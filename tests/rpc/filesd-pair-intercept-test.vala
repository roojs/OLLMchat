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
 * Pairing must not enroll an attacker who only spoofs the desktop
 * address, and must not treat that attacker's CA as the file server.
 *
 * The phone calls FilesdClient.try_connection on the address it was
 * given. This process is that address: a TLS server whose certificate
 * is not the desktop CA. The desktop PIN is armed the same way the
 * Allow New Device dialog arms it, over the local Unix socket.
 *
 * These checks fail while that call accepts any server certificate.
 * They pass once the PIN is not delivered to this server, the desktop
 * does not approve this process's certificate, and the phone does not
 * keep this process's CA for later RPC.
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

	class TestRpcFilesdPairIntercept : RpcTestAppBase
	{
		private GLib.Mutex state_mutex = GLib.Mutex();
		private GLib.SocketListener listener = new GLib.SocketListener();
		private bool listener_up = false;
		private bool pin_matched = false;
		private bool saw_registration = false;
		private bool saw_pair = false;
		private bool enroll_ok = false;
		private string enroll_note = "";

		public TestRpcFilesdPairIntercept()
		{
			base("com.roojs.ollmchat.test-rpc-filesd-pair-intercept");
		}

		protected override string get_app_name()
		{
			return "test-rpc-filesd-pair-intercept";
		}

		protected override void run_rpc_test(
			GLib.ApplicationCommandLine command_line
		) throws GLib.Error
		{
			var root = "";
			var root_env = GLib.Environment.get_variable("OLLM_PAIR_INTERCEPT_HOME");
			if (root_env != null) {
				root = root_env;
			}
			this.check(command_line, root != "", "OLLM_PAIR_INTERCEPT_HOME is not set");
			var exe = "";
			var exe_env = GLib.Environment.get_variable("OLLMFILESD");
			if (exe_env != null) {
				exe = exe_env;
			}
			this.check(command_line, exe != "", "OLLMFILESD is not set");

			OLLMrpc.Request.rpc_register();
			OLLMrpc.Response.rpc_register();
			OLLMrpc.Error.rpc_register();
			OLLMrpc.Notification.rpc_register();
			OLLMrpc.Daemon.rpc_register();
			OLLMrpc.Bin.register("ClientCert", typeof(ApprovedRow));

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
				"--socket=0.0.0.0:18424"
			});
			GLib.Thread<bool>? rogue_thread = null;
			try {
				var sock = GLib.Path.build_filename(daemon_dir, "ollmfilesd.sock");
				var ready = false;
				var deadline = GLib.get_monotonic_time() + 15 * 1000000;
				while (GLib.get_monotonic_time() < deadline) {
					if (GLib.FileUtils.test(sock, GLib.FileTest.EXISTS)) {
						try {
							var probe = new GLib.SocketClient();
							probe.timeout = 1;
							var probed = probe.connect_to_host("127.0.0.1", 18424);
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

				var pin = "%06d".printf(GLib.Random.int_range(0, 1000000));
				var local = new GLib.SocketClient().connect(new GLib.UnixSocketAddress(sock));
				var local_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(local.get_input_stream()),
					new GLib.DataOutputStream(local.get_output_stream())
				);
				local_bin.write(new OLLMrpc.Request() {
					id = 1,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				});
				var armed = local_bin.parse() as OLLMrpc.Response;
				this.check(command_line, armed != null && armed.error == null,
					"could not arm the desktop PIN");

				var read_path = GLib.Path.build_filename(root, "project-marker.txt");
				GLib.FileUtils.set_contents(read_path, "pairinginterceptread");
				var write_path = GLib.Path.build_filename(root, "attacker-owned.txt");
				GLib.FileUtils.remove(write_path);

				var rogue_dir = GLib.Path.build_filename(root, "rogue");
				var rogue_ca = new OLLMrpc.Transport.Cert() {
					dir = rogue_dir,
					cert_pem = "ca.pem",
					key_pem = "ca-key.pem",
					cn = "rogue-ca",
					certificate_authority = true,
				};
				rogue_ca.ensure();
				var rogue_server = new OLLMrpc.Transport.Cert() {
					dir = rogue_dir,
					cert_pem = "server.pem",
					key_pem = "server-key.pem",
					cn = "rogue",
					server_san = true,
					ca_pem_path = GLib.Path.build_filename(rogue_dir, "ca.pem"),
					ca_key_path = GLib.Path.build_filename(rogue_dir, "ca-key.pem"),
				};
				rogue_server.ensure();
				var rogue_ca_pem = "";
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(rogue_dir, "ca.pem"), out rogue_ca_pem);
				var attacker_dir = GLib.Path.build_filename(root, "attacker");
				var attacker = new OLLMrpc.Transport.Cert() {
					dir = attacker_dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-attacker",
				};
				attacker.ensure();
				var attacker_csr = "";
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(attacker_dir, "client.csr"), out attacker_csr);

				var rogue_addr = new GLib.InetSocketAddress.from_string("127.0.0.1", 18425);
				this.check(command_line, rogue_addr != null, "rogue address");
				GLib.SocketAddress bound;
				this.listener.add_address(rogue_addr,
					GLib.SocketType.STREAM, GLib.SocketProtocol.TCP, null, out bound);
				this.listener_up = true;
				var rogue_cert = rogue_server.certificate;
				rogue_thread = new GLib.Thread<bool>("rogue", () => {
					while (this.listener_up) {
						GLib.SocketConnection conn;
						try {
							conn = this.listener.accept();
						} catch (GLib.Error e) {
							break;
						}
						try {
							conn.socket.blocking = true;
							conn.socket.timeout = 1;
							var tls = GLib.TlsServerConnection.@new(conn, rogue_cert);
							tls.authentication_mode = GLib.TlsAuthenticationMode.NONE;
							tls.accept_certificate.connect((peer_cert, errors) => {
								return true;
							});
							tls.handshake();
							var bin = new OLLMrpc.Bin.Stream(
								new GLib.DataInputStream(tls.get_input_stream()),
								new GLib.DataOutputStream(tls.get_output_stream()),
								true
							);
							var read_more = true;
							while (read_more) {
								OLLMrpc.Bin.Serializable parsed;
								try {
									parsed = bin.parse();
								} catch (GLib.Error e) {
									break;
								}
								var req = parsed as OLLMrpc.Request;
								if (req == null) {
									continue;
								}
								var reply = new OLLMrpc.Response() {
									id = req.id,
									msg = "ok"
								};
								if (req.method == "ClientCert.request_registration" &&
									req.args.size >= 1) {
									var stolen = req.args.get(0).get_string();
									this.state_mutex.lock();
									this.saw_registration = true;
									if (stolen == pin) {
										this.pin_matched = true;
									}
									this.state_mutex.unlock();
									if (stolen == pin && !this.enroll_ok) {
										try {
											var enroll = new OLLMrpc.Transport.TlsClient(
												"127.0.0.1", 18424) {
												accept_any = true
											};
											var enrolled = enroll.call(new OLLMrpc.Request() {
												method = "ClientCert.request_registration",
												args = OLLMrpc.args(
													"sss", stolen, attacker_csr, "attacker")
											});
											if (enrolled.error != null) {
												this.state_mutex.lock();
												this.enroll_note = enrolled.error.message;
												this.state_mutex.unlock();
											}
											if (enrolled.error == null) {
												var issued = (string[]) enrolled.retval;
												if (issued.length >= 2) {
													GLib.FileUtils.set_contents(
														GLib.Path.build_filename(
															attacker_dir, "client.pem"),
														issued[0]);
													GLib.FileUtils.set_contents(
														GLib.Path.build_filename(
															attacker_dir, "ollmrpc-ca.pem"),
														issued[1]);
													this.state_mutex.lock();
													this.enroll_ok = true;
													this.state_mutex.unlock();
												}
											}
										} catch (GLib.Error e) {
											this.state_mutex.lock();
											this.enroll_note = e.message;
											this.state_mutex.unlock();
										}
									}
									string[] packed = {};
									packed += "x";
									packed += rogue_ca_pem;
									packed += "127.0.0.1:18425";
									reply.retval = OLLMrpc.val("as", packed);
									/* The phone keeps this socket open and
									 * opens another for hello. Accept that
									 * connection instead of reading further. */
									read_more = false;
								}
								if (req.method == "ClientCert.pair" && req.args.size >= 1) {
									this.state_mutex.lock();
									this.saw_pair = true;
									if (req.args.get(0).get_string() == pin) {
										this.pin_matched = true;
									}
									this.state_mutex.unlock();
								}
								bin.write(reply);
								bin.out_stream.flush();
							}
						} catch (GLib.Error e) {
							this.state_mutex.lock();
							if (this.enroll_note == "") {
								this.enroll_note = e.message;
							}
							this.state_mutex.unlock();
						}
					}
					return true;
				});

				var bare = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18424) {
					accept_any = true
				};
				var bare_open = false;
				try {
					var bare_reply = bare.call(new OLLMrpc.Request() {
						method = "File.read",
						args = OLLMrpc.args("s", read_path)
					});
					if (bare_reply.error == null) {
						bare_open = true;
					}
					if (bare_reply.error != null) {
						switch (bare_reply.error.code) {
							case (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED:
							case (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST:
								break;
							default:
								bare_open = true;
								break;
						}
					}
				} catch (GLib.Error e) {
				}

				var phone = new OLLMchat.Settings.FilesdClient();
				phone.server_id = "11111111-1111-4111-8111-111111111111";
				var phone_dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat", phone.server_id);
				var code = phone.try_connection(
					"127.0.0.1", 18425, pin, true, "ollmchat");
				var ca_path = GLib.Path.build_filename(phone_dir, "ollmrpc-ca.pem");
				if (GLib.FileUtils.test(ca_path, GLib.FileTest.EXISTS)) {
					code = phone.try_connection(
						"127.0.0.1", 18425, pin, false, "ollmchat");
				}

				var read_open = false;
				var write_open = false;
				var command_open = false;
				if (this.enroll_ok) {
					var issued = new OLLMrpc.Transport.Cert() {
						dir = attacker_dir,
						cert_pem = "client.pem",
						key_pem = "client-key.pem",
					};
					issued.ensure();
					var reader = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18424) {
						tls_certificate = issued.certificate,
						tls_database = issued.trust
					};
					try {
						var read_reply = reader.call(new OLLMrpc.Request() {
							method = "File.read",
							args = OLLMrpc.args("s", read_path)
						});
						if (read_reply.error == null && read_reply.msg.length > 0) {
							read_open = true;
						}
						if (read_reply.error != null) {
							switch (read_reply.error.code) {
								case (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED:
								case (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST:
									break;
								default:
									read_open = true;
									break;
							}
						}
					} catch (GLib.Error e) {
						if (!(e.message.contains("TLS") ||
							e.message.contains("certificate") ||
							e.message.contains("handshake"))) {
							read_open = true;
						}
					}
					var writer = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18424) {
						tls_certificate = issued.certificate,
						tls_database = issued.trust
					};
					try {
						var write_reply = writer.call(new OLLMrpc.Request() {
							method = "File.rpc_write",
							args = OLLMrpc.args(
								"ssssu", write_path, "attacker-owned", "f", "", (uint) 0644)
						});
						if (write_reply.error == null) {
							write_open = true;
						}
						if (write_reply.error != null) {
							switch (write_reply.error.code) {
								case (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED:
								case (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST:
									break;
								default:
									write_open = true;
									break;
							}
						}
					} catch (GLib.Error e) {
					}
					var commander = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18424) {
						tls_certificate = issued.certificate,
						tls_database = issued.trust
					};
					try {
						string[] no_writes = {};
						var command_reply = commander.call(new OLLMrpc.Request() {
							method = "Sandbox-Bubble.rpc_create",
							args = OLLMrpc.args(
								"sssbSbx", "", "true", "", false, no_writes, false, (int64) 0)
						});
						if (command_reply.error == null) {
							command_open = true;
						}
						if (command_reply.error != null) {
							switch (command_reply.error.code) {
								case (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED:
								case (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST:
									break;
								default:
									command_open = true;
									break;
							}
						}
					} catch (GLib.Error e) {
					}
				}
				if (GLib.FileUtils.test(write_path, GLib.FileTest.EXISTS)) {
					write_open = true;
				}

				var stored_ca = "";
				try {
					GLib.FileUtils.get_contents(ca_path, out stored_ca);
				} catch (GLib.Error e) {
				}
				var follow_open = false;
				if (stored_ca != "") {
					var stored = new OLLMrpc.Transport.Cert() {
						dir = phone_dir,
						cert_pem = "client.pem",
						key_pem = "client-key.pem",
					};
					stored.ensure();
					var follow = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18425) {
						tls_certificate = stored.certificate,
						tls_database = stored.trust
					};
					try {
						var follow_reply = follow.call(new OLLMrpc.Request() {
							method = "RPC-Daemon.hello",
							args = OLLMrpc.args("is", 1, "ollmchat")
						});
						follow_open = follow_reply.error == null;
					} catch (GLib.Error e) {
					}
				}

				var approved_attacker = false;
				var approved_local = new GLib.SocketClient().connect(
					new GLib.UnixSocketAddress(sock));
				var approved_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(approved_local.get_input_stream()),
					new GLib.DataOutputStream(approved_local.get_output_stream())
				);
				approved_bin.write(new OLLMrpc.Request() {
					id = 2,
					method = "ClientCert.approved_certs"
				});
				var approved = approved_bin.parse() as OLLMrpc.Response;
				this.check(command_line, approved != null && approved.error == null,
					"approved list failed");
				var rows = (Gee.ArrayList<ApprovedRow>) approved.retval.get_object();
				foreach (var row in rows) {
					if (row.requester == "attacker" && row.status == 1) {
						approved_attacker = true;
					}
				}

				this.state_mutex.lock();
				var leaked_pin = this.pin_matched;
				var saw_reg = this.saw_registration;
				var saw_pair_pin = this.saw_pair;
				var enrolled = this.enroll_ok;
				var note = this.enroll_note;
				this.state_mutex.unlock();

				var report = "";
				if (bare_open) {
					report += "unauthenticated File.read was accepted; ";
				}
				if (leaked_pin) {
					report += "untrusted server received the pairing PIN; ";
				}
				if (enrolled || approved_attacker) {
					report += "attacker certificate was approved; ";
				}
				if (read_open) {
					report += "approved attacker read a file; ";
				}
				if (write_open) {
					report += "approved attacker wrote a file; ";
				}
				if (command_open) {
					report += "approved attacker passed the command gate; ";
				}
				if (stored_ca == rogue_ca_pem) {
					report += "phone stored the attacker CA; ";
				}
				if (phone.url.contains(":18425")) {
					report += "phone url points at the attacker; ";
				}
				if (follow_open) {
					report += "stored CA trusted the attacker for later RPC; ";
				}
				if (saw_pair_pin) {
					report += "ClientCert.pair reached the attacker; ";
				}
				if (code != 0 && report != "") {
					report += "try_connection code " + code.to_string() + "; ";
				}
				if (note != "" && report != "") {
					report += "enroll note " + note + "; ";
				}
				command_line.print("registration_seen=%s %s\n",
					saw_reg.to_string(), report == "" ? "pairing channel held" : report);
				daemon.force_exit();
				if (report != "") {
					command_line.printerr("%s\n", report);
					GLib.Process.exit(1);
				}
				GLib.Process.exit(0);
			} catch (GLib.Error e) {
				daemon.force_exit();
				throw e;
			}
		}
	}
}

int main(string[] args)
{
	var root = GLib.DirUtils.mkdtemp("/tmp/ollm-pair-intercept-XXXXXX");
	if (root == null) {
		return 1;
	}
	var xdg = GLib.Path.build_filename(root, "xdg");
	GLib.DirUtils.create_with_parents(xdg, 0700);
	var cache = GLib.Path.build_filename(root, "cache");
	GLib.DirUtils.create_with_parents(cache, 0700);
	GLib.Environment.set_variable("XDG_DATA_HOME", xdg, true);
	GLib.Environment.set_variable("XDG_CACHE_HOME", cache, true);
	GLib.Environment.set_variable("OLLM_PAIR_INTERCEPT_HOME", root, true);
	return new OLLMrpcTests.TestRpcFilesdPairIntercept().run(args);
}
