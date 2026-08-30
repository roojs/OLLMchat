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

namespace OLLMtools.RunCommand
{
	/**
	 * Request handler for executing terminal commands in the project root directory.
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

		/** Validated allow_write tokens; populated only in {@link execute} before permission. */
		private string[] write_array = {};
		
		/** When true, {@link execute} appends a unique suffix to {@link permission_target_path} so each prompt is distinct (used for non-bwrap runs). */
		private bool is_complex_command = false;
		private int output_lines = 0;
		private bool stopped = false;
		private bool timed_out = false;
		private uint timeout_src = 0;
		private string[] tail = {};
		private string[] pending_output = {};
		private uint pending_output_src = 0;
		private GLib.FileOutputStream spill_stream;
		private bool spill_active = false;
		private string spill_path = "";
		private GLib.Subprocess child;
		private bool child_active = false;
		private OLLMbwrap.Bubble bubble;
		private bool bubble_active = false;
			
		/**
		 * Default constructor.
		 */
		public Request()
		{
		}

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
			if (OLLMbwrap.Bubble.can_wrap ()) {
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

			bool can = OLLMbwrap.Bubble.can_wrap ();
			string head0 = this.write_array.length > 0 ? this.write_array[0].down () : "";
			bool default_sandbox_writes = (head0 == "no" || head0 == "project");

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
			// Parameters are already deserialized in constructor
			if (this.command.strip() == "") {
				return "ERROR: Invalid parameters";
			}
			
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
			}

#if G_OS_WIN32
			if (this.run_as_root) {
				return "ERROR: run_as_root is not supported on Windows";
			}
#else
			if (this.run_as_root && GLib.Environment.find_program_in_path ("sudo") == null) {
				return "ERROR: run_as_root requires sudo, which was not found on PATH";
			}
#endif

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

			bool need_perm = this.build_perm_question ();
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
			if (this.run_as_root) {
				run_status = "Running command as root (sudo)";
			}
			if (!this.run_as_root && OLLMbwrap.Bubble.can_wrap()) {
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
			this.timeout_src = GLib.Timeout.add_seconds(this.timeout, () => {
				this.timed_out = true;
				this.stop();
				this.timeout_src = 0;
				return false;
			});
			try {
				return yield this.execute_tool_async();
			} catch (Error e) {
				return "ERROR: " + e.message;
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
				if (this.spill_active) {
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
				this.agent.notification(new OLLMrpc.Notification() {
					method = "client.run_tool.end",
					message = this.command.strip(),
				});
			}
		}
		
		/**
		 * Async method to execute the command with non-blocking I/O.
		 * 
		 * Checks if bubblewrap can be used (via Bubble.can_wrap() static method).
		 * If bubblewrap is available and not running in Flatpak, uses Bubble.exec().
		 * Otherwise, falls back to regular GLib.Subprocess execution.
		 */
		private async string execute_tool_async() throws Error
		{
			if (this.command == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("Command cannot be empty");
			}
			
			var normalized_working_dir = this.normalize_working_dir();

			if (this.run_as_root) {
				return yield this.execute_with_subprocess ();
			}

			if (!OLLMbwrap.Bubble.can_wrap()) {
				return yield this.execute_with_subprocess();
			}

			var run_command_tool = (Tool) this.tool;
			var project_manager = run_command_tool.project_manager;
			var project = (project_manager != null && project_manager.active_project != null)
				? project_manager.active_project
				: (OLLMfiles.Folder?) null;

			try {
				var project_path = "";
				var write_roots = new Gee.HashMap<string, string>();
				if (project != null) {
					project_path = project.path;
					write_roots.set(project.path, project.path);
				}

				var verification = new OLLMtools.FileVerification(
					project,
					project_manager
				);
				// due to vala async ctor quirk
				var bubble = new OLLMbwrap.Bubble(verification);
				bubble.project_path = project_path;
				bubble.allow_network = this.network;
				bubble.write_tokens = this.write_array;
				bubble.write_roots = write_roots;
				this.bubble = bubble;
				this.bubble_active = true;
				bubble.output.connect((line) => {
					this.pending_output += line;
					this.output_lines++;
					if (this.spill_active) {
						try {
							this.spill_stream.write_all((line + "\n").data, null);
						} catch (GLib.Error e) {
							this.spill_active = false;
						}
					}
					if (this.pending_output_src != 0) {
						return;
					}
					this.pending_output_src = GLib.Timeout.add(500, () => {
						this.agent.notification(new OLLMrpc.Notification() {
							method = "client.run_tool.output",
							message = string.joinv("\n", this.pending_output) + "\n",
							id = this.request_id,
						});
						this.pending_output = {};
						this.pending_output_src = 0;
						return false;
					});
				});

				var output = yield bubble.exec(
					this.command,
					normalized_working_dir
				);
				this.bubble_active = false;
				if (output.strip() == "") {
					output = "No output received from command";
				}
				if (this.timed_out) {
					output = output.replace("\nCommand stopped by user.", "");
					output += "\nCommand timed out after " + this.timeout.to_string()
						+ "s. Raise timeout in run_command if this was expected to run longer.";
				}

				var footer = "";
				if (this.output_lines > 50) {
					footer += "// LLM received last 50 of " + this.output_lines.to_string() + " lines.\n";
					if (this.spill_path != "") {
						footer += "Full output: " + this.spill_path + "\n";
					}
				}
				if (this.timed_out) {
					footer += "Command timed out after " + this.timeout.to_string()
						+ "s. Raise timeout in run_command if this was expected to run longer.\n";
				}
				if (this.stopped && !this.timed_out) {
					footer += "Command stopped by user.\n";
				}
				var exit_at = output.index_of("Exit code:");
				if (!this.stopped && exit_at >= 0) {
					footer += output.substring(exit_at);
				}
				if (this.spill_path != "" && this.output_lines > 50) {
					output = output + "\nFull output: " + this.spill_path + "\n";
				}
				if (footer != "") {
					this.agent.notification(new OLLMrpc.Notification() {
						method = "client.run_tool.output",
						message = footer,
						id = this.request_id,
					});
				}
				return output;
				
			} catch (Error e) {
				// Cleanup is handled inside bubble.exec() finally block, so we just re-throw
				throw e;
			}
		}
		
		/**
		 * Execute command using regular GLib.Subprocess (fallback for Flatpak or when bwrap is unavailable).
		 * 
		 * This is the original implementation that uses GLib.Subprocess directly.
		 * Used when bubblewrap is not available or when running inside Flatpak.
		 */
		private async string execute_with_subprocess() throws Error
		{
			// Get working directory - use normalized working_dir if provided, otherwise fall back to tool's base_directory
			var normalized_working_dir = this.normalize_working_dir();
			var run_command_tool = (Tool) this.tool;
			var work_dir = (normalized_working_dir != "") ? normalized_working_dir : run_command_tool.base_directory;
			
			// When not using bwrap, $HOME/playground may not exist; use the real playground path
			var home_playground = GLib.Path.build_filename(GLib.Environment.get_home_dir(), "playground");
			if (work_dir == home_playground) {
				work_dir = GLib.Path.build_filename(GLib.Environment.get_home_dir(), ".local", "share", "ollmchat", "playground");
				var pf = GLib.File.new_for_path(work_dir);
				if (!GLib.FileUtils.test(pf.get_path(), GLib.FileTest.EXISTS)) {
					pf.make_directory_with_parents(null);
				}
			}
			
			// Validate directory exists (should already be validated in execute(), but double-check for safety)
			var dir_file = GLib.File.new_for_path(work_dir);
			if (!GLib.FileUtils.test(dir_file.get_path(), GLib.FileTest.EXISTS)) {
				throw new GLib.IOError.NOT_FOUND("Working directory does not exist: " + work_dir);
			}
			
			string[] argv;
#if G_OS_WIN32
			var shell = GLib.Environment.get_variable ("COMSPEC");
			if (shell == null || shell.strip () == "") {
				shell = "cmd.exe";
			}
			argv = { shell, "/c", this.command };
#else
			if (this.run_as_root) {
				var shell_inner = this.command;
				if (work_dir != "") {
					shell_inner = "cd " + GLib.Shell.quote (work_dir) + " && " + shell_inner;
				}
				argv = {
					"sudo",
					"-S",
					"/bin/sh",
					"-c",
					shell_inner
				};
			} else {
				argv = { "/bin/sh", "-c", this.command };
			}
#endif

			string stdout_output;
			string stderr_output;
			int exit_status = 0;

#if G_OS_WIN32
			GLib.Subprocess subprocess;
			try {
				var launcher = new GLib.SubprocessLauncher (
					GLib.SubprocessFlags.STDOUT_PIPE |
					GLib.SubprocessFlags.STDERR_PIPE |
					GLib.SubprocessFlags.STDIN_PIPE
				);
				launcher.set_cwd (work_dir);
				subprocess = launcher.spawnv (argv);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to create subprocess: " + e.message);
			}

			this.child = subprocess;
			this.child_active = true;

			// Win32 pipe reads via read_line_async can hang; STDIN_INHERIT can block cmd.exe.
			string? stdout_buf = null;
			string? stderr_buf = null;
			bool success = false;
			try {
				success = yield subprocess.communicate_utf8_async (null, null, out stdout_buf, out stderr_buf);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to run command: " + e.message);
			}
			stdout_output = stdout_buf ?? "";
			stderr_output = stderr_buf ?? "";
			if (this.spill_active) {
				try {
					this.spill_stream.write_all((stdout_output + stderr_output).data, null);
				} catch (GLib.Error e) {
					this.spill_active = false;
				}
			}
			this.output_lines = (stdout_output + "\n" + stderr_output).split("\n").length;
			stdout_output = this.truncate_output(stdout_output, 50);
			exit_status = success ? 0 : subprocess.get_exit_status ();
#else
			if (this.run_as_root) {
				var klauncher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.NONE);
				var kproc = klauncher.spawnv ({"sudo", "-k"});
				kproc.wait (null);
			}

			GLib.Subprocess subprocess;
			try {
				var flags = GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE;
				if (this.run_as_root) {
					flags |= GLib.SubprocessFlags.STDIN_PIPE;
				} else {
					flags |= GLib.SubprocessFlags.STDIN_INHERIT;
				}
				var launcher = new GLib.SubprocessLauncher (flags);
				if (!this.run_as_root) {
					launcher.set_cwd (work_dir);
				}
				launcher.set_child_setup(() => {
					Posix.setpgid(0, 0);
				});
				subprocess = launcher.spawnv (argv);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to create subprocess: " + e.message);
			}

			this.child = subprocess;
			this.child_active = true;

			if (this.run_as_root) {
				var stdin_stream = subprocess.get_stdin_pipe ();
				stdin_stream.write_all ((this.elevation_password + "\n").data, null);
				stdin_stream.close (null);
				this.elevation_password = "";
			}

			var stdout_stream = subprocess.get_stdout_pipe ();
			var stderr_stream = subprocess.get_stderr_pipe ();
			yield this.read_stream_async (stdout_stream, subprocess);
			stdout_output = yield this.read_stream_async (stderr_stream, subprocess);
			stderr_output = "";

			try {
				if (!(yield subprocess.wait_async (null))) {
					exit_status = subprocess.get_exit_status ();
				}
			} catch (GLib.Error e) {
				if (!subprocess.get_successful ()) {
					exit_status = subprocess.get_exit_status ();
				}
				throw new GLib.IOError.FAILED("Failed to wait for process: " + e.message);
			}
#endif

			this.child_active = false;
			
			var	output_content  = stdout_output;
			if (stderr_output != "") {
				if (stdout_output != "") {
					output_content += "\n";
				}
				output_content += stderr_output;
			}
			if (this.timed_out) {
				output_content += "\nCommand timed out after " + this.timeout.to_string()
					+ "s. Raise timeout in run_command if this was expected to run longer.";
			}
			if (this.stopped && !this.timed_out) {
				output_content += "\nCommand stopped by user.";
			}
			if (!this.stopped && exit_status != 0) {
				if (stdout_output != "" || stderr_output != "") {
					output_content += "\n";
				}
				output_content += "Exit code: " + exit_status.to_string();
				if (!this.network) {
					output_content += " - Note: Networking is disabled by default. Pass \"network\": true in the "
						+ this.tool.name + " arguments to enable it.";
				}
				output_content += "\n";
			}
			if (output_content.strip() == "") {
				output_content = "No output received from command";
			}

			if (this.spill_path != "" && this.output_lines > 50) {
				output_content = output_content + "\nFull output: " + this.spill_path + "\n";
			}
#if G_OS_WIN32
			this.agent.notification(new OLLMrpc.Notification() {
				method = "client.run_tool.output",
				message = output_content + "\n",
				id = this.request_id,
			});
#else
			var footer = "";
			if (this.output_lines > 50) {
				footer += "// LLM received last 50 of " + this.output_lines.to_string() + " lines.\n";
				if (this.spill_path != "") {
					footer += "Full output: " + this.spill_path + "\n";
				}
			}
			if (this.timed_out) {
				footer += "Command timed out after " + this.timeout.to_string()
					+ "s. Raise timeout in run_command if this was expected to run longer.\n";
			}
			if (this.stopped && !this.timed_out) {
				footer += "Command stopped by user.\n";
			}
			if (!this.stopped && exit_status != 0) {
				footer += "Exit code: " + exit_status.to_string();
				if (!this.network) {
					footer += " - Note: Networking is disabled by default. Pass \"network\": true in the "
						+ this.tool.name + " arguments to enable it.";
				}
				footer += "\n";
			}
			if (footer != "") {
				this.agent.notification(new OLLMrpc.Notification() {
					method = "client.run_tool.output",
					message = footer,
					id = this.request_id,
				});
			}
#endif
			return output_content;
		}
		
		/**
		 * Truncates output to a maximum number of lines, adding a truncation message.
		 * 
		 * @param output The output string to truncate
		 * @param max_lines Maximum number of lines to keep (default: 50)
		 * @return Truncated output with truncation message if needed
		 */
		private string truncate_output(string output, int max_lines = 50)
		{
			if (output == "") {
				return output;
			}
			
			var lines = output.split("\n");
			var total_lines = lines.length;
			
			if (total_lines <= max_lines) {
				return output;
			}
			
			var start = total_lines - max_lines;
			var truncated_lines = lines[start:total_lines];
			var truncated = string.joinv("\n", truncated_lines);
			return "// ... (output truncated: showing last " + max_lines.to_string() + " of " + total_lines.to_string() + " lines) ...\n" + truncated;
		}

#if !G_OS_WIN32
		/**
		 * Async method to read from a stream and accumulate output.
		 */
		private async string read_stream_async (InputStream? stream, GLib.Subprocess subprocess)
		{
			if (stream == null) {
				return "";
			}

			var data_input = new GLib.DataInputStream (stream);
			while (true) {
				if (this.stopped) {
					break;
				}
				string? line = null;
				try {
					line = yield data_input.read_line_async (GLib.Priority.DEFAULT, null);
				} catch (GLib.Error e) {
					return string.joinv("\n", this.tail);
				}
				if (line == null) {
					break;
				}
				if (this.tail.length >= 50) {
					this.tail = this.tail[1:this.tail.length];
				}
				this.tail += line;
				this.output_lines++;
				this.pending_output += line;
				if (this.spill_active) {
					try {
						this.spill_stream.write_all((line + "\n").data, null);
					} catch (GLib.Error e) {
						this.spill_active = false;
					}
				}
				if (this.pending_output_src != 0) {
					continue;
				}
				this.pending_output_src = GLib.Timeout.add(500, () => {
					this.agent.notification(new OLLMrpc.Notification() {
						method = "client.run_tool.output",
						message = string.joinv("\n", this.pending_output) + "\n",
						id = this.request_id,
					});
					this.pending_output = {};
					this.pending_output_src = 0;
					return false;
				});
			}
			var output = string.joinv("\n", this.tail);
			if (this.output_lines <= 50) {
				return output;
			}
			return "// ... (output truncated: showing last 50 of " + this.output_lines.to_string() + " lines) ...\n" + output;
		}
#endif
		
		// FUTURE: Streaming support - uncomment these methods and fields to enable real-time output
		// private OLLMchat.Message? current_tool_message = null;
		// 
		// /**
		//  * Sends the initial tool message with opening code blocks for streaming.
		//  * 
		//  * @param content The message content
		//  */
		// protected virtual void send_initial_tool_message(string content)
		// {
		//     // Create initial message with opening code blocks
		//     var initial_content = new StringBuilder();
		//     initial_content.append("```bash\n");
		//     initial_content.append("$ ").append(this.command).append("\n");
		//     initial_content.append("```\n\n");
		//     initial_content.append("```txt\n");
		//     
		//     this.current_tool_message = new OLLMchat.Message(this.chat_call, "ui", initial_content.str);
		//     this.chat_call.client.tool_message(this.current_tool_message);
		// }
		// 
		// /**
		//  * Appends a line to the streaming tool message.
		//  * 
		//  * @param text The text to append
		//  */
		// protected virtual void send_or_append_message(string text)
		// {
		//     if (this.current_tool_message != null) {
		//         this.current_tool_message.content += text + "\n";
		//         this.chat_call.client.tool_message(this.current_tool_message);
		//     }
		// }
		
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
