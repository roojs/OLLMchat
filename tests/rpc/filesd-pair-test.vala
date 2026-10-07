/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Manual TLS bin client against a live ollmfilesd. Sends
 * ClientCert.request_registration while the desktop PIN dialog
 * is open, writes the returned PEMs with Cert, then hello.
 */

namespace OLLMrpcTests
{
	class ApprovedClient : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public int64 id { get; set; default = 0; }
		public string fingerprint { get; set; default = ""; }
		public int status { get; set; default = 0; }
		public string ip { get; set; default = ""; }
		public int64 created { get; set; default = 0; }
		public string requester { get; set; default = ""; }
	}

	class TestRpcFilesdPair : RpcTestAppBase
	{
		protected static string opt_host = "";
		protected static int opt_port = 0;
		protected static string opt_pin = "";
		protected static bool opt_arm_only = false;
		protected static bool opt_list_approved = false;

		protected override string help { get; set; default = """
Usage: {ARG} [--host=IP] [--port=N] [--arm-only|--list-approved] [--pin=DIGITS]

Talk to a running ollmfilesd TLS bin listener while Allow New
Device is open. Reads client.csr from the app cert directory,
writes the signed cert and CA back, then RPC-Daemon.hello.

--arm-only sets the daemon PIN over its local Unix socket and exits.
--list-approved queries approved clients over the local Unix socket and exits.
"""; }

		public TestRpcFilesdPair()
		{
			base("com.roojs.ollmchat.test-rpc-filesd-pair");
		}

		protected override string get_app_name()
		{
			return "test-rpc-filesd-pair";
		}

		protected override OptionContext app_options()
		{
			var opt_context = new OptionContext(this.get_app_name());
			var entries = new OptionEntry[8];
			entries[0] = base_options[0];
			entries[1] = base_options[1];
			entries[2] = { "host", 0, 0, OptionArg.STRING, ref opt_host,
				"TLS bin host. Empty reads filesd.socket.", "IP" };
			entries[3] = { "port", 0, 0, OptionArg.INT, ref opt_port,
				"TLS bin port. 0 reads filesd.socket.", "N" };
			entries[4] = { "pin", 0, 0, OptionArg.STRING, ref opt_pin,
				"Six digits from Allow New Device.", "DIGITS" };
			entries[5] = { "arm-only", 0, 0, OptionArg.NONE, ref opt_arm_only,
				"Set the daemon PIN over its local Unix socket and exit.", null };
			entries[6] = { "list-approved", 0, 0, OptionArg.NONE, ref opt_list_approved,
				"List approved clients over the local Unix socket and exit.", null };
			entries[7] = { null };
			opt_context.add_main_entries(entries, null);
			return opt_context;
		}

		protected override void run_rpc_test(GLib.ApplicationCommandLine command_line) throws Error
		{
			OLLMrpc.Request.rpc_register();
			OLLMrpc.Response.rpc_register();
			OLLMrpc.Error.rpc_register();
			OLLMrpc.Notification.rpc_register();
			OLLMrpc.Daemon.rpc_register();
			OLLMrpc.Bin.register("ClientCert", typeof(ApprovedClient));

			var host = opt_host;
			var port = opt_port;
			if (host == "" || port == 0) {
				var socket = this.base_load_config().filesd.socket;
				var colon = socket.last_index_of(":");
				this.check(command_line, colon > 0, "filesd.socket has no port");
				if (host == "") {
					host = socket.substring(0, colon);
				}
				if (port == 0) {
					this.check(command_line,
						int.try_parse(socket.substring(colon + 1), out port),
						"filesd.socket port");
				}
			}
			if (opt_arm_only || opt_list_approved) {
				var local = new GLib.SocketClient().connect(
					new GLib.UnixSocketAddress(GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "ollmchat", "ollmfilesd.sock"))
				);
				var local_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(local.get_input_stream()),
					new GLib.DataOutputStream(local.get_output_stream())
				);
				if (opt_list_approved) {
					local_bin.write(new OLLMrpc.Request() {
						id = 1,
						method = "ClientCert.approved_certs"
					});
					var approved = local_bin.parse() as OLLMrpc.Response;
					this.check(command_line, approved != null, "approved reply was not a response");
					this.check(command_line, approved.error == null,
						approved.error != null ? approved.error.message : "");
					var clients = (Gee.ArrayList<ApprovedClient>) approved.retval.get_object();
					foreach (var approved_client in clients) {
						command_line.print("%" + int64.FORMAT + " %s %s\n", approved_client.id,
							approved_client.fingerprint, approved_client.requester);
					}
					command_line.print("approved clients: %d\n", clients.size);
					return;
				}
				this.check(command_line, opt_pin != "", "--pin is required");
				local_bin.write(new OLLMrpc.Request() {
					id = 1,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", opt_pin)
				});
				var armed = local_bin.parse() as OLLMrpc.Response;
				this.check(command_line, armed != null, "pair reply was not a response");
				this.check(command_line, armed.error == null,
					armed.error != null ? armed.error.message : "");
				command_line.print("pair armed with %s\n", opt_pin);
				return;
			}
			this.check(command_line, opt_pin != "", "--pin is required");
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var tls_files = new OLLMrpc.Transport.Cert() {
				dir = dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
			};
			tls_files.ensure();
			var csr = "";
			var csr_path = GLib.Path.build_filename(dir, "client.csr");
			this.check(command_line,
				GLib.FileUtils.get_contents(csr_path, out csr),
				"read " + csr_path);

			var client = new GLib.SocketClient();
			var conn = client.connect_to_host(host, (uint16) port);
			var tls = GLib.TlsClientConnection.@new(conn, null);
			tls.accept_certificate.connect((peer_cert, errors) => {
				return true;
			});
			tls.handshake();
			var bin = new OLLMrpc.Bin.Stream(
				new GLib.DataInputStream(tls.get_input_stream()),
				new GLib.DataOutputStream(tls.get_output_stream())
			);
			bin.write(new OLLMrpc.Request() {
				method = "ClientCert.request_registration",
				args = OLLMrpc.args("sss", opt_pin, csr, "ollmchat")
			});
			var response = bin.parse() as OLLMrpc.Response;
			this.check(command_line, response != null, "reply was not a response");
			if (response.error != null) {
				command_line.print("%s\n", response.error.message);
				return;
			}
			this.check(command_line, response.msg == "ok", "msg=" + response.msg);
			var packed = (string[]) response.retval;
			this.check(command_line, packed.length >= 2,
				"reply needs a client cert and a CA");
			GLib.FileUtils.set_contents(
				GLib.Path.build_filename(dir, "client.pem"), packed[0]);
			GLib.FileUtils.set_contents(
				GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), packed[1]);
			tls_files.ensure();
			for (var i = 2; i < packed.length; i++) {
				command_line.print("address %s\n", packed[i]);
			}

			var again = client.connect_to_host(host, (uint16) port);
			var tls2 = GLib.TlsClientConnection.@new(again, null);
			tls2.certificate = tls_files.certificate;
			tls2.database = tls_files.trust;
			tls2.accept_certificate.connect((peer_cert, errors) => {
				return peer_cert != null
					&& (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
			});
			tls2.handshake();
			var bin2 = new OLLMrpc.Bin.Stream(
				new GLib.DataInputStream(tls2.get_input_stream()),
				new GLib.DataOutputStream(tls2.get_output_stream())
			);
			bin2.write(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "ollmchat")
			});
			var hello = bin2.parse() as OLLMrpc.Response;
			this.check(command_line, hello != null, "hello was not a response");
			this.check(command_line, hello.error == null,
				hello.error != null ? hello.error.message : "");
			command_line.print("hello ok\n");
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcFilesdPair().run(args);
}
