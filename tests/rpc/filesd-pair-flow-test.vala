/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Regression for the phone pairing flow. Starts this tree's
 * ollmfilesd and drives FilesdClient.try_connection: PIN register,
 * stored certificate, unregistered certificate, delete, and re-pair.
 */

namespace OLLMrpcTests
{
	class TestRpcFilesdPairFlow : RpcTestAppBase
	{
		public TestRpcFilesdPairFlow()
		{
			base("com.roojs.ollmchat.test-rpc-filesd-pair-flow");
		}

		protected override string get_app_name()
		{
			return "test-rpc-filesd-pair-flow";
		}

		protected override void run_rpc_test(
			GLib.ApplicationCommandLine command_line
		) throws GLib.Error
		{
			var client = new OLLMchat.Settings.FilesdClient();
			this.check(command_line, client.state.label() == "Requested",
				"requested label");
			client.state = OLLMchat.Settings.FilesdClient.State.DISABLED;
			this.check(command_line, client.state.label() == "Disabled",
				"disabled label");
			client.state = OLLMchat.Settings.FilesdClient.State.UNREACHABLE;
			this.check(command_line, client.state.label() == "Unreachable",
				"unreachable label");
			client.state = OLLMchat.Settings.FilesdClient.State.ENABLED;
			this.check(command_line, client.state.label() == "Active",
				"enabled label");
			client.state = OLLMchat.Settings.FilesdClient.State.LIVE;
			this.check(command_line, client.state.label() == "Active",
				"live label");
			client.state = OLLMchat.Settings.FilesdClient.State.SOCKET;
			this.check(command_line, client.state.label() == "Active",
				"socket label");
			client.remove();

			var exe = "";
			var exe_env = GLib.Environment.get_variable("OLLMFILESD");
			if (exe_env != null) {
				exe = exe_env;
			}
			this.check(command_line, exe != "", "OLLMFILESD is not set");
			var root = "";
			var root_env = GLib.Environment.get_variable("OLLM_PAIR_FLOW_HOME");
			if (root_env != null) {
				root = root_env;
			}
			this.check(command_line, root != "", "OLLM_PAIR_FLOW_HOME is not set");
			var daemon_dir = GLib.Path.build_filename(root, "daemon");
			GLib.DirUtils.create_with_parents(daemon_dir, 0700);
			var err_path = GLib.Path.build_filename(root, "daemon.err");
			var launcher = new GLib.SubprocessLauncher(GLib.SubprocessFlags.NONE);
			launcher.setenv("OLLMFILES_IS_TEST", "1", true);
			launcher.setenv("OLLMFILESD_DAEMON", "1", true);
			launcher.set_stderr_file_path(err_path);
			var daemon = launcher.spawnv({
				exe,
				"--data-dir=" + daemon_dir,
				"--socket=0.0.0.0:18422"
			});
			try {
				OLLMrpc.Request.rpc_register();
				OLLMrpc.Response.rpc_register();
				OLLMrpc.Error.rpc_register();
				OLLMrpc.Notification.rpc_register();
				OLLMrpc.Daemon.rpc_register();

				var sock = GLib.Path.build_filename(daemon_dir, "ollmfilesd.sock");
				var ready = false;
				var deadline = GLib.get_monotonic_time() + 10 * 1000000;
				while (GLib.get_monotonic_time() < deadline) {
					if (GLib.FileUtils.test(sock, GLib.FileTest.EXISTS)) {
						try {
							var probe = new GLib.SocketClient();
							probe.timeout = 1;
							var probed = probe.connect_to_host("127.0.0.1", 18422);
							probed.close();
							ready = true;
							break;
						} catch (GLib.Error e) {
						}
					}
					GLib.Thread.usleep(100000);
				}
				var err_text = "";
				try {
					GLib.FileUtils.get_contents(err_path, out err_text);
				} catch (GLib.Error e) {
				}
				this.check(command_line, ready,
					"daemon did not listen: " + err_text);

				var phone = new OLLMchat.Settings.FilesdClient();
				phone.server_id = "dfbfedc5-7de0-460f-bfca-06e65357b036";
				var cert_dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat", phone.server_id);
				var local = new GLib.SocketClient().connect(
					new GLib.UnixSocketAddress(sock));
				var local_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(local.get_input_stream()),
					new GLib.DataOutputStream(local.get_output_stream())
				);
				local_bin.write(new OLLMrpc.Request() {
					id = 1,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", "159264")
				});
				var armed = local_bin.parse() as OLLMrpc.Response;
				this.check(command_line, armed != null, "pair reply was not a response");
				this.check(command_line, armed.error == null,
					armed.error != null ? armed.error.message : "pair failed");
				var force_register = false;
				var code = 0;
				while (true) {
					code = phone.try_connection(
						"127.0.0.1", 18422, "159264", force_register, "ollmchat");
					if (code == (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED
						&& !force_register) {
						force_register = true;
						continue;
					}
					break;
				}
				this.check(command_line, code == 0,
					"first pair code " + code.to_string());
				this.check(command_line, !force_register,
					"first pair retried registration");
				this.check(command_line, phone.url == "tcp://127.0.0.1:18422",
					"first pair url " + phone.url);
				this.check(command_line, phone.addresses.contains("18422"),
					"first pair addresses " + phone.addresses);
				phone.state = OLLMchat.Settings.FilesdClient.State.ENABLED;
				this.check(command_line, phone.state.label() == "Active",
					"paired row");

				var again = new GLib.SocketClient().connect(
					new GLib.UnixSocketAddress(sock));
				var again_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(again.get_input_stream()),
					new GLib.DataOutputStream(again.get_output_stream())
				);
				again_bin.write(new OLLMrpc.Request() {
					id = 2,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", "159264")
				});
				var rearmed = again_bin.parse() as OLLMrpc.Response;
				this.check(command_line, rearmed != null && rearmed.error == null,
					"could not re-arm the PIN");
				code = phone.try_connection("127.0.0.1", 18422, "159264", false, "ollmchat");
				this.check(command_line, code == 0,
					"stored certificate code " + code.to_string());
				code = phone.try_connection("127.0.0.1", 18422, "000000", false, "ollmchat");
				this.check(command_line,
					code == (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
					"wrong PIN code " + code.to_string());

				var stranger_dir = GLib.Path.build_filename(root, "stranger");
				var stranger = new OLLMrpc.Transport.Cert() {
					dir = stranger_dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-stranger",
					ca_pem_path = GLib.Path.build_filename(
						daemon_dir, "tls", "ollmrpc-ca.pem"),
					ca_key_path = GLib.Path.build_filename(
						daemon_dir, "tls", "ollmrpc-ca-key.pem"),
				};
				stranger.ensure();
				var stranger_pem = "";
				var stranger_key = "";
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(stranger_dir, "client.pem"), out stranger_pem);
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(stranger_dir, "client-key.pem"), out stranger_key);
				GLib.FileUtils.set_contents(
					GLib.Path.build_filename(cert_dir, "client.pem"), stranger_pem);
				GLib.FileUtils.set_contents(
					GLib.Path.build_filename(cert_dir, "client-key.pem"), stranger_key);
				GLib.FileUtils.remove(GLib.Path.build_filename(cert_dir, "client.csr"));
				var third = new GLib.SocketClient().connect(
					new GLib.UnixSocketAddress(sock));
				var third_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(third.get_input_stream()),
					new GLib.DataOutputStream(third.get_output_stream())
				);
				third_bin.write(new OLLMrpc.Request() {
					id = 3,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", "159264")
				});
				var third_armed = third_bin.parse() as OLLMrpc.Response;
				this.check(command_line, third_armed != null && third_armed.error == null,
					"could not arm the PIN for re-registration");
				force_register = false;
				var saw_unregistered = false;
				while (true) {
					code = phone.try_connection(
						"127.0.0.1", 18422, "159264", force_register, "ollmchat");
					if (code == (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED
						&& !force_register) {
						saw_unregistered = true;
						force_register = true;
						continue;
					}
					break;
				}
				this.check(command_line, saw_unregistered,
					"unregistered certificate was accepted");
				this.check(command_line, code == 0,
					"re-register code " + code.to_string());

				phone.remove();
				this.check(command_line,
					!GLib.FileUtils.test(cert_dir, GLib.FileTest.EXISTS),
					"cert dir remains after remove");
				var fourth = new GLib.SocketClient().connect(
					new GLib.UnixSocketAddress(sock));
				var fourth_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(fourth.get_input_stream()),
					new GLib.DataOutputStream(fourth.get_output_stream())
				);
				fourth_bin.write(new OLLMrpc.Request() {
					id = 4,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", "159264")
				});
				var fourth_armed = fourth_bin.parse() as OLLMrpc.Response;
				this.check(command_line, fourth_armed != null && fourth_armed.error == null,
					"could not arm the PIN after remove");
				code = phone.try_connection("127.0.0.1", 18422, "159264", false, "ollmchat");
				this.check(command_line, code == 0,
					"pair after remove code " + code.to_string());
				this.check(command_line,
					GLib.FileUtils.test(
						GLib.Path.build_filename(cert_dir, "ollmrpc-ca.pem"),
						GLib.FileTest.EXISTS),
					"pair after remove wrote no CA");
				code = phone.try_connection("127.0.0.1", 1, "159264", false, "ollmchat");
				this.check(command_line,
					code == (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
					"dead desktop code " + code.to_string());
				daemon.force_exit();
			} catch (GLib.Error e) {
				daemon.force_exit();
				throw e;
			}
		}
	}
}

int main(string[] args)
{
	var root = GLib.DirUtils.mkdtemp("/tmp/ollm-pair-flow-XXXXXX");
	if (root == null) {
		return 1;
	}
	var xdg = GLib.Path.build_filename(root, "xdg");
	GLib.DirUtils.create_with_parents(xdg, 0700);
	GLib.Environment.set_variable("XDG_DATA_HOME", xdg, true);
	GLib.Environment.set_variable("OLLM_PAIR_FLOW_HOME", root, true);
	return new OLLMrpcTests.TestRpcFilesdPairFlow().run(args);
}
