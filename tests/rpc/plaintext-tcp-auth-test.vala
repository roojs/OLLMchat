/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Plaintext TCP on 127.0.0.1 must not run File, ProjectManager,
 * ClientCert, Codebase, Folder, Sandbox, or Daemon methods.
 * Windows starts that listener for every non-interactive daemon
 * (ollmfilesd/Application.vala, libocrpc/windows/ClientBoot.vala).
 * These checks fail until that listener rejects an unauthenticated
 * client before any file or process side effect.
 */

namespace OLLMrpcTests
{
	class WireFile : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string path { get; set; default = ""; }
		public bool is_text { get; set; default = false; }
	}

	class TestRpcPlaintextTcp : RpcTestAppBase
	{
		protected static string opt_peer_host = "";
		protected static int opt_peer_port = 0;
		protected static string opt_peer_path = "";

		public TestRpcPlaintextTcp()
		{
			base("com.roojs.ollmchat.test-rpc-plaintext-tcp");
		}

		protected override string get_app_name()
		{
			return "test-rpc-plaintext-tcp";
		}

		protected override OptionContext app_options()
		{
			var opt_context = new OptionContext(this.get_app_name());
			var entries = new OptionEntry[6];
			entries[0] = base_options[0];
			entries[1] = base_options[1];
			entries[2] = { "peer-host", 0, 0, OptionArg.STRING, ref opt_peer_host,
				"Plaintext peer host", "HOST" };
			entries[3] = { "peer-port", 0, 0, OptionArg.INT, ref opt_peer_port,
				"Plaintext peer port", "PORT" };
			entries[4] = { "peer-path", 0, 0, OptionArg.STRING, ref opt_peer_path,
				"File the peer must not read", "PATH" };
			entries[5] = { null };
			opt_context.add_main_entries(entries, null);
			return opt_context;
		}

		protected override void run_rpc_test(
			GLib.ApplicationCommandLine command_line
		) throws GLib.Error
		{
			OLLMrpc.rpc_register();
			OLLMrpc.Daemon.rpc_register();
			OLLMrpc.Bin.register("File", typeof(WireFile));
			if (opt_peer_port != 0) {
				this.check(command_line, opt_peer_host != "" && opt_peer_path != "",
					"--peer-host and --peer-path are required with --peer-port");
				var direct = false;
				try {
					var ignored = "";
					direct = GLib.FileUtils.get_contents(opt_peer_path, out ignored);
				} catch (GLib.Error e) {
					direct = false;
				}
				this.check(command_line, !direct,
					"peer read the private file without RPC");
				var peer_client = new GLib.SocketClient();
				peer_client.timeout = 5;
				var peer_conn = peer_client.connect_to_host(
					opt_peer_host, (uint16) opt_peer_port);
				var peer_bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(peer_conn.get_input_stream()),
					new GLib.DataOutputStream(peer_conn.get_output_stream())
				);
				peer_bin.mode = OLLMrpc.Bin.Mode.IGNORE_UNKNOWN;
				peer_bin.write(new OLLMrpc.Request() {
					id = 1,
					method = "File.read",
					args = OLLMrpc.args("s", opt_peer_path)
				});
				var peer_parsed = peer_bin.parse();
				while (peer_parsed is OLLMrpc.Notification) {
					peer_parsed = peer_bin.parse();
				}
				var peer_response = peer_parsed as OLLMrpc.Response;
				this.check(command_line, peer_response != null,
					"peer reply was not a response");
				var peer_marker = "plain-tcp-secret-marker";
				var peer_bytes = peer_marker.data;
				var peer_encoded = GLib.Base64.encode(
					peer_bytes[0:peer_bytes.length > 0 ? peer_bytes.length - 1 : 0]);
				if (peer_response.error == null ||
					peer_response.msg.contains(peer_marker) ||
					peer_response.msg.contains(peer_encoded)) {
					command_line.printerr("peer File.read was accepted msg=%s\n",
						peer_response.msg);
					Posix.exit(1);
				}
				Posix.exit(0);
			}

			var exe = "";
			var exe_env = GLib.Environment.get_variable("OLLMFILESD");
			if (exe_env != null) {
				exe = exe_env;
			}
			if (exe == "") {
				command_line.printerr("OLLMFILESD is not set\n");
				Posix.exit(1);
			}
			var self_bin = "";
			var self_env = GLib.Environment.get_variable("OLLM_TCP_SELF");
			if (self_env != null) {
				self_bin = self_env;
			}
			if (self_bin == "") {
				command_line.printerr("OLLM_TCP_SELF is not set\n");
				Posix.exit(1);
			}
			var root = "";
			var root_env = GLib.Environment.get_variable("OLLM_TCP_HOME");
			if (root_env != null) {
				root = root_env;
			}
			if (root == "") {
				command_line.printerr("OLLM_TCP_HOME is not set\n");
				Posix.exit(1);
			}
			var failures = "";
			string[] cases = {
				"read",
				"exists",
				"changed",
				"chmod",
				"write",
				"delete",
				"hello",
				"shutdown",
				"db_projects",
				"create_project",
				"activate",
				"approved_certs",
				"can_wrap",
				"fetch_dir",
				"fetch",
				"file_info",
				"stop"
			};
			var port = 35110;
			foreach (var name in cases) {
				port++;
				var case_dir = GLib.Path.build_filename(root, name);
				GLib.DirUtils.create_with_parents(case_dir, 0700);
				var marker = "plain-tcp-secret-marker";
				var secret_path = GLib.Path.build_filename(case_dir, "secret.txt");
				GLib.FileUtils.set_contents(secret_path, marker);
				Posix.chmod(secret_path, 0600);
				var written_path = GLib.Path.build_filename(case_dir, "written.txt");
				var project_path = GLib.Path.build_filename(case_dir, "project-marker");
				GLib.DirUtils.create_with_parents(project_path, 0700);
				var err_path = GLib.Path.build_filename(root, name + ".err");
				var launcher = new GLib.SubprocessLauncher(GLib.SubprocessFlags.NONE);
				launcher.setenv("OLLMFILES_IS_TEST", "1", true);
				launcher.setenv("OLLMFILESD_DAEMON", "1", true);
				launcher.set_stderr_file_path(err_path);
				var daemon = launcher.spawnv({
					exe,
					"--tcp",
					"--tcp-host=127.0.0.1",
					"--tcp-port=" + port.to_string(),
					"--data-dir=" + case_dir
				});
				var case_failure = "";
				try {
					var ready = false;
					var deadline = GLib.get_monotonic_time() + 15 * 1000000;
					while (GLib.get_monotonic_time() < deadline) {
						try {
							var probe = new GLib.SocketClient();
							probe.timeout = 1;
							var probed = probe.connect_to_host("127.0.0.1", (uint16) port);
							probed.close();
							ready = true;
							break;
						} catch (GLib.Error e) {
							GLib.Thread.usleep(100000);
						}
					}
					var err_text = "";
					try {
						GLib.FileUtils.get_contents(err_path, out err_text);
					} catch (GLib.Error e) {
					}
					if (!ready) {
						case_failure = name + ": daemon did not listen: " + err_text;
					}
					if (case_failure == "") {
						var client = new GLib.SocketClient();
						client.timeout = 8;
						var conn = client.connect_to_host("127.0.0.1", (uint16) port);
						var bin = new OLLMrpc.Bin.Stream(
							new GLib.DataInputStream(conn.get_input_stream()),
							new GLib.DataOutputStream(conn.get_output_stream())
						);
						bin.mode = OLLMrpc.Bin.Mode.IGNORE_UNKNOWN;
						var request = new OLLMrpc.Request() {
							id = 1,
							method = "RPC-Daemon.hello",
							args = OLLMrpc.args("is", 1, "plaintext-peer")
						};
						switch (name) {
							case "read":
								request.method = "File.read";
								request.args = OLLMrpc.args("s", secret_path);
								break;
							case "exists":
								request.method = "File.exists";
								request.args = OLLMrpc.args("s", secret_path);
								break;
							case "changed":
								request.method = "File.changed.check";
								request.args = OLLMrpc.args("sx", secret_path, (int64) 0);
								break;
							case "chmod":
								request.method = "File.apply_permissions";
								request.args = OLLMrpc.args("su", secret_path, (uint) 511);
								break;
							case "write":
								request.method = "File.rpc_write";
								request.args = OLLMrpc.args("ssssu",
									written_path, marker, "f", "", (uint) 0);
								break;
							case "delete":
								request.method = "File.rpc_delete";
								request.args = OLLMrpc.args("s", secret_path);
								break;
							case "hello":
								break;
							case "shutdown":
								request.method = "RPC-Daemon.shutdown";
								request.args = OLLMrpc.args("");
								break;
							case "db_projects":
								request.method = "ProjectManager.db_projects";
								request.args = OLLMrpc.args("");
								break;
							case "create_project":
								request.method = "ProjectManager.rpc_create_project";
								request.args = OLLMrpc.args("s", project_path);
								break;
							case "activate":
								request.method = "ProjectManager.rpc_activate_project";
								request.args = OLLMrpc.args("sb", project_path, true);
								break;
							case "approved_certs":
								request.method = "ClientCert.approved_certs";
								request.args = OLLMrpc.args("");
								break;
							case "can_wrap":
								request.method = "Sandbox-Bubble.can_wrap";
								request.args = OLLMrpc.args("");
								break;
							case "fetch_dir":
								request.method = "Folder.fetch_dir";
								request.args = OLLMrpc.args("s", secret_path);
								break;
							case "fetch":
								request.method = "File.fetch";
								request.args = OLLMrpc.args("ss", project_path, secret_path);
								break;
							case "file_info":
								request.method = "Codebase.file_info";
								request.args = OLLMrpc.args("s", secret_path);
								break;
							case "stop":
								request.method = "Codebase.stop";
								request.args = OLLMrpc.args("");
								break;
							default:
								case_failure = name + ": unknown case";
								break;
						}
						if (case_failure == "") {
							bin.write(request);
							OLLMrpc.Response? response = null;
							try {
								var parsed = bin.parse();
								while (parsed is OLLMrpc.Notification) {
									parsed = bin.parse();
								}
								response = parsed as OLLMrpc.Response;
								if (response == null) {
									case_failure = name + ": reply was not a response";
								}
							} catch (GLib.Error e) {
								if (e.message.contains("unknown bin property") ||
									e.message.contains("unknown alias") ||
									e.message.contains("REGISTRATION")) {
									case_failure = name + ": server returned a result: " + e.message;
								}
							}
							if (response != null && response.error == null && case_failure == "") {
								case_failure = name + ": unauthenticated call was accepted msg=" +
									response.msg;
							}
							if (response != null) {
								var encoded = GLib.Base64.encode(
									marker.data[0:marker.data.length > 0 ? marker.data.length - 1 : 0]);
								if (response.msg.contains(marker) || response.msg.contains(encoded)) {
									case_failure = name + ": reply contained the file";
								}
							}
							Posix.Stat st;
							if (Posix.stat(secret_path, out st) != 0) {
								case_failure = name + ": secret file was removed";
							}
							if (name == "chmod" && Posix.stat(secret_path, out st) == 0 &&
								(st.st_mode & 0777) != 0600) {
								case_failure = name + ": mode changed before refusal";
							}
							if (name == "write" &&
								GLib.FileUtils.test(written_path, GLib.FileTest.EXISTS)) {
								case_failure = name + ": wrote a file before refusal";
							}
							if (name == "delete") {
								try {
									bin.write(new OLLMrpc.Request() {
										id = 2,
										method = "ProjectManager.rpc_create_project",
										args = OLLMrpc.args("s", project_path)
									});
									var created = bin.parse();
									while (created is OLLMrpc.Notification) {
										created = bin.parse();
									}
									bin.write(new OLLMrpc.Request() {
										id = 3,
										method = "ProjectManager.rpc_activate_project",
										args = OLLMrpc.args("sb", project_path, true)
									});
									var activated = bin.parse();
									while (activated is OLLMrpc.Notification) {
										activated = bin.parse();
									}
									bin.write(new OLLMrpc.Request() {
										id = 4,
										method = "File.rpc_write",
										args = OLLMrpc.args("ssssu",
											secret_path, "plain-tcp-replaced", "f", "", (uint) 0)
									});
									var wrote = bin.parse();
									while (wrote is OLLMrpc.Notification) {
										wrote = bin.parse();
									}
									bin.write(new OLLMrpc.Request() {
										id = 5,
										method = "File.rpc_delete",
										args = OLLMrpc.args("s", secret_path)
									});
									var removed = bin.parse();
									while (removed is OLLMrpc.Notification) {
										removed = bin.parse();
									}
								} catch (GLib.Error e) {
								}
								var body = "";
								if (!GLib.FileUtils.test(secret_path, GLib.FileTest.EXISTS) ||
									!GLib.FileUtils.get_contents(secret_path, out body) ||
									body != marker) {
									case_failure = name + ": file changed before refusal";
								}
							}
							if (name == "create_project") {
								daemon.send_signal(Posix.Signal.TERM);
								try {
									daemon.wait();
								} catch (GLib.Error e) {
								}
								var db_path = GLib.Path.build_filename(case_dir, "files.sqlite");
								try {
									var info = GLib.File.new_for_path(db_path).query_info(
										GLib.FileAttribute.STANDARD_SIZE,
										GLib.FileQueryInfoFlags.NONE);
									var stream = GLib.File.new_for_path(db_path).read();
									var dbdata = stream.read_bytes((size_t) info.get_size()).get_data();
									stream.close();
									var needle = project_path.data;
									var needle_len = needle.length > 0 ? needle.length - 1 : 0;
									var found = false;
									if (needle_len > 0 && dbdata.length >= needle_len) {
										for (var i = 0; i <= dbdata.length - needle_len; i++) {
											var match = true;
											for (var j = 0; j < needle_len; j++) {
												if (dbdata[i + j] != needle[j]) {
													match = false;
													break;
												}
											}
											if (!match) {
												continue;
											}
											found = true;
											break;
										}
									}
									if (found) {
										case_failure = name + ": project row was stored before refusal";
									}
								} catch (GLib.Error e) {
									if (case_failure == "") {
										case_failure = name + ": " + e.message;
									}
								}
							}
							if (name == "shutdown") {
								GLib.Thread.usleep(400000);
								var ident = daemon.get_identifier();
								var exited = ident == null || ident == "";
								if (!exited && Posix.kill((Posix.pid_t) int.parse(ident), 0) != 0) {
									exited = true;
								}
								if (exited) {
									case_failure = name + ": daemon exited";
								}
							}
							if (name == "read") {
								var peer_id = new GLib.SubprocessLauncher(
									GLib.SubprocessFlags.STDOUT_SILENCE |
									GLib.SubprocessFlags.STDERR_SILENCE);
								var peer_user = false;
								try {
									peer_id.spawnv({ "id", "ollmpeer" }).wait_check();
									peer_user = true;
								} catch (GLib.Error e) {
									peer_user = false;
								}
								if (peer_user) {
									var peer_err = GLib.Path.build_filename(root, "peer.err");
									var peer_launcher = new GLib.SubprocessLauncher(
										GLib.SubprocessFlags.NONE);
									peer_launcher.set_stderr_file_path(peer_err);
									try {
										var peer = peer_launcher.spawnv({
											"sudo", "-n", "-u", "ollmpeer",
											self_bin,
											"--peer-host=127.0.0.1",
											"--peer-port=" + port.to_string(),
											"--peer-path=" + secret_path
										});
										peer.wait_check();
									} catch (GLib.Error e) {
										var peer_text = "";
										try {
											GLib.FileUtils.get_contents(peer_err, out peer_text);
										} catch (GLib.Error read_err) {
										}
										var peer_failure = "read: other user was not rejected: " +
											peer_text + " " + e.message;
										if (case_failure != "") {
											case_failure += "\n" + peer_failure;
										}
										if (case_failure == "") {
											case_failure = peer_failure;
										}
									}
								}
							}
						}
					}
				} catch (GLib.Error e) {
					if (case_failure == "") {
						case_failure = name + ": " + e.message;
					}
				}
				daemon.force_exit();
				if (case_failure == "") {
					continue;
				}
				if (failures != "") {
					failures += "\n";
				}
				failures += case_failure;
			}
			if (failures != "") {
				command_line.printerr("%s\n", failures);
				Posix.exit(1);
			}
		}
	}
}

int main(string[] args)
{
	var root = GLib.DirUtils.mkdtemp("/tmp/ollm-plain-tcp-XXXXXX");
	if (root == null) {
		return 1;
	}
	var self_path = args[0];
	if (!GLib.Path.is_absolute(self_path)) {
		self_path = GLib.Path.build_filename(
			GLib.Environment.get_current_dir(), self_path);
	}
	GLib.Environment.set_variable("OLLM_TCP_HOME", root, true);
	GLib.Environment.set_variable("OLLM_TCP_SELF", self_path, true);
	return new OLLMrpcTests.TestRpcPlaintextTcp().run(args);
}
