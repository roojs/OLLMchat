/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * HTTP Rpc Transport.HttpClient smoke — types here are NOT shipped in libocrpc.
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
	class TestRpcHttpClient : RpcTestAppBase
	{
		public TestRpcHttpClient()
		{
			base("com.roojs.ollmchat.test-rpc-http-client");
		}

		protected override string get_app_name()
		{
			return "test-rpc-http-client";
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
			var base_url = "http://127.0.0.1:%u".printf(http.port);

			var json_client = new OLLMrpc.Transport.HttpClient(base_url);
			OLLMrpc.Response? response = null;
			var err_msg = "";
			var loop = new GLib.MainLoop();
			json_client.call.begin(new OLLMrpc.Request() {
				method = "RPC-Hello.world"
			}, (obj, res) => {
				try {
					response = json_client.call.end(res);
				} catch (GLib.Error e) {
					err_msg = e.message;
				}
				loop.quit();
			});
			loop.run();
			this.check(command_line, err_msg == "", "json1 error: %s".printf(err_msg));
			this.check(command_line, response != null, "json1 null response");
			this.check(
				command_line,
				response.msg == "Hello World",
				"json1 msg=%s".printf(response.msg)
			);
			this.check(
				command_line,
				json_client.session_id != "",
				"json1 missing session_id"
			);
			this.check(
				command_line,
				json_client.sequence == 1,
				"json1 sequence want 1 got %u".printf(json_client.sequence)
			);

			response = null;
			err_msg = "";
			loop = new GLib.MainLoop();
			json_client.call.begin(new OLLMrpc.Request() {
				method = "RPC-Hello.world"
			}, (obj, res) => {
				try {
					response = json_client.call.end(res);
				} catch (GLib.Error e) {
					err_msg = e.message;
				}
				loop.quit();
			});
			loop.run();
			this.check(command_line, err_msg == "", "json2 error: %s".printf(err_msg));
			this.check(
				command_line,
				json_client.sequence == 2,
				"json2 sequence want 2 got %u".printf(json_client.sequence)
			);

			var bin_client = new OLLMrpc.Transport.HttpClient(base_url) {
				bin_body = true
			};
			response = null;
			err_msg = "";
			loop = new GLib.MainLoop();
			bin_client.call.begin(new OLLMrpc.Request() {
				method = "RPC-Hello.world"
			}, (obj, res) => {
				try {
					response = bin_client.call.end(res);
				} catch (GLib.Error e) {
					err_msg = e.message;
				}
				loop.quit();
			});
			loop.run();
			this.check(command_line, err_msg == "", "bin1 error: %s".printf(err_msg));
			this.check(command_line, response != null, "bin1 null response");
			this.check(
				command_line,
				response.msg == "Hello World",
				"bin1 msg=%s".printf(response.msg)
			);
			this.check(
				command_line,
				bin_client.session_id != "",
				"bin1 missing session_id"
			);
			this.check(
				command_line,
				bin_client.sequence == 1,
				"bin1 sequence want 1 got %u".printf(bin_client.sequence)
			);
			var bin_sid = bin_client.session_id;

			response = null;
			err_msg = "";
			loop = new GLib.MainLoop();
			bin_client.call.begin(new OLLMrpc.Request() {
				method = "RPC-Hello.world"
			}, (obj, res) => {
				try {
					response = bin_client.call.end(res);
				} catch (GLib.Error e) {
					err_msg = e.message;
				}
				loop.quit();
			});
			loop.run();
			this.check(command_line, err_msg == "", "bin2 (JIT) error: %s".printf(err_msg));
			this.check(
				command_line,
				bin_client.sequence == 2,
				"bin2 sequence want 2 got %u".printf(bin_client.sequence)
			);

			bin_client.reset();
			response = null;
			err_msg = "";
			loop = new GLib.MainLoop();
			bin_client.call.begin(new OLLMrpc.Request() {
				method = "RPC-Hello.world"
			}, (obj, res) => {
				try {
					response = bin_client.call.end(res);
				} catch (GLib.Error e) {
					err_msg = e.message;
				}
				loop.quit();
			});
			loop.run();
			this.check(command_line, err_msg == "", "bin reset error: %s".printf(err_msg));
			this.check(
				command_line,
				bin_client.session_id == bin_sid,
				"bin reset session_id changed"
			);
			this.check(
				command_line,
				bin_client.sequence == 1,
				"bin reset sequence want 1 got %u".printf(bin_client.sequence)
			);

			bin_client.session_id = "not-a-real-session";
			response = null;
			err_msg = "";
			var threw_409 = false;
			loop = new GLib.MainLoop();
			bin_client.call.begin(new OLLMrpc.Request() {
				method = "RPC-Hello.world"
			}, (obj, res) => {
				try {
					response = bin_client.call.end(res);
				} catch (GLib.Error e) {
					err_msg = e.message;
					threw_409 = e.message.contains("409");
				}
				loop.quit();
			});
			loop.run();
			this.check(
				command_line,
				threw_409,
				"bogus session want 409 got: %s".printf(err_msg)
			);

			http.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcHttpClient().run(args);
}
