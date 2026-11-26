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
 * Closed pairing window. An empty PIN must not mint a certificate,
 * and deleting the client_cert row must stop that device from
 * obtaining another one. File.read and Sandbox-Bubble.rpc_create /
 * rpc_run must stay refused. Fails while the bypass is present.
 *
 * Same allow_request gate, not invoked here: File.exists, File.fetch,
 * File.rpc_write, File.rpc_delete, File.register, File.changed.check,
 * File.apply_permissions, File.ast_lookup, File.ast_summarize,
 * Sandbox-Bubble.kill, Sandbox-Bubble.tail, Sandbox-Bubble.wait,
 * Sandbox-Bubble.send, Sandbox-Bubble.can_wrap.
 */

namespace OLLMrpcTests
{
	class RevokedFile : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public int64 id { get; set; default = 0; }
		public string path { get; set; default = ""; }
		public int64 parent_id { get; set; default = 0; }
		public int file_count { get; set; default = 0; }
		public int folder_count { get; set; default = 0; }
		public int document_count { get; set; default = 0; }
		public int code_count { get; set; default = 0; }
		public GLib.Object points_to { get; set; }
		public int64 points_to_id { get; set; default = 0; }
		public string target_path { get; set; default = ""; }
		public string base_type { get; set; default = ""; }
		public bool is_active { get; set; default = false; }
		public string language { get; set; default = ""; }
		public bool is_need_approval { get; set; default = false; }
		public string last_change_type { get; set; default = ""; }
		public bool is_unsaved { get; set; default = false; }
		public bool is_project { get; set; default = false; }
		public int64 last_viewed { get; set; default = 0; }
		public int64 last_modified { get; set; default = 0; }
		public int64 size { get; set; default = 0; }
		public bool is_ignored { get; set; default = false; }
		public bool is_text { get; set; default = false; }
		public string mime_type { get; set; default = ""; }
		public int is_repo { get; set; default = -1; }
		public int64 last_vector_scan { get; set; default = 0; }
		public int64 delete_id { get; set; default = 0; }
	}

	class RevokedClient : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public int64 id { get; set; default = 0; }
		public string fingerprint { get; set; default = ""; }
		public int status { get; set; default = 0; }
		public string ip { get; set; default = ""; }
		public int64 created { get; set; default = 0; }
		public string requester { get; set; default = ""; }
	}

	class TestRpcFilesdRevocation : RpcTestAppBase
	{
		public TestRpcFilesdRevocation()
		{
			base("com.roojs.ollmchat.test-rpc-filesd-revocation");
		}

		protected override string get_app_name()
		{
			return "test-rpc-filesd-revocation";
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
			var root_env = GLib.Environment.get_variable("OLLM_REVOCATION_HOME");
			if (root_env != null) {
				root = root_env;
			}
			this.check(command_line, root != "", "OLLM_REVOCATION_HOME is not set");
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
				"--socket=0.0.0.0:18423"
			});
			try {
				OLLMrpc.Request.rpc_register();
				OLLMrpc.Response.rpc_register();
				OLLMrpc.Error.rpc_register();
				OLLMrpc.Notification.rpc_register();
				OLLMrpc.Daemon.rpc_register();
				OLLMrpc.Bin.register("ClientCert", typeof(RevokedClient));
				OLLMrpc.Bin.register("File", typeof(RevokedFile));

				var sock = GLib.Path.build_filename(daemon_dir, "ollmfilesd.sock");
				var ready = false;
				var deadline = GLib.get_monotonic_time() + 10 * 1000000;
				while (GLib.get_monotonic_time() < deadline) {
					if (GLib.FileUtils.test(sock, GLib.FileTest.EXISTS)) {
						try {
							var probe = new GLib.SocketClient();
							probe.timeout = 1;
							var probed = probe.connect_to_host("127.0.0.1", 18423);
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

				var sentinel = GLib.Path.build_filename(root, "sentinel.txt");
				GLib.FileUtils.set_contents(sentinel, "revocation-sentinel\n");
				/* bwrap mounts a tmpfs on /tmp after the write binds, so a
				 * marker under /tmp would not be visible on the host. */
				var marker_made = GLib.DirUtils.mkdtemp("/var/tmp/ollm-revoke-marker-XXXXXX");
				this.check(command_line, marker_made != null, "could not create the marker directory");
				var marker_dir = marker_made != null ? marker_made : "";
				var marker = GLib.Path.build_filename(marker_dir, "ran");
				var pin = "111111";
				var phone = new OLLMchat.Settings.FilesdClient();
				phone.server_id = "revocation-paired-device";
				var phone_dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat", phone.server_id);
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
					"could not open the pairing window");
				var code = phone.try_connection("127.0.0.1", 18423, pin, false, "ollmchat");
				this.check(command_line, code == 0, "first pair code " + code.to_string());
				var removed_dir = GLib.Path.build_filename(root, "removed");
				GLib.DirUtils.create_with_parents(removed_dir, 0700);
				var saved_pem = "";
				var saved_key = "";
				this.check(command_line, GLib.FileUtils.get_contents(
					GLib.Path.build_filename(phone_dir, "client.pem"), out saved_pem),
					"paired client cert missing");
				this.check(command_line, GLib.FileUtils.get_contents(
					GLib.Path.build_filename(phone_dir, "client-key.pem"), out saved_key),
					"paired client key missing");
				GLib.FileUtils.set_contents(
					GLib.Path.build_filename(removed_dir, "client.pem"), saved_pem);
				GLib.FileUtils.set_contents(
					GLib.Path.build_filename(removed_dir, "client-key.pem"), saved_key);
				var paired_files = new OLLMrpc.Transport.Cert() {
					dir = phone_dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
				};
				paired_files.ensure();
				var paired_link = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18423) {
					accept_any = true,
					tls_certificate = paired_files.certificate
				};
				var paired_read = paired_link.call(new OLLMrpc.Request() {
					id = 2,
					method = "File.read",
					args = OLLMrpc.args("s", sentinel)
				});
				this.check(command_line, paired_read.error == null && paired_read.msg != "",
					"approved certificate could not read the sentinel");

				var closed_dir = GLib.Path.build_filename(root, "closed-pin");
				var closed_csr = new OLLMrpc.Transport.Cert() {
					dir = closed_dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "closed-window-pin",
				};
				closed_csr.ensure();
				var closed_body = "";
				this.check(command_line, GLib.FileUtils.get_contents(
					GLib.Path.build_filename(closed_dir, "client.csr"), out closed_body),
					"closed-window csr missing");
				var closed_link = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18423) {
					accept_any = true,
					tls_certificate = paired_files.certificate
				};
				var closed_reg = closed_link.call(new OLLMrpc.Request() {
					id = 3,
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("sss", pin, closed_body, "still-open")
				});
				this.check(command_line, closed_reg.error != null,
					"pairing window still accepted the old PIN");

				var pair_link = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18423) {
					accept_any = true,
					tls_certificate = paired_files.certificate
				};
				var empty_pair = pair_link.call(new OLLMrpc.Request() {
					id = 4,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", "")
				});
				string[] failures = {};
				if (empty_pair.error == null) {
					failures += "ClientCert.pair accepted an empty PIN with the window closed";
				}

				var approved_csr = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(root, "approved-empty"),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "approved-empty-pin",
				};
				approved_csr.ensure();
				var approved_body = "";
				this.check(command_line, GLib.FileUtils.get_contents(
					GLib.Path.build_filename(root, "approved-empty", "client.csr"),
					out approved_body), "approved-empty csr missing");
				var approved_link = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18423) {
					accept_any = true,
					tls_certificate = paired_files.certificate
				};
				var approved_reg = approved_link.call(new OLLMrpc.Request() {
					id = 5,
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("sss", "", approved_body, "already-approved")
				});
				if (approved_reg.error == null) {
					failures += "approved certificate re-registered with an empty PIN";
				}

				local_bin.write(new OLLMrpc.Request() {
					id = 6,
					method = "ClientCert.approved_certs"
				});
				var listed_obj = local_bin.parse();
				while (!(listed_obj is OLLMrpc.Response)) {
					listed_obj = local_bin.parse();
				}
				var listed = listed_obj as OLLMrpc.Response;
				this.check(command_line, listed != null && listed.error == null,
					"approved_certs failed before remove");
				this.check(command_line, listed.retval.type() != GLib.Type.INVALID,
					"pair left no approved certificate");
				var listed_clients = (Gee.ArrayList<RevokedClient>) listed.retval.get_object();
				foreach (var listed_client in listed_clients) {
					local_bin.write(new OLLMrpc.Request() {
						id = 7,
						method = "ClientCert.client_cert",
						args = OLLMrpc.args("sx", "remove", listed_client.id)
					});
					var removed_obj = local_bin.parse();
					while (!(removed_obj is OLLMrpc.Response)) {
						removed_obj = local_bin.parse();
					}
					var removed_row = removed_obj as OLLMrpc.Response;
					this.check(command_line,
						removed_row != null && removed_row.error == null &&
						removed_row.retval.get_boolean(),
						"client_cert remove failed");
				}
				local_bin.write(new OLLMrpc.Request() {
					id = 8,
					method = "ClientCert.approved_certs"
				});
				var after_remove_obj = local_bin.parse();
				while (!(after_remove_obj is OLLMrpc.Response)) {
					after_remove_obj = local_bin.parse();
				}
				var after_remove = after_remove_obj as OLLMrpc.Response;
				this.check(command_line, after_remove != null && after_remove.error == null,
					"approved_certs failed after remove");
				var remaining_count = 0;
				if (after_remove.retval.type() != GLib.Type.INVALID) {
					remaining_count =
						((Gee.ArrayList<RevokedClient>) after_remove.retval.get_object()).size;
				}
				this.check(command_line, remaining_count == 0,
					"remove left approved certificates");

				var removed_files = new OLLMrpc.Transport.Cert() {
					dir = removed_dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
				};
				removed_files.ensure();
				var wrong_csr = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(root, "wrong-pin"),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "wrong-pin",
				};
				wrong_csr.ensure();
				var wrong_body = "";
				this.check(command_line, GLib.FileUtils.get_contents(
					GLib.Path.build_filename(root, "wrong-pin", "client.csr"), out wrong_body),
					"wrong-pin csr missing");
				var wrong_link = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18423) {
					accept_any = true,
					tls_certificate = removed_files.certificate
				};
				try {
					var wrong_reg = wrong_link.call(new OLLMrpc.Request() {
						id = 9,
						method = "ClientCert.request_registration",
						args = OLLMrpc.args("sss", "999999", wrong_body, "wrong-pin")
					});
					this.check(command_line, wrong_reg.error != null,
						"removed certificate registered with a wrong PIN");
				} catch (GLib.Error e) {
					this.check(command_line, false,
						"removed certificate could not connect for a wrong PIN: " + e.message);
				}

				var reissue_dir = GLib.Path.build_filename(root, "reissue");
				var reissue_csr = new OLLMrpc.Transport.Cert() {
					dir = reissue_dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "reissued-device",
				};
				reissue_csr.ensure();
				var reissue_body = "";
				this.check(command_line, GLib.FileUtils.get_contents(
					GLib.Path.build_filename(reissue_dir, "client.csr"), out reissue_body),
					"reissue csr missing");
				var attack = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18423) {
					accept_any = true,
					tls_certificate = removed_files.certificate
				};
				var attack_reg = attack.call(new OLLMrpc.Request() {
					id = 10,
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("sss", "", reissue_body, "removed-phone")
				});
				var issued_pem = "";
				if (attack_reg.error == null) {
					failures += "removed certificate registered with an empty PIN";
					var packed = (string[]) attack_reg.retval;
					if (packed.length >= 1) {
						issued_pem = packed[0];
					}
				}
				local_bin.write(new OLLMrpc.Request() {
					id = 11,
					method = "ClientCert.approved_certs"
				});
				var after_attack_obj = local_bin.parse();
				while (!(after_attack_obj is OLLMrpc.Response)) {
					after_attack_obj = local_bin.parse();
				}
				var after_attack = after_attack_obj as OLLMrpc.Response;
				this.check(command_line, after_attack != null && after_attack.error == null,
					"approved_certs failed after empty PIN");
				var minted_count = 0;
				if (after_attack.retval.type() != GLib.Type.INVALID) {
					minted_count =
						((Gee.ArrayList<RevokedClient>) after_attack.retval.get_object()).size;
				}
				if (minted_count != 0) {
					failures += "empty PIN inserted an approved certificate";
				}

				var bare = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18423) {
					accept_any = true
				};
				try {
					var bare_reg = bare.call(new OLLMrpc.Request() {
						id = 12,
						method = "ClientCert.request_registration",
						args = OLLMrpc.args("sss", "", reissue_body, "no-cert")
					});
					if (bare_reg.error == null) {
						failures += "client with no certificate registered with an empty PIN";
					}
				} catch (GLib.Error e) {
					command_line.print("no-certificate handshake: %s\n", e.message);
				}

				var use_files = removed_files;
				if (issued_pem != "") {
					GLib.FileUtils.set_contents(
						GLib.Path.build_filename(reissue_dir, "client.pem"), issued_pem);
					use_files = new OLLMrpc.Transport.Cert() {
						dir = reissue_dir,
						cert_pem = "client.pem",
						key_pem = "client-key.pem",
					};
					use_files.ensure();
				}
				var use_link = new OLLMrpc.Transport.TlsClient("127.0.0.1", 18423) {
					accept_any = true,
					tls_certificate = use_files.certificate
				};
				var read_allowed = false;
				var read_msg = "";
				try {
					var used_read = use_link.call(new OLLMrpc.Request() {
						id = 13,
						method = "File.read",
						args = OLLMrpc.args("s", sentinel)
					});
					read_msg = used_read.msg;
					if (used_read.error == null && used_read.msg != "") {
						read_allowed = true;
					}
				} catch (GLib.Error e) {
					command_line.print("file read handshake: %s\n", e.message);
				}
				if (issued_pem != "" && read_allowed) {
					failures += "reissued certificate read the sentinel (" + read_msg.length.to_string() + " bytes)";
				}
				if (issued_pem == "" && read_allowed) {
					failures += "removed certificate read the sentinel (" + read_msg.length.to_string() + " bytes)";
				}
				string[] allow_write = {};
				allow_write += marker_dir;
				var sandbox_blocked = false;
				var sandbox_msg = "handle issued";
				var sandbox_handle = (uint64) 0;
				try {
					var created = use_link.call(new OLLMrpc.Request() {
						id = 14,
						method = "Sandbox-Bubble.rpc_create",
						args = OLLMrpc.args("sssbSbx",
							"", "printf revocation-marker > " + marker, "",
							true, allow_write, false, (int64) 1)
					});
					if (created.error != null &&
						created.error.code == (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED) {
						sandbox_blocked = true;
					}
					if (created.error != null &&
						created.error.message == "client certificate required") {
						sandbox_blocked = true;
					}
					if (created.error != null) {
						sandbox_msg = created.error.message;
					}
					if (created.error == null) {
						sandbox_handle = created.retval.get_uint64();
					}
				} catch (GLib.Error e) {
					sandbox_blocked = true;
					command_line.print("sandbox handshake: %s\n", e.message);
				}
				if (!sandbox_blocked) {
					failures += "Sandbox-Bubble.rpc_create was not refused: " + sandbox_msg;
				}
				if (sandbox_handle != 0) {
					var ran = use_link.call(new OLLMrpc.Request() {
						id = 15,
						method = "Sandbox-Bubble.rpc_run",
						args = OLLMrpc.args("t", sandbox_handle)
					});
					var marker_deadline = GLib.get_monotonic_time() + 2 * 1000000;
					while (GLib.get_monotonic_time() < marker_deadline) {
						if (GLib.FileUtils.test(marker, GLib.FileTest.EXISTS)) {
							break;
						}
						GLib.Thread.usleep(50000);
					}
					if (ran.error == null) {
						failures += "Sandbox-Bubble.rpc_run started a command";
					}
				}
				if (GLib.FileUtils.test(marker, GLib.FileTest.EXISTS)) {
					failures += "sandbox command wrote a marker file";
				}

				var fresh = new OLLMchat.Settings.FilesdClient();
				fresh.server_id = "revocation-fresh-device";
				local_bin.write(new OLLMrpc.Request() {
					id = 16,
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				});
				var rearmed_obj = local_bin.parse();
				while (!(rearmed_obj is OLLMrpc.Response)) {
					rearmed_obj = local_bin.parse();
				}
				var rearmed = rearmed_obj as OLLMrpc.Response;
				this.check(command_line, rearmed != null && rearmed.error == null,
					"could not open the pairing window again");
				var fresh_code = fresh.try_connection(
					"127.0.0.1", 18423, pin, false, "ollmchat");
				this.check(command_line, fresh_code == 0,
					"open window rejected the PIN, code " + fresh_code.to_string());
				this.check(command_line, failures.length == 0, string.joinv("; ", failures));
			} catch (GLib.Error e) {
				daemon.force_exit();
				command_line.printerr("Error: %s\n", e.message);
				/* Application.run zeroes the status after each main-loop
				 * turn, so the process has to exit here. */
				GLib.Process.exit(1);
			}
			daemon.force_exit();
		}
	}
}

int main(string[] args)
{
	var root = GLib.DirUtils.mkdtemp("/tmp/ollm-revoke-XXXXXX");
	if (root == null) {
		return 1;
	}
	var xdg = GLib.Path.build_filename(root, "xdg");
	GLib.DirUtils.create_with_parents(xdg, 0700);
	GLib.Environment.set_variable("XDG_DATA_HOME", xdg, true);
	GLib.Environment.set_variable("OLLM_REVOCATION_HOME", root, true);
	return new OLLMrpcTests.TestRpcFilesdRevocation().run(args);
}
