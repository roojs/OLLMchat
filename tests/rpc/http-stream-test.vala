/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * HTTP binary streaming + preemptive request headers smoke test —
 * types here are NOT shipped in libocrpc.
 */

namespace RpcDummy
{
	public class AuthHttpServer : OLLMrpc.Transport.HttpServer
	{
		public string expected_auth { get; set; default = ""; }
		public int auth_checked { get; set; default = 0; }

		public AuthHttpServer(uint port = 0)
		{
			base(port);
		}

		protected override bool allow_rpc(OLLMrpc.Transport.HttpReply reply, OLLMrpc.Request request)
		{
			this.auth_checked++;
			var auth = reply.msg.get_request_headers().get_one("Authorization");
			if (auth == null || auth != this.expected_auth) {
				reply.msg.set_status(401, null);
				reply.msg.set_response("text/plain", Soup.MemoryUse.COPY, "unauthorized".data);
				reply.finished = true;
				return false;
			}
			return true;
		}
	}

	public class StreamHello : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class("Hello", typeof(StreamHello), "world", "");
		}

		public void world(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				msg = "Hello World"
			});
		}
	}

	public class Events : GLib.Object
	{
		public bool server_closed { get; set; default = false; }

		public static void rpc_register()
		{
			OLLMrpc.Http.routes("Events", typeof(Events),
				"/events", "GET", "stream", "", typeof(void), typeof(void));
		}

		public void stream(OLLMrpc.Request request)
		{
			var reply = request.connection as OLLMrpc.Transport.HttpReply;
			reply.bin_body = true;
			reply.closed.connect(() => {
				this.server_closed = true;
			});
			reply.write(new OLLMrpc.Notification() {
				method = "ready",
				message = "ok"
			});
			GLib.Timeout.add(50, () => {
				if (!reply.finished) {
					reply.write(new OLLMrpc.Notification() {
						method = "ping",
						message = "tick"
					});
				}
				return false;
			});
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcHttpStream : RpcTestAppBase
	{
		public TestRpcHttpStream()
		{
			base("com.roojs.ollmchat.test-rpc-http-stream");
		}

		protected override string get_app_name()
		{
			return "test-rpc-http-stream";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			OLLMrpc.Request.rpc_register();
			OLLMrpc.Response.rpc_register();
			OLLMrpc.Error.rpc_register();
			OLLMrpc.Notification.rpc_register();
			RpcDummy.StreamHello.rpc_register();
			RpcDummy.Events.rpc_register();

			var events = new RpcDummy.Events();
			OLLMrpc.Request.register("Hello", new RpcDummy.StreamHello());
			OLLMrpc.Request.register("Events", events);

			var auth_value = "Basic dGVzdDpzZWNyZXQ=";
			var http = new RpcDummy.AuthHttpServer(0) {
				expected_auth = auth_value
			};
			this.check(command_line, http.start(), "http server start");
			var base_url = "http://127.0.0.1:%u".printf(http.port);

			var unauth_client = new OLLMrpc.Transport.HttpClient(base_url) {
				bin_body = true
			};
			var unauth_401 = false;
			var unauth_err = "";
			var loop = new GLib.MainLoop();
			unauth_client.call.begin(new OLLMrpc.Request() {
				method = "Hello.world"
			}, (obj, res) => {
				try {
					unauth_client.call.end(res);
				} catch (GLib.Error e) {
					unauth_err = e.message;
					unauth_401 = e.message.contains("401");
				}
				loop.quit();
			});
			loop.run();
			this.check(command_line, unauth_401, "unauthenticated call want 401 got: %s".printf(unauth_err));

			var rpc_client = new OLLMrpc.Transport.HttpClient(base_url) {
				bin_body = true
			};
			rpc_client.headers.set("Authorization", auth_value);

			var stream = new OLLMrpc.Transport.HttpStream(base_url + "/events");
			stream.headers.set("Authorization", auth_value);

			var received = new Gee.ArrayList<OLLMrpc.Notification>();
			var stream_closed = false;
			var closed_reason = "";
			var rpc_msg = "";
			var rpc_err = "";
			var rpc_done = false;
			loop = new GLib.MainLoop();

			var timed_out = false;
			var timeout_id = GLib.Timeout.add(4000, () => {
				timed_out = true;
				loop.quit();
				return false;
			});

			stream.received.connect((obj) => {
				var notif = obj as OLLMrpc.Notification;
				if (notif != null) {
					received.add(notif);
				}
				if (received.size == 1) {
					rpc_client.call.begin(new OLLMrpc.Request() {
						method = "Hello.world"
					}, (o, r) => {
						try {
							var resp = rpc_client.call.end(r);
							rpc_msg = resp.msg;
						} catch (GLib.Error e) {
							rpc_err = e.message;
						}
						rpc_done = true;
						if (stream_closed && events.server_closed) {
							loop.quit();
						}
					});
				}
				if (received.size == 2) {
					stream.close();
				}
			});
			stream.closed.connect((reason) => {
				stream_closed = true;
				closed_reason = reason;
				GLib.Timeout.add(20, () => {
					if (rpc_done && events.server_closed) {
						loop.quit();
						return false;
					}
					return true;
				});
			});

			stream.open.begin();
			loop.run();
			if (!timed_out) {
				GLib.Source.remove(timeout_id);
			}
			this.check(command_line, !timed_out,
				"stream test timed out (frames=%d rpc_done=%s stream_closed=%s reason=%s server_closed=%s)".printf(
					received.size, rpc_done.to_string(), stream_closed.to_string(),
					closed_reason, events.server_closed.to_string()));

			this.check(command_line, received.size == 2, "stream want 2 frames got %d".printf(received.size));
			this.check(command_line, received.get(0).method == "ready" && received.get(0).message == "ok",
				"frame 0 want ready/ok got %s/%s".printf(received.get(0).method, received.get(0).message));
			this.check(command_line, received.get(1).method == "ping" && received.get(1).message == "tick",
				"frame 1 want ping/tick got %s/%s".printf(received.get(1).method, received.get(1).message));
			this.check(command_line, rpc_done && rpc_err == "", "concurrent bin RPC error: %s".printf(rpc_err));
			this.check(command_line, rpc_msg == "Hello World",
				"concurrent bin RPC want Hello World got %s".printf(rpc_msg));
			this.check(command_line, stream_closed && closed_reason == "closed",
				"stream closed want closed got %s".printf(closed_reason));
			this.check(command_line, events.server_closed, "server HttpReply.closed did not fire");

			http.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcHttpStream().run(args);
}
