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
		/** Tool string allow_write: no, project, or colon-separated absolute roots on Unix. Parsed in execute() before permission. */
		public string allow_write { get; set; default = "project"; }

		/** Validated allow_write tokens; populated only in {@link execute} before permission. */
		private string[] write_array = {};
		
		/** When true, {@link execute} appends a unique suffix to {@link permission_target_path} so each prompt is distinct (used for non-bwrap runs). */
		private bool is_complex_command = false;
			
		/**
		 * Default constructor.
		 */
		public Request()
		{
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
			if (Bubble.can_wrap ()) {
				return "";
			}
			if (GLib.Environment.get_variable ("FLATPAK_ID") != null) {
				return " (Flatpak: bubblewrap is not used here.)";
			}
			return " (Install bubblewrap or add bwrap to PATH to enable sandboxing.)";
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
		protected override bool build_perm_question()
		{
			string cmd_preview = "";
			if (this.command != "") {
				int nl = this.command.index_of_char ('\n');
				cmd_preview = nl >= 0 ? this.command.substring (0, nl).strip () : this.command.strip ();
			}

			// Handle network requests first - they always require approval (even with bubblewrap)
			if (this.network) {
				this.one_time_only = true;
				// Use unique identifier to bypass cache (timestamp-based)
				this.permission_target_path = "network#" + GLib.get_real_time().to_string();
				this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
				this.permission_question = "Confirm — Network access requested.\n\n"
					+ "Run command with network access: " + cmd_preview + "?"
					+ this.bwrap_unavailable_note ();
				return true;
			}

			bool can = Bubble.can_wrap ();
			string head0 = this.write_array.length > 0 ? this.write_array[0].down () : "";
			bool default_sandbox_writes = (head0 == "no" || head0 == "project");

			if (can && !default_sandbox_writes) {
				this.one_time_only = true;
				this.permission_target_path = "allow_write_paths#" + GLib.get_real_time ().to_string ();
				this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
				this.permission_question = "Confirm — Additional file write access requested.\n\n"
					+ "This request asks for write permission to these folders: "
					+ string.joinv (", ", this.write_array)
					+ ", for this command: " + cmd_preview + "?"
					+ this.bwrap_unavailable_note ();
				return true;
			}

			if (can && default_sandbox_writes) {
				this.permission_question = "";
				this.is_complex_command = false;
				return false;
			}

			// No bubblewrap: approve each run (no bwrap containment)
			this.is_complex_command = true;
			this.one_time_only = true;
			this.permission_target_path = this.command;
			this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
			this.permission_question = "Confirm (sandbox unavailable):\n\nRun command: " + cmd_preview + "?"
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
					if (!dir_file.query_exists()) {
						return "ERROR: Working directory does not exist: " + normalized_working_dir;
					}
					var file_type = dir_file.query_file_type(GLib.FileQueryInfoFlags.NONE, null);
					if (file_type != GLib.FileType.DIRECTORY) {
						return "ERROR: Working directory is not a directory: " + normalized_working_dir;
					}
				}
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
			
			this.agent.add_message (new OLLMchat.Message ("ui",
				OLLMchat.Message.fenced ("text.oc-frame-info.collapsed Running command in sandbox",
					"$ " + this.command)));
			
			// Execute the tool async
			try {
				return yield this.execute_tool_async();
			} catch (Error e) {
				return "ERROR: " + e.message;
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

			if (!Bubble.can_wrap()) {
				return yield this.execute_with_subprocess();
			}

			var run_command_tool = (Tool) this.tool;
			var project_manager = run_command_tool.project_manager;
			var project = (project_manager != null && project_manager.active_project != null)
				? project_manager.active_project
				: (OLLMfiles.Folder?) null;

			Bubble? bubble = null;
			try {
				bubble = new Bubble (project, this.network, this.write_array);
				
				// Execute command in bwrap sandbox (writes go to overlay upper directory)
				// exec() handles overlay creation, mounting, file copying, and cleanup internally
				var output = yield bubble.exec(this.command, normalized_working_dir);
				
				// Truncate output if needed
				// FIXME - not sure this is a great idea - we will be bumping the context up soon
				// with ollama create tricks
				output = this.truncate_output(output, 100);
				if (output.strip() == "") {
					output = "No output received from command";
				}
				
				// Send output as second message via message_created
				this.agent.add_message(new OLLMchat.Message("ui",
					 OLLMchat.Message.fenced("text.oc-frame-success.collapsed Execution results", output)));
				
				// Return output to LLM
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
				if (!pf.query_exists()) {
					pf.make_directory_with_parents(null);
				}
			}
			
			// Validate directory exists (should already be validated in execute(), but double-check for safety)
			var dir_file = GLib.File.new_for_path(work_dir);
			if (!dir_file.query_exists()) {
				throw new GLib.IOError.NOT_FOUND("Working directory does not exist: " + work_dir);
			}
			
			// Execute command using shell with working directory
			// Build command with cd if needed
			string shell_cmd = this.command;
			if (!this.command.has_prefix("cd ")) {
				// Prepend cd to command to set working directory
				shell_cmd = "cd " + GLib.Shell.quote(work_dir) + " && " + this.command;
			}
			
			string[] argv = { "/bin/sh", "-c", shell_cmd };
			
			GLib.Subprocess subprocess;
			try {
				subprocess = new GLib.Subprocess.newv(
					argv,
					GLib.SubprocessFlags.STDOUT_PIPE | 
					GLib.SubprocessFlags.STDERR_PIPE |
					GLib.SubprocessFlags.STDIN_INHERIT
				);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to create subprocess: " + e.message);
			}
			
			// Read from both streams concurrently using async I/O
			var stdout_stream = subprocess.get_stdout_pipe();
			var stderr_stream = subprocess.get_stderr_pipe();
			
			// Read from both streams concurrently (accumulate output)
			var stdout_output = yield this.read_stream_async(stdout_stream);
			var stderr_output = yield this.read_stream_async(stderr_stream);
			
			// Wait for process to complete (async)
			int exit_status = 0;
			try {
				if (!(yield subprocess.wait_async(null))) {
					exit_status = subprocess.get_exit_status();
				}
			} catch (GLib.Error e) {
				if (!subprocess.get_successful()) {
					exit_status = subprocess.get_exit_status();
				}
				throw new GLib.IOError.FAILED("Failed to wait for process: " + e.message);
			}
			
			// Truncate outputs if they exceed max lines (50)
			stdout_output = this.truncate_output(stdout_output, 50);
			//stderr_output = this.truncate_output(stderr_output, 50);
			
			// Escape code blocks in stdout output
 			
			// Build output message (txt code block)
			
			var	output_content  = stdout_output;
			 
			// Add stderr output (if any)
			if (stderr_output != "") {
				if (stdout_output != "") {
					output_content += "\n";
				}
				output_content += stderr_output;
			}
			 
			// Add exit code only if non-zero (success doesn't need to be shown)
			if (exit_status != 0) {
				if (stdout_output != "" || stderr_output != "") {
					output_content += "\n";
				}
				output_content += "Exit code: " + exit_status.to_string();
				if (!this.network) {
					output_content += " - Note: Networking is disabled by default. Pass \"network\": true in the run_command arguments to enable it.";
				}
				output_content += "\n";
			}
			if (output_content.strip() == "") {
				output_content = "No output received from command";
			}
			 
			
		// Send output as second message (danger when command failed, success when exit 0)
			var frame_header = exit_status != 0
				? "text.oc-frame-danger.collapsed Execution results (Command Failed)"
				: "text.oc-frame-success.collapsed Execution results";
			this.agent.add_message(new OLLMchat.Message("ui", 
				OLLMchat.Message.fenced(frame_header, output_content)));
				
			// FUTURE: Streaming support - clear current message when done
			// this.current_tool_message = null;
			
			// Merge outputs: stdout first, then stderr (for LLM return value)
			// Note: stdout_output and stderr_output are already truncated above
			/*
			string merged_output = "";
			if (stdout_output != "") {
				merged_output = stdout_output;
			}
			if (stderr_output != "") {
				if (merged_output != "") {
					merged_output += "\n";
				}
				merged_output += stderr_output;
			}
			 */
			// Return same merged output as shown in UI (already truncated)
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
			
			// Truncate to max_lines
			var truncated_lines = lines[0:max_lines];
			var truncated = string.joinv("\n", truncated_lines);
			
			// Add truncation message (similar to codesearch tool format)
			return truncated + "\n\n// ... (output truncated: showing first " + max_lines.to_string() + " of " + total_lines.to_string() + " lines, output too long) ...";
		}
		
		/**
		 * Async method to read from a stream and accumulate output.
		 */
		private async string read_stream_async(InputStream? stream)
		{
			if (stream == null) {
				return "";
			}
			
			var data_input = new GLib.DataInputStream(stream);
			string output = "";
			
			try {
				while (true) {
					string? line = yield data_input.read_line_async(GLib.Priority.DEFAULT, null);
					
					if (line == null) {
						break;
					}
					
					// Add to output (accumulate for final message)
					if (output != "") {
						output += "\n";
					}
					output += line;
					
					// FUTURE: Streaming support - uncomment to enable real-time output
					// if (this.current_tool_message != null) {
					//     this.current_tool_message.content += line + "\n";
					//     this.chat_call.client.tool_message(this.current_tool_message);
					// }
				}
			} catch (GLib.Error e) {
				// Stream closed or error - return what we have
				return output;
			}
			
			return output;
		}
		
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
