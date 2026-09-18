/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * HTTPS Rpc smoke — product CA + HttpServer + HttpClient trust.
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
	class TestRpcHttpHttps : RpcTestAppBase
	{
		public TestRpcHttpHttps()
		{
			base("com.roojs.ollmchat.test-rpc-http-https");
		}

		protected override string get_app_name()
		{
			return "test-rpc-http-https";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			OLLMrpc.Request.rpc_register();
			OLLMrpc.Response.rpc_register();
			OLLMrpc.Error.rpc_register();
			OLLMrpc.Notification.rpc_register();
			RpcDummy.Hello.rpc_register();
			OLLMrpc.Request.register("RPC-Hello", new RpcDummy.Hello());

			var tls_dir = GLib.DirUtils.make_tmp("ollmrpc-https-XXXXXX");
			var ca_pem = GLib.Environment.get_variable("OLLM_RPC_CA_PEM");
			var ca_key = GLib.Environment.get_variable("OLLM_RPC_CA_KEY");
			this.check(command_line, ca_pem != null && ca_pem != "", "OLLM_RPC_CA_PEM");
			this.check(command_line, ca_key != null && ca_key != "", "OLLM_RPC_CA_KEY");
			var cert = new OLLMrpc.Transport.Cert() {
				dir = tls_dir,
				ca_pem_path = ca_pem,
				ca_key_path = ca_key,
				server_san = true,
			};
			cert.ensure();
			var http = new OLLMrpc.Transport.HttpServer(0) {
				tls_certificate = cert.certificate
			};
			this.check(command_line, http.start(), "https server start");
			var base_url = "https://localhost:%u".printf(http.port);

			var client = new OLLMrpc.Transport.HttpClient(base_url) {
				tls_database = cert.trust
			};
			OLLMrpc.Response? response = null;
			var err_msg = "";
			var loop = new GLib.MainLoop();
			client.call.begin(new OLLMrpc.Request() {
				method = "RPC-Hello.world"
			}, (obj, res) => {
				try {
					response = client.call.end(res);
				} catch (GLib.Error e) {
					err_msg = e.message;
				}
				loop.quit();
			});
			loop.run();
			this.check(command_line, err_msg == "", "https call error: %s".printf(err_msg));
			this.check(command_line, response != null, "https null response");
			this.check(
				command_line,
				response.msg == "Hello World",
				"https msg=%s".printf(response.msg)
			);
			this.check(
				command_line,
				client.session_id != "",
				"https missing session_id"
			);
			this.check(
				command_line,
				client.sequence == 1,
				"https sequence want 1 got %u".printf(client.sequence)
			);

			http.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcHttpHttps().run(args);
}
