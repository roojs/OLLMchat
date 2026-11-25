/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

/*
 * Pairing PIN attempt limit for ClientCert.request_registration.
 *
 * The desktop arms a PIN with ClientCert.pair on the Unix socket.
 * A TLS client with no certificate then calls request_registration.
 * Eight failed PIN checks in that window must clear the PIN before
 * any certificate is signed. The next call, on that same TLS session
 * or on a new one, must not return a certificate and must not insert
 * a client_cert row with status 1. Failures are counted for the
 * window, including when each guess uses a new TLS session. A new
 * window armed from the Unix socket may still accept the PIN on
 * the first try. ClientCert.pair on TLS without a certificate must
 * not reveal or consume the PIN.
 */

namespace OLLMrpcTests
{
	class ApprovedRow : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public int64 id { get; set; default = 0; }
		public string fingerprint { get; set; default = ""; }
		public int status { get; set; default = 0; }
		public string ip { get; set; default = ""; }
		public int64 created { get; set; default = 0; }
		public string requester { get; set; default = ""; }
	}

	class ReadFile : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string path { get; set; default = ""; }
	}

	class TestRpcFilesdPinLockout : RpcTestAppBase
	{
		public TestRpcFilesdPinLockout()
		{
			base("com.roojs.ollmchat.test-rpc-filesd-pin-lockout");
		}

		protected override string get_app_name()
		{
			return "test-rpc-filesd-pin-lockout";
		}

		protected override void run_rpc_test(
			GLib.ApplicationCommandLine command_line
		) throws GLib.Error
		{
			var exe = "";
			var exe_env = GLib.Environment.get_variable("OLLMFILESD");
			if (exe_env != null) {
				exe = exe_env;
			}
			this.check(command_line, exe != "", "OLLMFILESD is not set");
			var root = "";
			var root_env = GLib.Environment.get_variable("OLLM_PIN_LOCKOUT_HOME");
			if (root_env != null) {
				root = root_env;
			}
			this.check(command_line, root != "", "OLLM_PIN_LOCKOUT_HOME is not set");
			var daemon_dir = GLib.Path.build_filename(root, "daemon");
			GLib.DirUtils.create_with_parents(daemon_dir, 0700);
			var marker_path = GLib.Path.build_filename(root, "marker.txt");
			var written_path = GLib.Path.build_filename(root, "written.txt");
			GLib.FileUtils.set_contents(marker_path, "pin-lockout-marker");
			var err_path = GLib.Path.build_filename(root, "daemon.err");
			var launcher = new GLib.SubprocessLauncher(GLib.SubprocessFlags.NONE);
			launcher.setenv("OLLMFILES_IS_TEST", "1", true);
			launcher.setenv("OLLMFILESD_DAEMON", "1", true);
			launcher.set_stderr_file_path(err_path);
			var daemon = launcher.spawnv({
				exe,
				"--data-dir=" + daemon_dir,
				"--socket=0.0.0.0:18433"
			});
			try {
				OLLMrpc.Request.rpc_register();
				OLLMrpc.Response.rpc_register();
				OLLMrpc.Error.rpc_register();
				OLLMrpc.Notification.rpc_register();
				OLLMrpc.Daemon.rpc_register();
				OLLMrpc.Bin.register("ClientCert", typeof(ApprovedRow));
				OLLMrpc.Bin.register("File", typeof(ReadFile));

				var sock = GLib.Path.build_filename(daemon_dir, "ollmfilesd.sock");
				var ready = false;
				var deadline = GLib.get_monotonic_time() + 10 * 1000000;
				while (GLib.get_monotonic_time() < deadline) {
					if (GLib.FileUtils.test(sock, GLib.FileTest.EXISTS)) {
						try {
							var probe = new GLib.SocketClient();
							probe.timeout = 1;
							var probed = probe.connect_to_host("127.0.0.1", 18433);
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
				this.check(command_line, ready, "daemon did not listen: " + err_text);
				var tcp = "";
				GLib.FileUtils.get_contents("/proc/net/tcp", out tcp);
				var port_hex = "%04X".printf(18433);
				this.check(command_line, tcp.contains("00000000:" + port_hex),
					"TLS listener is not bound to 0.0.0.0:" + port_hex);

				var cert_dir = GLib.Path.build_filename(root, "device");
				var device = new OLLMrpc.Transport.Cert() {
					dir = cert_dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
				};
				device.ensure();
				var csr = "";
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(cert_dir, "client.csr"), out csr);
				var pin = "000000";
				string[] wrong_pins = {
					"111111", "222222", "333333", "444444",
					"555555", "666666", "777777", "888888"
				};
				var next_id = 1;

				var arm = new GLib.SocketClient().connect(new GLib.UnixSocketAddress(sock));
				var arm_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(arm.get_input_stream()),
					new GLib.DataOutputStream(arm.get_output_stream())
				);
				var arm_id = next_id;
				next_id += 1;
				arm_bin.write(new OLLMrpc.Request() {
					id = arm_id,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				});
				var armed = arm_bin.parse() as OLLMrpc.Response;
				this.check(command_line, armed != null && armed.error == null,
					"could not arm the PIN");
				arm.close();

				var pair_sock = new GLib.SocketClient().connect_to_host("127.0.0.1", 18433);
				var pair_tls = GLib.TlsClientConnection.@new(pair_sock, null);
				pair_tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
				pair_tls.handshake();
				var pair_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(pair_tls.get_input_stream()),
					new GLib.DataOutputStream(pair_tls.get_output_stream())
				);
				var pair_id = next_id;
				next_id += 1;
				pair_bin.write(new OLLMrpc.Request() {
					id = pair_id,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				});
				var pair_parsed = pair_bin.parse();
				while (pair_parsed is OLLMrpc.Notification) {
					pair_parsed = pair_bin.parse();
				}
				var pair_reply = pair_parsed as OLLMrpc.Response;
				this.check(command_line, pair_reply != null && pair_reply.error != null,
					"TLS pair without a certificate was accepted");
				this.check(command_line,
					pair_reply.error.message == "client certificate required",
					"TLS pair error " + pair_reply.error.message);
				pair_tls.close();

				var first_sock = new GLib.SocketClient().connect_to_host("127.0.0.1", 18433);
				var first_tls = GLib.TlsClientConnection.@new(first_sock, null);
				first_tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
				first_tls.handshake();
				var first_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(first_tls.get_input_stream()),
					new GLib.DataOutputStream(first_tls.get_output_stream())
				);
				var first_id = next_id;
				next_id += 1;
				first_bin.write(new OLLMrpc.Request() {
					id = first_id,
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("sss", pin, csr, "lockout-probe")
				});
				var first_parsed = first_bin.parse();
				while (first_parsed is OLLMrpc.Notification) {
					first_parsed = first_bin.parse();
				}
				var first = first_parsed as OLLMrpc.Response;
				this.check(command_line, first != null && first.error == null,
					"first PIN was rejected: " +
					(first != null && first.error != null ? first.error.message : ""));
				var first_packed = (string[]) first.retval;
				this.check(command_line, first_packed.length >= 2,
					"first PIN reply had no certificate");
				first_tls.close();
				GLib.FileUtils.set_contents(
					GLib.Path.build_filename(cert_dir, "client.pem"), first_packed[0]);
				GLib.FileUtils.set_contents(
					GLib.Path.build_filename(cert_dir, "ollmrpc-ca.pem"), first_packed[1]);
				device.ensure();

				var authed_sock = new GLib.SocketClient().connect_to_host("127.0.0.1", 18433);
				var authed_tls = GLib.TlsClientConnection.@new(authed_sock, null);
				authed_tls.certificate = device.certificate;
				authed_tls.database = device.trust;
				authed_tls.accept_certificate.connect((peer_cert, errors) => {
					return peer_cert != null &&
						(errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
				});
				authed_tls.handshake();
				var authed_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(authed_tls.get_input_stream()),
					new GLib.DataOutputStream(authed_tls.get_output_stream())
				);
				authed_bin.mode = OLLMrpc.Bin.Mode.IGNORE_UNKNOWN;
				var hello_id = next_id;
				next_id += 1;
				authed_bin.write(new OLLMrpc.Request() {
					id = hello_id,
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				});
				var hello_parsed = authed_bin.parse();
				while (hello_parsed is OLLMrpc.Notification) {
					hello_parsed = authed_bin.parse();
				}
				var hello = hello_parsed as OLLMrpc.Response;
				this.check(command_line, hello != null && hello.error == null,
					"hello with the issued certificate failed: " +
					(hello != null && hello.error != null ? hello.error.message : ""));
				var wrap_id = next_id;
				next_id += 1;
				authed_bin.write(new OLLMrpc.Request() {
					id = wrap_id,
					method = "Sandbox-Bubble.can_wrap"
				});
				var wrap_parsed = authed_bin.parse();
				while (wrap_parsed is OLLMrpc.Notification) {
					wrap_parsed = authed_bin.parse();
				}
				var wrap = wrap_parsed as OLLMrpc.Response;
				this.check(command_line, wrap != null && wrap.error == null,
					"Sandbox-Bubble.can_wrap failed: " +
					(wrap != null && wrap.error != null ? wrap.error.message : ""));
				var read_id = next_id;
				next_id += 1;
				authed_bin.write(new OLLMrpc.Request() {
					id = read_id,
					method = "File.read",
					args = OLLMrpc.args("s", marker_path)
				});
				var read_parsed = authed_bin.parse();
				while (read_parsed is OLLMrpc.Notification) {
					read_parsed = authed_bin.parse();
				}
				var read_reply = read_parsed as OLLMrpc.Response;
				this.check(command_line, read_reply != null && read_reply.error == null,
					"File.read failed: " +
					(read_reply != null && read_reply.error != null ? read_reply.error.message : ""));
				var read_body = read_reply.msg;
				if (read_reply.msg_encode == 1) {
					read_body = (string) GLib.Base64.decode(read_reply.msg);
				}
				this.check(command_line, read_body.contains("pin-lockout-mark"),
					"File.read did not return the marker: " + read_body);
				var write_id = next_id;
				next_id += 1;
				authed_bin.write(new OLLMrpc.Request() {
					id = write_id,
					method = "File.rpc_write",
					args = OLLMrpc.args("ssssu",
						written_path, "pin-lockout-written", "f", "", (uint) 0644)
				});
				var write_parsed = authed_bin.parse();
				while (write_parsed is OLLMrpc.Notification) {
					write_parsed = authed_bin.parse();
				}
				var write_reply = write_parsed as OLLMrpc.Response;
				this.check(command_line,
					write_reply != null && write_reply.error == null && write_reply.msg == "ok",
					"File.rpc_write failed: " +
					(write_reply != null && write_reply.error != null ? write_reply.error.message : ""));
				var written_body = "";
				GLib.FileUtils.get_contents(written_path, out written_body);
				this.check(command_line, written_body == "pin-lockout-written",
					"File.rpc_write left " + written_body);
				authed_tls.close();

				var list = new GLib.SocketClient().connect(new GLib.UnixSocketAddress(sock));
				var list_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(list.get_input_stream()),
					new GLib.DataOutputStream(list.get_output_stream())
				);
				var list_id = next_id;
				next_id += 1;
				list_bin.write(new OLLMrpc.Request() {
					id = list_id,
					method = "ClientCert.approved_certs"
				});
				var listed = list_bin.parse() as OLLMrpc.Response;
				this.check(command_line, listed != null && listed.error == null,
					"approved_certs failed");
				var rows = (Gee.ArrayList<ApprovedRow>) listed.retval.get_object();
				foreach (var row in rows) {
					var remove_id = next_id;
					next_id += 1;
					list_bin.write(new OLLMrpc.Request() {
						id = remove_id,
						method = "ClientCert.client_cert",
						args = OLLMrpc.args("sx", "remove", row.id)
					});
					var removed = list_bin.parse() as OLLMrpc.Response;
					this.check(command_line, removed != null && removed.error == null,
						"could not remove the issued certificate");
				}
				var clear_id = next_id;
				next_id += 1;
				list_bin.write(new OLLMrpc.Request() {
					id = clear_id,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", "")
				});
				var cleared = list_bin.parse() as OLLMrpc.Response;
				this.check(command_line, cleared != null && cleared.error == null,
					"could not clear the PIN");
				var rearm_id = next_id;
				next_id += 1;
				list_bin.write(new OLLMrpc.Request() {
					id = rearm_id,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				});
				var rearmed = list_bin.parse() as OLLMrpc.Response;
				this.check(command_line, rearmed != null && rearmed.error == null,
					"could not arm the PIN for the attempt limit");
				list.close();

				var session_sock = new GLib.SocketClient().connect_to_host("127.0.0.1", 18433);
				var session_tls = GLib.TlsClientConnection.@new(session_sock, null);
				session_tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
				session_tls.handshake();
				var session_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(session_tls.get_input_stream()),
					new GLib.DataOutputStream(session_tls.get_output_stream())
				);
				OLLMrpc.Response? ninth = null;
				for (var i = 0; i < wrong_pins.length; i++) {
					var guess_id = next_id;
					next_id += 1;
					session_bin.write(new OLLMrpc.Request() {
						id = guess_id,
						method = "ClientCert.request_registration",
						args = OLLMrpc.args("sss", wrong_pins[i], csr, "lockout-probe")
					});
					var guess_parsed = session_bin.parse();
					while (guess_parsed is OLLMrpc.Notification) {
						guess_parsed = session_bin.parse();
					}
					var rejected = guess_parsed as OLLMrpc.Response;
					if (rejected == null || rejected.error == null) {
						this.fail(command_line, "a wrong PIN issued a certificate");
					}
				}
				var ninth_id = next_id;
				next_id += 1;
				session_bin.write(new OLLMrpc.Request() {
					id = ninth_id,
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("sss", pin, csr, "lockout-probe")
				});
				var ninth_parsed = session_bin.parse();
				while (ninth_parsed is OLLMrpc.Notification) {
					ninth_parsed = session_bin.parse();
				}
				ninth = ninth_parsed as OLLMrpc.Response;
				this.check(command_line, ninth != null, "same session sent no reply");
				var evidence = "";
				if (ninth != null && ninth.error == null) {
					var issued = (string[]) ninth.retval;
					GLib.FileUtils.set_contents(
						GLib.Path.build_filename(cert_dir, "client.pem"), issued[0]);
					GLib.FileUtils.set_contents(
						GLib.Path.build_filename(cert_dir, "ollmrpc-ca.pem"), issued[1]);
					device.ensure();
					var stolen_sock = new GLib.SocketClient().connect_to_host("127.0.0.1", 18433);
					var stolen_tls = GLib.TlsClientConnection.@new(stolen_sock, null);
					stolen_tls.certificate = device.certificate;
					stolen_tls.database = device.trust;
					stolen_tls.accept_certificate.connect((peer_cert, errors) => {
						return peer_cert != null &&
							(errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
					});
					stolen_tls.handshake();
					var stolen_bin = new OLLMrpc.Bin.Stream(
						new GLib.DataInputStream(stolen_tls.get_input_stream()),
						new GLib.DataOutputStream(stolen_tls.get_output_stream())
					);
					stolen_bin.mode = OLLMrpc.Bin.Mode.IGNORE_UNKNOWN;
					var stolen_read_id = next_id;
					next_id += 1;
					stolen_bin.write(new OLLMrpc.Request() {
						id = stolen_read_id,
						method = "File.read",
						args = OLLMrpc.args("s", marker_path)
					});
					var stolen_parsed = stolen_bin.parse();
					while (stolen_parsed is OLLMrpc.Notification) {
						stolen_parsed = stolen_bin.parse();
					}
					var stolen_reply = stolen_parsed as OLLMrpc.Response;
					var stolen_body = "";
					if (stolen_reply != null && stolen_reply.error == null) {
						stolen_body = stolen_reply.msg;
						if (stolen_reply.msg_encode == 1) {
							stolen_body = (string) GLib.Base64.decode(stolen_reply.msg);
						}
					}
					var stolen_wrap_id = next_id;
					next_id += 1;
					stolen_bin.write(new OLLMrpc.Request() {
						id = stolen_wrap_id,
						method = "Sandbox-Bubble.can_wrap"
					});
					var stolen_wrap_parsed = stolen_bin.parse();
					while (stolen_wrap_parsed is OLLMrpc.Notification) {
						stolen_wrap_parsed = stolen_bin.parse();
					}
					var stolen_wrap = stolen_wrap_parsed as OLLMrpc.Response;
					var stolen_write_id = next_id;
					next_id += 1;
					stolen_bin.write(new OLLMrpc.Request() {
						id = stolen_write_id,
						method = "File.rpc_write",
						args = OLLMrpc.args("ssssu",
							written_path, "pin-lockout-rewritten", "f", "", (uint) 0644)
					});
					var stolen_write_parsed = stolen_bin.parse();
					while (stolen_write_parsed is OLLMrpc.Notification) {
						stolen_write_parsed = stolen_bin.parse();
					}
					var stolen_write = stolen_write_parsed as OLLMrpc.Response;
					var rewritten = "";
					try {
						GLib.FileUtils.get_contents(written_path, out rewritten);
					} catch (GLib.Error e) {
						rewritten = e.message;
					}
					var wrap_msg = "";
					if (stolen_wrap != null) {
						wrap_msg = stolen_wrap.msg;
					}
					var write_msg = "";
					if (stolen_write != null) {
						write_msg = stolen_write.msg;
					}
					evidence += "same TLS session signed a certificate after 8 rejected guesses; " +
						"File.read=" + stolen_body + "; " +
						"can_wrap=" + wrap_msg + "; " +
						"rpc_write=" + write_msg + "; disk=" + rewritten + "; ";
					stolen_tls.close();
				}
				session_tls.close();

				OLLMrpc.Response? fresh_reply = null;
				try {
					var fresh_sock = new GLib.SocketClient().connect_to_host("127.0.0.1", 18433);
					var fresh_tls = GLib.TlsClientConnection.@new(fresh_sock, null);
					fresh_tls.accept_certificate.connect((peer_cert, errors) => {
						return true;
					});
					fresh_tls.handshake();
					var fresh_bin = new OLLMrpc.Bin.Stream(
						new GLib.DataInputStream(fresh_tls.get_input_stream()),
						new GLib.DataOutputStream(fresh_tls.get_output_stream())
					);
					var fresh_id = next_id;
					next_id += 1;
					fresh_bin.write(new OLLMrpc.Request() {
						id = fresh_id,
						method = "ClientCert.request_registration",
						args = OLLMrpc.args("sss", pin, csr, "lockout-probe")
					});
					var fresh_parsed = fresh_bin.parse();
					while (fresh_parsed is OLLMrpc.Notification) {
						fresh_parsed = fresh_bin.parse();
					}
					fresh_reply = fresh_parsed as OLLMrpc.Response;
					fresh_tls.close();
				} catch (GLib.Error e) {
					fresh_reply = new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST(e.message)
					};
				}
				if (fresh_reply != null && fresh_reply.error == null) {
					evidence += "a new TLS session still received a certificate; ";
				}

				var after = new GLib.SocketClient().connect(new GLib.UnixSocketAddress(sock));
				var after_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(after.get_input_stream()),
					new GLib.DataOutputStream(after.get_output_stream())
				);
				var after_id = next_id;
				next_id += 1;
				after_bin.write(new OLLMrpc.Request() {
					id = after_id,
					method = "ClientCert.approved_certs"
				});
				var after_listed = after_bin.parse() as OLLMrpc.Response;
				this.check(command_line, after_listed != null && after_listed.error == null,
					"approved_certs after guesses failed");
				var after_rows = (Gee.ArrayList<ApprovedRow>) after_listed.retval.get_object();
				if (after_rows.size > 0) {
					evidence += "status 1 rows=" + after_rows.size.to_string() + "; ";
				}
				if (evidence != "") {
					this.fail(command_line,
						"after 8 rejected PIN guesses the armed PIN still registered a device: " +
						evidence);
				}
				this.check(command_line, ninth.error != null,
					"same session accepted the PIN after 8 failures");
				this.check(command_line, fresh_reply != null && fresh_reply.error != null,
					"new session accepted the PIN after 8 failures");
				this.check(command_line, after_rows.size == 0,
					"a status 1 row was inserted");

				var split_clear_id = next_id;
				next_id += 1;
				after_bin.write(new OLLMrpc.Request() {
					id = split_clear_id,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", "")
				});
				var split_cleared = after_bin.parse() as OLLMrpc.Response;
				this.check(command_line, split_cleared != null && split_cleared.error == null,
					"could not close the window before the split guesses");
				var split_rearm_id = next_id;
				next_id += 1;
				after_bin.write(new OLLMrpc.Request() {
					id = split_rearm_id,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				});
				var split_rearmed = after_bin.parse() as OLLMrpc.Response;
				this.check(command_line, split_rearmed != null && split_rearmed.error == null,
					"could not arm the PIN for separate connections");
				for (var i = 0; i < wrong_pins.length; i++) {
					var one_sock = new GLib.SocketClient().connect_to_host("127.0.0.1", 18433);
					var one_tls = GLib.TlsClientConnection.@new(one_sock, null);
					one_tls.accept_certificate.connect((peer_cert, errors) => {
						return true;
					});
					one_tls.handshake();
					var one_bin = new OLLMrpc.Bin.Stream(
						new GLib.DataInputStream(one_tls.get_input_stream()),
						new GLib.DataOutputStream(one_tls.get_output_stream())
					);
					var one_id = next_id;
					next_id += 1;
					one_bin.write(new OLLMrpc.Request() {
						id = one_id,
						method = "ClientCert.request_registration",
						args = OLLMrpc.args("sss", wrong_pins[i], csr, "lockout-probe")
					});
					var one_parsed = one_bin.parse();
					while (one_parsed is OLLMrpc.Notification) {
						one_parsed = one_bin.parse();
					}
					var one_reply = one_parsed as OLLMrpc.Response;
					one_tls.close();
					if (one_reply == null || one_reply.error == null) {
						this.fail(command_line, "a wrong PIN on its own connection issued a certificate");
					}
				}
				var last_sock = new GLib.SocketClient().connect_to_host("127.0.0.1", 18433);
				var last_tls = GLib.TlsClientConnection.@new(last_sock, null);
				last_tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
				last_tls.handshake();
				var last_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(last_tls.get_input_stream()),
					new GLib.DataOutputStream(last_tls.get_output_stream())
				);
				var last_id = next_id;
				next_id += 1;
				last_bin.write(new OLLMrpc.Request() {
					id = last_id,
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("sss", pin, csr, "lockout-probe")
				});
				var last_parsed = last_bin.parse();
				while (last_parsed is OLLMrpc.Notification) {
					last_parsed = last_bin.parse();
				}
				var last_reply = last_parsed as OLLMrpc.Response;
				last_tls.close();
				this.check(command_line, last_reply != null && last_reply.error != null,
					"guesses on separate connections did not close the window");

				var again_id = next_id;
				next_id += 1;
				after_bin.write(new OLLMrpc.Request() {
					id = again_id,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				});
				var again_armed = after_bin.parse() as OLLMrpc.Response;
				this.check(command_line, again_armed != null && again_armed.error == null,
					"a new window could not be armed");
				after.close();
				var again_sock = new GLib.SocketClient().connect_to_host("127.0.0.1", 18433);
				var again_tls = GLib.TlsClientConnection.@new(again_sock, null);
				again_tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
				again_tls.handshake();
				var again_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(again_tls.get_input_stream()),
					new GLib.DataOutputStream(again_tls.get_output_stream())
				);
				var again_req = next_id;
				next_id += 1;
				again_bin.write(new OLLMrpc.Request() {
					id = again_req,
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("sss", pin, csr, "lockout-probe")
				});
				var again_parsed = again_bin.parse();
				while (again_parsed is OLLMrpc.Notification) {
					again_parsed = again_bin.parse();
				}
				var again = again_parsed as OLLMrpc.Response;
				again_tls.close();
				this.check(command_line, again != null && again.error == null && again.msg == "ok",
					"a fresh window rejected the first PIN");
				daemon.force_exit();
			} catch (GLib.Error e) {
				daemon.force_exit();
				GLib.Process.exit(1);
			}
		}
	}
}

int main(string[] args)
{
	var root = GLib.DirUtils.mkdtemp("/tmp/ollm-pin-lockout-XXXXXX");
	if (root == null) {
		return 1;
	}
	var xdg = GLib.Path.build_filename(root, "xdg");
	GLib.DirUtils.create_with_parents(xdg, 0700);
	GLib.Environment.set_variable("XDG_DATA_HOME", xdg, true);
	GLib.Environment.set_variable("OLLM_PIN_LOCKOUT_HOME", root, true);
	return new OLLMrpcTests.TestRpcFilesdPinLockout().run(args);
}
