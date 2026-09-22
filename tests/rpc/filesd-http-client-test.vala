/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Manual HTTPS client against a live ollmfilesd (systemd). Default
 * sends RPC-ClientCert.request_registration; --hello sends
 * RPC-Daemon.hello after desktop Accept.
 */

namespace OLLMrpcTests
{
	class TestRpcFilesdHttpClient : RpcTestAppBase
	{
		protected static bool opt_hello = false;

		protected override string help { get; set; default = """
Usage: {ARG} [--url=https://host:port] [--hello]

Talk to a running ollmfilesd HTTPS listener (systemd user unit).
Mints a throwaway client cert under
~/.cache/ollmchat/testing/filesd-http-client.

  {ARG} --url=https://192.168.1.10:8443
      Send RPC-ClientCert.request_registration. Accept the pending
      request on the desktop Connections banner.

  {ARG} --url=https://192.168.1.10:8443 --hello
      Send RPC-Daemon.hello with the same cert (after Accept).

Without --url, uses https:// plus filesd.https from
~/.config/ollmchat/config.2.json.
"""; }

		public TestRpcFilesdHttpClient()
		{
			base("com.roojs.ollmchat.test-rpc-filesd-http-client");
		}

		protected override string get_app_name()
		{
			return "test-rpc-filesd-http-client";
		}

		protected override OptionContext app_options()
		{
			var opt_context = new OptionContext(this.get_app_name());
			var opts = new OptionEntry[5];
			opts[0] = base_options[0];
			opts[1] = base_options[1];
			opts[2] = { "url", 0, 0, OptionArg.STRING, ref opt_url, "File server HTTPS URL", "URL" };
			opts[3] = { "hello", 0, 0, OptionArg.NONE, ref opt_hello, "Send RPC-Daemon.hello after desktop Accept", null };
			opts[4] = { null };
			opt_context.add_main_entries(opts, null);
			return opt_context;
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			OLLMrpc.Request.rpc_register();
			OLLMrpc.Response.rpc_register();
			OLLMrpc.Error.rpc_register();
			OLLMrpc.Notification.rpc_register();
			OLLMrpc.Daemon.rpc_register();

			var url = opt_url != null ? opt_url : "";
			if (url == "") {
				url = this.base_load_config().filesd.https;
				if (url != "" && !url.has_prefix("https://")) {
					url = "https://" + url;
				}
			}
			this.check(
				command_line,
				url != "",
				"need --url or filesd.https in config.2.json"
			);
			if (!url.has_prefix("https://")) {
				this.fail(command_line, "URL must start with https://: " + url);
			}

			var tls = new OLLMrpc.Transport.Cert() {
				dir = GLib.Path.build_filename(
					GLib.Environment.get_user_cache_dir(),
					"ollmchat", "testing", "filesd-http-client"),
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
				product_ca_resource = true,
			};
			tls.ensure();
			var http = new OLLMrpc.Transport.HttpClient(url) {
				bin_body = true,
				tls_certificate = tls.certificate,
				tls_database = tls.trust
			};

			var request = new OLLMrpc.Request() {
				method = "RPC-ClientCert.request_registration",
				args = OLLMrpc.args("s", "test-rpc-filesd-http-client")
			};
			if (opt_hello) {
				request = new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "test-rpc-filesd-http-client")
				};
			}

			OLLMrpc.Response? response = null;
			var err_msg = "";
			var loop = new GLib.MainLoop();
			http.call.begin(request, (obj, res) => {
				try {
					response = http.call.end(res);
				} catch (GLib.Error e) {
					err_msg = e.message;
				}
				loop.quit();
			});
			loop.run();
			this.check(command_line, err_msg == "", "%s error: %s".printf(request.method, err_msg));
			this.check(command_line, response != null, "%s null response".printf(request.method));

			if (opt_hello) {
				this.check(
					command_line,
					response.retval.get_object() is OLLMrpc.Daemon,
					"hello retval not Daemon"
				);
				var daemon = (OLLMrpc.Daemon) response.retval.get_object();
				command_line.print("hello ok server=%s ready=%s protocol=%d session=%s\n",
					daemon.server, daemon.ready.to_string(), daemon.protocol, http.session_id);
				return;
			}

			this.check(
				command_line,
				response.msg == "ok",
				"request_registration msg=%s".printf(response.msg)
			);
			command_line.print("request_registration ok session=%s\nAccept on the desktop, then re-run with --hello\n",
				http.session_id);
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcFilesdHttpClient().run(args);
}
