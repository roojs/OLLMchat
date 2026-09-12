/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * HTTP bin RPC + session smoke — types here are NOT shipped in libocrpc.
 */

namespace RpcDummy
{
	public class Hello : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Hello", typeof(Hello),
				"world", ""
			);
		}

		public void world(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				msg = "Hello World"
			});
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcHttpBinSession : RpcTestAppBase
	{
		public TestRpcHttpBinSession()
		{
			base("com.roojs.ollmchat.test-rpc-http-bin-session");
		}

		protected override string get_app_name()
		{
			return "test-rpc-http-bin-session";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			OLLMrpc.Request.rpc_register();
			OLLMrpc.Response.rpc_register();
			OLLMrpc.Error.rpc_register();
			OLLMrpc.Notification.rpc_register();
			RpcDummy.Hello.rpc_register();
			OLLMrpc.Request.register("RPC-Hello", new RpcDummy.Hello());

			var http = new OLLMrpc.Transport.HttpServer(0);
			this.check(command_line, http.start(), "http server start");

			var soup = new Soup.Session();
			var client_bin = new OLLMrpc.Bin.Stream(null, null);
			client_bin.mode = OLLMrpc.Bin.Mode.EXPLICIT;

			var mem = new GLib.MemoryOutputStream.resizable();
			client_bin.out_stream = new GLib.DataOutputStream(mem);
			client_bin.write(new OLLMrpc.Request() {
				id = 1,
				method = "RPC-Hello.world"
			});
			client_bin.out_stream.close();
			client_bin.out_stream = null;
			var body1 = mem.steal_as_bytes();

			var msg1 = new Soup.Message(
				"POST",
				"http://127.0.0.1:%u/rpc".printf(http.port)
			);
			msg1.set_request_body_from_bytes("application/octet-stream", body1);
			var status = 0u;
			GLib.Bytes? resp_bytes = null;
			var loop = new GLib.MainLoop();
			soup.send_and_read_async.begin(
				msg1, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						resp_bytes = soup.send_and_read_async.end(res);
						status = msg1.status_code;
					} catch (GLib.Error e) {
						command_line.print("post1 error: %s\n", e.message);
					}
					loop.quit();
				}
			);
			loop.run();
			this.check(command_line, status == 200, "post1 status %u".printf(status));
			var session_id = msg1.get_response_headers().get_one("X-rpc-session");
			var seq_hdr = msg1.get_response_headers().get_one("X-rpc-sequence");
			this.check(
				command_line,
				session_id != null && session_id != "",
				"post1 missing X-rpc-session"
			);
			this.check(command_line, seq_hdr == "1", "post1 sequence want 1 got %s".printf(
				seq_hdr != null ? seq_hdr : "(null)"));
			client_bin.in_stream = new GLib.DataInputStream(
				new GLib.MemoryInputStream.from_bytes(resp_bytes)
			);
			var resp1 = client_bin.parse() as OLLMrpc.Response;
			client_bin.in_stream = null;
			this.check(command_line, resp1 != null, "post1 response null");
			this.check(
				command_line,
				resp1.msg == "Hello World",
				"post1 msg=%s".printf(resp1.msg)
			);

			mem = new GLib.MemoryOutputStream.resizable();
			client_bin.out_stream = new GLib.DataOutputStream(mem);
			client_bin.write(new OLLMrpc.Request() {
				id = 2,
				method = "RPC-Hello.world"
			});
			client_bin.out_stream.close();
			client_bin.out_stream = null;
			var body2 = mem.steal_as_bytes();
			var msg2 = new Soup.Message(
				"POST",
				"http://127.0.0.1:%u/rpc".printf(http.port)
			);
			msg2.set_request_body_from_bytes("application/octet-stream", body2);
			msg2.get_request_headers().replace("X-rpc-session", session_id);
			msg2.get_request_headers().replace("X-rpc-sequence", "1");
			status = 0u;
			resp_bytes = null;
			loop = new GLib.MainLoop();
			soup.send_and_read_async.begin(
				msg2, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						resp_bytes = soup.send_and_read_async.end(res);
						status = msg2.status_code;
					} catch (GLib.Error e) {
						command_line.print("post2 error: %s\n", e.message);
					}
					loop.quit();
				}
			);
			loop.run();
			this.check(
				command_line,
				status == 200,
				"post2 (JIT reuse) status %u".printf(status)
			);
			seq_hdr = msg2.get_response_headers().get_one("X-rpc-sequence");
			this.check(command_line, seq_hdr == "2", "post2 sequence want 2 got %s".printf(
				seq_hdr != null ? seq_hdr : "(null)"));

			var bad_seq = new Soup.Message(
				"POST",
				"http://127.0.0.1:%u/rpc".printf(http.port)
			);
			bad_seq.set_request_body_from_bytes("application/octet-stream", body2);
			bad_seq.get_request_headers().replace("X-rpc-session", session_id);
			bad_seq.get_request_headers().replace("X-rpc-sequence", "99");
			status = 0u;
			loop = new GLib.MainLoop();
			soup.send_and_read_async.begin(
				bad_seq, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						soup.send_and_read_async.end(res);
						status = bad_seq.status_code;
					} catch (GLib.Error e) {
						command_line.print("bad_seq error: %s\n", e.message);
					}
					loop.quit();
				}
			);
			loop.run();
			this.check(command_line, status == 409, "wrong sequence want 409 got %u".printf(status));

			var bad_sid = new Soup.Message(
				"POST",
				"http://127.0.0.1:%u/rpc".printf(http.port)
			);
			bad_sid.set_request_body_from_bytes("application/octet-stream", body2);
			bad_sid.get_request_headers().replace("X-rpc-session", "not-a-real-session");
			bad_sid.get_request_headers().replace("X-rpc-sequence", "0");
			status = 0u;
			loop = new GLib.MainLoop();
			soup.send_and_read_async.begin(
				bad_sid, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						soup.send_and_read_async.end(res);
						status = bad_sid.status_code;
					} catch (GLib.Error e) {
						command_line.print("bad_sid error: %s\n", e.message);
					}
					loop.quit();
				}
			);
			loop.run();
			this.check(command_line, status == 409, "unknown session want 409 got %u".printf(status));

			var fresh = new OLLMrpc.Bin.Stream(null, null);
			fresh.mode = OLLMrpc.Bin.Mode.EXPLICIT;
			mem = new GLib.MemoryOutputStream.resizable();
			fresh.out_stream = new GLib.DataOutputStream(mem);
			fresh.write(new OLLMrpc.Request() {
				id = 3,
				method = "RPC-Hello.world"
			});
			fresh.out_stream.close();
			fresh.out_stream = null;
			var body_reset = mem.steal_as_bytes();
			var msg_reset = new Soup.Message(
				"POST",
				"http://127.0.0.1:%u/rpc".printf(http.port)
			);
			msg_reset.set_request_body_from_bytes("application/octet-stream", body_reset);
			msg_reset.get_request_headers().replace("X-rpc-session", session_id);
			msg_reset.get_request_headers().replace("X-rpc-sequence", "-1");
			status = 0u;
			resp_bytes = null;
			loop = new GLib.MainLoop();
			soup.send_and_read_async.begin(
				msg_reset, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						resp_bytes = soup.send_and_read_async.end(res);
						status = msg_reset.status_code;
					} catch (GLib.Error e) {
						command_line.print("reset error: %s\n", e.message);
					}
					loop.quit();
				}
			);
			loop.run();
			this.check(command_line, status == 200, "reset status %u".printf(status));
			seq_hdr = msg_reset.get_response_headers().get_one("X-rpc-sequence");
			this.check(command_line, seq_hdr == "1", "reset sequence want 1 got %s".printf(
				seq_hdr != null ? seq_hdr : "(null)"));

			var msg_stale_jit = new Soup.Message(
				"POST",
				"http://127.0.0.1:%u/rpc".printf(http.port)
			);
			msg_stale_jit.set_request_body_from_bytes("application/octet-stream", body2);
			msg_stale_jit.get_request_headers().replace("X-rpc-session", session_id);
			msg_stale_jit.get_request_headers().replace("X-rpc-sequence", "1");
			status = 0u;
			loop = new GLib.MainLoop();
			soup.send_and_read_async.begin(
				msg_stale_jit, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						soup.send_and_read_async.end(res);
						status = msg_stale_jit.status_code;
					} catch (GLib.Error e) {
						command_line.print("stale_jit error: %s\n", e.message);
					}
					loop.quit();
				}
			);
			loop.run();
			this.check(
				command_line,
				status == 400,
				"stale JIT after reset want 400 got %u".printf(status)
			);

			http.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcHttpBinSession().run(args);
}
