/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * HTTP JSON RPC smoke — types here are NOT shipped in libocrpc.
 */

namespace RpcDummy
{
	public class Hello : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Hello", typeof(Hello),
				"world", "",
				"stream", ""
			);
		}

		public void world(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				msg = "Hello World"
			});
		}

		public void stream(OLLMrpc.Request request)
		{
			request.connection.write(new OLLMrpc.Notification() {
				method = "token",
				message = "Hel"
			});
			request.connection.write(new OLLMrpc.Notification() {
				method = "token",
				message = "lo"
			});
			request.reply(new OLLMrpc.Response() {
				msg = "done"
			});
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcHttpServer : RpcTestAppBase
	{
		public TestRpcHttpServer()
		{
			base("com.roojs.ollmchat.test-rpc-http-server");
		}

		protected override string get_app_name()
		{
			return "test-rpc-http-server";
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

			var session = new Soup.Session();
			var unary = new Soup.Message(
				"POST",
				"http://127.0.0.1:%u/rpc".printf(http.port)
			);
			unary.set_request_body_from_bytes(
				"application/json",
				new GLib.Bytes("{\"id\":1,\"method\":\"RPC-Hello.world\",\"args\":[]}".data)
			);
			var status = 0u;
			var text = "";
			var loop = new GLib.MainLoop();
			session.send_and_read_async.begin(
				unary, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						var bytes = session.send_and_read_async.end(res);
						status = unary.status_code;
						text = (string) bytes.get_data();
					} catch (GLib.Error e) {
						text = e.message;
					}
					loop.quit();
				}
			);
			loop.run();
			this.check(
				command_line,
				status == 200,
				"unary status %u body=%s".printf(status, text)
			);
			this.check(
				command_line,
				text.contains("Hello World"),
				"unary missing Hello World: %s".printf(text)
			);

			var stream_msg = new Soup.Message(
				"POST",
				"http://127.0.0.1:%u/rpc".printf(http.port)
			);
			stream_msg.set_request_body_from_bytes(
				"application/json",
				new GLib.Bytes("{\"id\":2,\"method\":\"RPC-Hello.stream\",\"args\":[]}".data)
			);
			status = 0u;
			text = "";
			loop = new GLib.MainLoop();
			session.send_and_read_async.begin(
				stream_msg, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						var bytes = session.send_and_read_async.end(res);
						status = stream_msg.status_code;
						text = (string) bytes.get_data();
					} catch (GLib.Error e) {
						text = e.message;
					}
					loop.quit();
				}
			);
			loop.run();
			this.check(
				command_line,
				status == 200,
				"stream status %u body=%s".printf(status, text)
			);
			this.check(command_line, text.contains("Hel"), "stream missing Hel: %s".printf(text));
			this.check(command_line, text.contains("lo"), "stream missing lo: %s".printf(text));
			this.check(command_line, text.contains("done"), "stream missing done: %s".printf(text));
			http.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcHttpServer().run(args);
}
