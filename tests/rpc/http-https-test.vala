/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * HTTPS RPC smoke — generated CA + HttpServer + HttpClient trust.
 */

namespace RpcDummy
{
	public class Hello : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"Hello", typeof(Hello),
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
			OLLMrpc.Request.register("Hello", new RpcDummy.Hello());

			var tls_dir = GLib.DirUtils.make_tmp("ollmrpc-https-XXXXXX");
			var ca = new OLLMrpc.Transport.Cert() {
				dir = tls_dir,
				cert_pem = "server-ca.pem",
				key_pem = "server-ca-key.pem",
				cn = "OLLMrpc Test CA",
				certificate_authority = true,
			};
			ca.ensure();
			var ca_fingerprint = GLib.Checksum.compute_for_data(
				GLib.ChecksumType.SHA256, ca.certificate.certificate.data);
			ca.ensure();
			this.check(command_line, ca_fingerprint == GLib.Checksum.compute_for_data(
				GLib.ChecksumType.SHA256, ca.certificate.certificate.data),
				"reinitializing changed CA");
			var second_ca = new OLLMrpc.Transport.Cert() {
				dir = GLib.DirUtils.make_tmp("ollmrpc-https-second-XXXXXX"),
				cert_pem = "server-ca.pem",
				key_pem = "server-ca-key.pem",
				cn = "OLLMrpc Test CA",
				certificate_authority = true,
			};
			second_ca.ensure();
			this.check(command_line, ca_fingerprint != GLib.Checksum.compute_for_data(
				GLib.ChecksumType.SHA256, second_ca.certificate.certificate.data),
				"clean directories generated the same CA");
			var cert = new OLLMrpc.Transport.Cert() {
				dir = tls_dir,
				ca_pem_path = GLib.Path.build_filename(tls_dir, "server-ca.pem"),
				ca_key_path = GLib.Path.build_filename(tls_dir, "server-ca-key.pem"),
				server_san = true,
			};
			cert.ensure();
			var http = new OLLMrpc.Transport.HttpServer(0) {
				tls_certificate = cert.certificate
			};
			this.check(command_line, http.start(), "https server start");
			var base_url = "https://localhost:%u".printf(http.port);

			var leaf = new OLLMrpc.Transport.Cert() {
				dir = tls_dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
			};
			leaf.ensure();
			var client = new OLLMrpc.Transport.HttpClient(base_url) {
				tls_database = cert.trust,
				tls_certificate = leaf.certificate
			};
			OLLMrpc.Response? response = null;
			var err_msg = "";
			var loop = new GLib.MainLoop();
			client.call.begin(new OLLMrpc.Request() {
				method = "Hello.world"
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
