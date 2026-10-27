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

namespace OLLMtools.Bash
{
	/**
	 * Request handler for the bash tool. New commands run on the file daemon.
	 */
	public class Request : OLLMchat.Tool.RequestBase
	{
		// Parameter properties
		public string command { get; set; default = ""; }
		public string working_dir { get; set; default = ""; }
		public bool network { get; set; default = false; }
		/**
		 * When true, run via sudo on Linux after permission (outside bubblewrap).
		 */
		public bool run_as_root { get; set; default = false; }
		/** Tool string allow_write: no, project, or colon-separated absolute roots on Unix. Parsed in execute() before permission. */
		public string allow_write { get; set; default = "project"; }
		/**
		 * Wall-clock seconds before the child is killed.
		 * Omitted JSON uses 60.
		 */
		public int timeout { get; set; default = 60; }

		/**
		 * Bwrap pid from a previous ''bash'' call.
		 * ''0'' means this call is a new command.
		 */
		public int pid { get; set; default = 0; }

		/**
		 * True when this ''bash'' call will spawn on the daemon.
		 * Set before permission so the sandbox question matches the host that runs the command.
		 */
		private bool remote_wrap = false;

		/**
		 * True once a negative timeout has handed the pid back
		 * and the command is still running.
		 */
		private bool detached = false;

		/** Validated allow_write tokens; populated only in {@link execute} before permission. */
		private string[] write_array = {};
		
		/** When true, {@link execute} appends a unique suffix to {@link permission_target_path} so each prompt is distinct (used for non-bwrap runs). */
		private bool is_complex_command = false;
		private int output_lines = 0;
		private bool stopped = false;
		private bool timed_out = false;
		private uint timeout_src = 0;
		private string[] pending_output = {};
		private uint pending_output_src = 0;
		private GLib.FileOutputStream spill_stream;
		private bool spill_active = false;
		private string spill_path = "";
		private GLib.Subprocess child;
		private bool child_active = false;
		private OLLMbwrap.Bubble bubble;
		private bool bubble_active = false;

		public override void stop()
		{
			this.stopped = true;
			if (this.bubble_active) {
				this.bubble.stop();
				return;
			}
			if (!this.child_active) {
				return;
			}
#if !G_OS_WIN32
			var id = this.child.get_identifier();
			if (id != null) {
				Posix.kill(-(int.parse(id)), Posix.Signal.KILL);
			}
#endif
			this.child.force_exit();
		}

		public override string to_summary ()
		{
			string[] lines = {};
			lines += "Command:";
			lines += this.command;
			if (this.working_dir.strip () != "") {
				lines += "Working directory: " + this.working_dir;
			}
			if (this.network) {
				lines += "Network: yes";
			}
			if (this.run_as_root) {
				lines += "Run as root: yes";
			}
			if (this.timeout != 60) {
				lines += "Timeout: " + this.timeout.to_string() + "s";
			}
			return string.joinv ("\n", lines);
		}
		
		/**
		 * Normalizes working_dir to an absolute path.
		 * 
		 * - If working_dir is empty, returns empty string (will use default project directory)
		 * - If working_dir is already absolute, returns it as-is
		 * - If working_dir is "playground", returns $HOME/playground (bind mount in bwrap)
		 * - If working_dir is relative, treats it as relative to user's home directory ($HOME)
		 * 
		 * @return Normalized absolute path, or empty string if working_dir is empty
		 */
		private string normalize_working_dir()
		{
			if (this.working_dir.strip() == "") {
				return "";
			}
			
			var dir = this.working_dir.strip();
			
			// If already absolute, return as-is
			if (GLib.Path.is_absolute(dir)) {
				return dir;
			}
			
			// Special case: "playground" maps to $HOME/playground (bind mount in bwrap)
			if (dir == "playground") {
				return GLib.Path.build_filename(GLib.Environment.get_home_dir(), "playground");
			}
			
			// Relative path: treat as relative to user's home directory
			return GLib.Path.build_filename(GLib.Environment.get_home_dir(), dir);
		}

		/**
		 * Short suffix when bubblewrap cannot be used (Flatpak or bwrap missing from PATH).
		 * Does not repeat the confirm lead-in; callers state sandbox unavailable if needed.
		 */
		private string bwrap_unavailable_note ()
		{
			if (this.remote_wrap || OLLMbwrap.Bubble.can_wrap()) {
				return "";
			}
#if G_OS_WIN32
			return " (Windows: commands run unsandboxed.)";
#else
			if (GLib.Environment.get_variable ("FLATPAK_ID") != null) {
				return " (Flatpak: bubblewrap is not used here.)";
			}
			return " (Install bubblewrap or add bwrap to PATH to enable sandboxing.)";
#endif
		}

		/**
		 * Sets permission_question, permission_target_path, permission_operation.
		 *
		 * With bubblewrap: only prompt for network access or extra allow_write host roots;
		 * default sandboxed runs skip execute permission (seccomp / mount policy contain the run).
		 * Without bubblewrap: prompt every command — there is no equivalent sandbox.
		 *
		 * @return true if permission is needed of false if it can be skipped
		 */
		public override bool build_perm_question()
		{
			this.permission_command = this.command.strip();

			if (this.run_as_root) {
				this.one_time_only = true;
				this.permission_target_path = "run_as_root#" + GLib.get_real_time ().to_string ();
				this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
				this.permission_question = "Confirm — Run as ROOT (high risk)\n\n"
					+ "This command will run with root privileges on your system, outside the normal sandbox.\n\n"
					+ "WARNING: This may damage your system. Only allow this if you understand exactly what the command does. If you get it wrong, you may not be able to log in tomorrow (or worse).\n\n"
					+ "If asked, enter your password. After a successful check it is stored in the system keyring.";
				return true;
			}

			// Handle network requests first - they always require approval (even with bubblewrap)
			if (this.network) {
				this.one_time_only = true;
				// Use unique identifier to bypass cache (timestamp-based)
				this.permission_target_path = "network#" + GLib.get_real_time().to_string();
				this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
				this.permission_question = "Confirm — Network access requested.\n\n"
					+ "Allow this command to run with network access?"
					+ this.bwrap_unavailable_note ();
				return true;
			}

			var can = this.remote_wrap || OLLMbwrap.Bubble.can_wrap();
			var head0 = this.write_array.length > 0 ? this.write_array[0].down() : "";
			var default_sandbox_writes = (head0 == "no" || head0 == "project");

			if (can && !default_sandbox_writes) {
				this.one_time_only = true;
				this.permission_target_path = "allow_write_paths#" + GLib.get_real_time ().to_string ();
				this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
				this.permission_question = "Confirm — Additional file write access requested.\n\n"
					+ "This request asks for write permission to these folders: "
					+ string.joinv (", ", this.write_array)
					+ "?"
					+ this.bwrap_unavailable_note ();
				return true;
			}

			if (can && default_sandbox_writes) {
				this.permission_question = "";
				this.permission_command = "";
				this.is_complex_command = false;
				return false;
			}

			// No bubblewrap: approve each run (no bwrap containment)
			this.is_complex_command = true;
			this.one_time_only = true;
			this.permission_target_path = this.command;
			this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
			this.permission_question = "Confirm (sandbox unavailable):\n\nRun this command?"
				+ this.bwrap_unavailable_note ();
			return true;
		}
		
		/**
		 * Override execute() so non-bwrap runs use a unique permission key per invocation
		 * (see {@link is_complex_command} after {@link build_perm_question}).
		 */
		public override async string execute()
		{
			if (this.pid != 0) {
				try {
					return yield this.manage();
				} catch (GLib.Error e) {
					return "ERROR: " + e.message;
				}
			}
			if (this.command.strip() == "") {
				return "ERROR: Invalid parameters";
			}
			if (this.run_as_root) {
				return "ERROR: run_as_root is not available";
			}
			var bash_tool = (Tool) this.tool;
			if (bash_tool.project_manager == null || !bash_tool.project_manager.rpc.connected) {
				return "ERROR: bash needs the file daemon";
			}
			try {
				var wrap = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
					method = "Sandbox-Bubble.can_wrap"
				});
				if (wrap.msg != "1") {
					return "ERROR: sandbox unavailable";
				}
			} catch (GLib.Error e) {
				return "ERROR: " + e.message;
			}
			this.remote_wrap = true;
			
			// Normalize and validate working_dir if provided
			var normalized_working_dir = this.normalize_working_dir();
			if (normalized_working_dir != "") {
				// $HOME/playground may be created by Bubble.ensure_home_playground_mount_point(); skip host existence check for it
				var home_playground = GLib.Path.build_filename(GLib.Environment.get_home_dir(), "playground");
				if (normalized_working_dir != home_playground) {
					var dir_file = GLib.File.new_for_path(normalized_working_dir);
					if (!GLib.FileUtils.test(dir_file.get_path(), GLib.FileTest.EXISTS)) {
						return "ERROR: Working directory does not exist: " + normalized_working_dir;
					}
					var file_type = dir_file.query_file_type(GLib.FileQueryInfoFlags.NONE, null);
					if (file_type != GLib.FileType.DIRECTORY) {
						return "ERROR: Working directory is not a directory: " + normalized_working_dir;
					}
				}
				this.working_dir = normalized_working_dir;
			}

			this.write_array = {};
			var run_command_tool = (Tool) this.tool;
			var project_manager = run_command_tool.project_manager;
			var project = (project_manager != null && project_manager.active_project != null)
				? project_manager.active_project
				: (OLLMfiles.Folder?) null;
			var aw_line = this.allow_write.strip ();
			aw_line = (aw_line == "") ? ((project != null) ? "project" : "no") : aw_line;
			var ar = aw_line.split (":");
			for (var i = 0; i < ar.length; i++) {
				var piece = ar[i].strip ();
				if (i == 0 && (piece.down () == "no" || piece.down () == "project")) {
					this.write_array += piece.down ();
					break;
				}
				if (piece == "") {
					continue;
				}
				if (!GLib.Path.is_absolute (piece)) {
					return "ERROR: allow_write: path must be absolute: " + piece;
				}
				this.write_array += piece;
			}
			if (this.write_array.length < 1) {
				return "ERROR: allow_write must contain project/no or a list of absolute paths";
			}

			var need_perm = this.build_perm_question();
			if (need_perm) {
				// For complex commands, use a unique identifier to bypass cache
				if (this.is_complex_command) {
					var unique_path = this.permission_target_path + "#" + GLib.get_real_time().to_string();
					this.permission_target_path = unique_path;
				}
				if (!(yield this.agent.get_permission_provider().request(this))) {
					return "ERROR: Permission denied: " + this.permission_question;
				}
			}
			
			var run_status = "Running command (NOT IN SANDBOX)";
			if (this.remote_wrap || OLLMbwrap.Bubble.can_wrap()) {
				run_status = "Running command in sandbox";
			}
			this.agent.notification(new OLLMrpc.Notification() {
				method = "client.run_tool.start",
				message = this.command.strip(),
				action = run_status,
			});
			this.spill_path = GLib.Path.build_filename(
				this.agent.chat().agent.session.task_dir(),
				"run_command-" + this.request_id.to_string() + ".log");
			try {
				this.spill_stream = GLib.File.new_for_path(this.spill_path).replace(
					null, false, GLib.FileCreateFlags.PRIVATE, null);
				this.spill_active = true;
			} catch (GLib.Error e) {
				this.spill_active = false;
			}
			try {
				return yield this.bash_remote();
			} catch (Error e) {
				if (e.message != "") {
					return "ERROR: " + e.message;
				}
				return "ERROR: " + e.domain.to_string() + " " + e.code.to_string();
			} finally {
				if (this.timeout_src != 0) {
					GLib.Source.remove(this.timeout_src);
					this.timeout_src = 0;
				}
				if (this.pending_output_src != 0) {
					GLib.Source.remove(this.pending_output_src);
					this.pending_output_src = 0;
				}
				if (this.pending_output.length > 0) {
					this.agent.notification(new OLLMrpc.Notification() {
						method = "client.run_tool.output",
						message = string.joinv("\n", this.pending_output) + "\n",
						id = this.request_id,
					});
					this.pending_output = {};
				}
				if (this.spill_active && !this.detached) {
					try {
						this.spill_stream.close(null);
					} catch (GLib.Error e) {
					}
					this.spill_active = false;
					if (this.output_lines <= 50) {
						try {
							GLib.File.new_for_path(this.spill_path).delete(null);
						} catch (GLib.Error e) {
						}
						try {
							GLib.File.new_for_path(GLib.Path.get_dirname(this.spill_path)).delete(null);
						} catch (GLib.Error e) {
						}
					}
				}
				if (!this.detached) {
					this.agent.notification(new OLLMrpc.Notification() {
						method = "client.run_tool.end",
						message = this.command.strip(),
					});
				}
			}
		}
		
		private static bool bash_listening = false;
		private static Gee.HashMap<int, Request> bash_lease;

		/**
		 * Spawn on the daemon and wait.
		 *
		 * Caller has already checked ''can_wrap'' and permission.
		 * A negative timeout uses 15 seconds and may detach.
		 *
		 * @return tool result, either the command output or the pid block
		 */
		private async string bash_remote() throws GLib.Error
		{
			var bash_tool = (Tool) this.tool;
			var project_manager = bash_tool.project_manager;
			if (project_manager == null) {
				return "ERROR: bash needs the file daemon";
			}
			var project_path = "";
			if (project_manager.active_project != null) {
				project_path = project_manager.active_project.path;
			}
			var keep_stdin = this.timeout < 0;
			var seconds = keep_stdin ? 15 : this.timeout;
			var session_id = this.agent.chat().agent.session.id;
			var created = yield project_manager.rpc.call(new OLLMrpc.Request() {
				method = "Sandbox-Bubble.rpc_create",
				args = OLLMrpc.args(
					"sssbSbx",
					project_path,
					this.command,
					this.working_dir,
					this.network,
					this.write_array,
					keep_stdin,
					session_id
				)
			});
			if (created.error != null) {
				return "ERROR: " + created.error.message;
			}
			var lease = created.retval.get_uint64();
			yield project_manager.rpc.call(new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.rpc_signal",
				lease_id = lease,
				args = OLLMrpc.args("s", "output")
			});
			yield project_manager.rpc.call(new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.rpc_signal",
				lease_id = lease,
				args = OLLMrpc.args("s", "finished")
			});
			this.arm_bash_listener(project_manager, lease);
			var started = yield project_manager.rpc.call(new OLLMrpc.Request() {
				method = "Sandbox-Bubble.rpc_run",
				args = OLLMrpc.args("t", lease)
			});
			if (started.error != null) {
				return "ERROR: " + started.error.message;
			}
			var pid = (int) started.retval.get_int();
			var waited = yield project_manager.rpc.call(new OLLMrpc.Request() {
				method = "Sandbox-Bubble.wait",
				args = OLLMrpc.args("iix", pid, seconds, session_id)
			});
			var state = (int) waited.retval.get_int();
			if (state >= 0) {
				return this.bash_finished_text(waited.msg);
			}
			if (keep_stdin) {
				this.detached = true;
				return this.pid_block(-pid, false);
			}
			yield project_manager.rpc.call(new OLLMrpc.Request() {
				method = "Sandbox-Bubble.kill",
				args = OLLMrpc.args("ix", pid, session_id)
			});
			this.timed_out = true;
			return this.bash_finished_text(waited.msg);
		}

		/**
		 * ''kill'' / ''tail'' / ''wait'' / ''send'' for a pid this session started.
		 *
		 * @return the verb result
		 */
		private async string manage() throws GLib.Error
		{
			if (this.pid >= 0) {
				return "command has ended";
			}
			var bash_tool = (Tool) this.tool;
			var session_id = this.agent.chat().agent.session.id;
			var command = this.command.strip();
			var space = command.index_of(" ");
			var verb = command;
			var payload = "";
			if (space > 0) {
				verb = command.substring(0, space);
				payload = command.substring(space + 1);
			}
			switch (verb) {
				case "kill":
					yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
						method = "Sandbox-Bubble.kill",
						args = OLLMrpc.args("ix", -this.pid, session_id)
					});
					return "command has ended";
				case "tail":
					var tail = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
						method = "Sandbox-Bubble.tail",
						args = OLLMrpc.args("ix", -this.pid, session_id)
					});
					if (tail.msg == "command has ended") {
						return "command has ended";
					}
					return tail.msg + "\n" + this.pid_block(this.pid, false);
				case "wait":
					var waited = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
						method = "Sandbox-Bubble.wait",
						args = OLLMrpc.args(
							"iix",
							-this.pid,
							this.timeout.clamp(60, int.MAX),
							session_id
						)
					});
					if ((int) waited.retval.get_int() >= 0) {
						return this.bash_finished_text(waited.msg);
					}
					return waited.msg + "\n" + this.pid_block(this.pid, false);
				case "send":
					if ((yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
						method = "Sandbox-Bubble.send",
						args = OLLMrpc.args(
							"isx",
							-this.pid,
							payload,
							session_id
						)
					})).msg == "ok") {
						return "ok";
					}
					return "command has ended";
				default:
					return "ERROR: Unknown command for pid " + this.pid.to_string();
			}
		}

		/**
		 * Pid return the agent reads. Waiting-for-input includes the 60 second reap line.
		 *
		 * @param pid bwrap pid
		 * @param waiting true when the job is blocked on stdin
		 * @return the block
		 */
		private string pid_block(int pid, bool waiting)
		{
			var head = waiting ? "Waiting for input" : "Still running";
			var reap = waiting ? "Left alone, it is killed in about 60 seconds.\n" : "";
			return @"$(head). pid $(pid).

Call this tool again with pid=$(pid) and command set to one of:
  send <text>  write to its stdin
  wait         wait 60 more seconds for it
  tail         show the last 50 lines of its output
  kill         stop it
$(reap)";
		}

		/**
		 * Connect ''output'' and ''finished'' once, and route them by lease.
		 *
		 * @param project_manager file daemon client
		 * @param lease bubble lease from ''rpc_create''
		 */
		private void arm_bash_listener(OLLMfiles.ProjectManager project_manager, uint64 lease)
		{
			if (Request.bash_lease == null) {
				Request.bash_lease = new Gee.HashMap<int, Request>();
			}
			Request.bash_lease.set((int) lease, this);
			if (Request.bash_listening) {
				return;
			}
			Request.bash_listening = true;
			project_manager.rpc.notification.connect((notif) => {
				if (notif.method != "output" && notif.method != "finished") {
					return;
				}
				if (!Request.bash_lease.has_key(notif.id)) {
					return;
				}
				var req = Request.bash_lease.get(notif.id);
				if (notif.method == "finished") {
					Request.bash_lease.unset(notif.id);
					if (!req.detached) {
						return;
					}
					if (req.pending_output_src != 0) {
						GLib.Source.remove(req.pending_output_src);
						req.pending_output_src = 0;
					}
					if (req.pending_output.length > 0) {
						req.agent.notification(new OLLMrpc.Notification() {
							method = "client.run_tool.output",
							message = string.joinv("\n", req.pending_output) + "\n",
							id = req.request_id,
						});
						req.pending_output = {};
					}
					if (req.spill_active) {
						try {
							req.spill_stream.close(null);
						} catch (GLib.Error e) {
						}
						req.spill_active = false;
						if (req.output_lines <= 50) {
							try {
								GLib.File.new_for_path(req.spill_path).delete(null);
							} catch (GLib.Error e) {
							}
							try {
								GLib.File.new_for_path(GLib.Path.get_dirname(req.spill_path)).delete(null);
							} catch (GLib.Error e) {
							}
						}
					}
					req.agent.notification(new OLLMrpc.Notification() {
						method = "client.run_tool.end",
						message = req.command.strip(),
					});
					return;
				}
				if (notif.args.size < 1 || notif.args.get(0) == null) {
					return;
				}
				var line = notif.args.get(0).get_string();
				req.pending_output += line;
				req.output_lines++;
				if (req.spill_active) {
					try {
						req.spill_stream.write_all((line + "\n").data, null);
					} catch (GLib.Error e) {
						req.spill_active = false;
					}
				}
				if (req.pending_output_src != 0) {
					return;
				}
				req.pending_output_src = GLib.Timeout.add(500, () => {
					req.agent.notification(new OLLMrpc.Notification() {
						method = "client.run_tool.output",
						message = string.joinv("\n", req.pending_output) + "\n",
						id = req.request_id,
					});
					req.pending_output = {};
					req.pending_output_src = 0;
					return false;
				});
			});
		}

		/**
		 * Command result, plus the spill footer when more than 50 lines arrived.
		 *
		 * @param msg last lines, or ''command has ended''
		 * @return text the agent reads
		 */
		private string bash_finished_text(string msg)
		{
			if (this.output_lines <= 50) {
				return msg;
			}
			return msg + @"

**Below are the last 50 of $(this.output_lines) lines.**
Full output: $(this.spill_path)
Do not read this file whole — it is $(this.output_lines) lines. Use grep, head, or tail on it with this tool to find the part you need.
";
		}


		/**
		 * Required by base class, but we handle everything in execute().
		 */
		protected override async string execute_request() throws Error
		{
			// This should never be called since we override execute()
			throw new GLib.IOError.NOT_SUPPORTED("execute_request() should not be called");
		}
	}
}
