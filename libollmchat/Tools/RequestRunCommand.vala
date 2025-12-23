/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
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

namespace OLLMchat.Tools
{
	/**
	 * Request handler for executing terminal commands in the project root directory.
	 */
	public class RequestRunCommand : OLLMchat.Tool.RequestBase
	{
		// Parameter properties
		public string command { get; set; default = ""; }
		
		// Flag to track if this is a complex command (needs to bypass cache)
		private bool is_complex_command = false;
		
		/**
		 * Default constructor.
		 */
		public RequestRunCommand()
		{
		}
		
		/**
		 * Detects bash operators in a command string.
		 * 
		 * @param cmd The command string to check
		 * @return true if bash operators are detected
		 */
		private bool has_bash_operators(string cmd)
		{
			// Check for common bash operators/separators
			// Note: We need to be careful not to match these inside quotes
			// For simplicity, we'll do a basic check - this could be improved
			// | catches both | and ||
			// > catches both > and >>
			// < catches both < and <<
			// & catches &, &&, and 2>&1 (but we exclude cd commands)
			if (cmd.contains("|") || 
			    cmd.contains(">") || 
			    cmd.contains("<") || 
			    cmd.contains(";") || 
			    (cmd.contains("&") && !cmd.has_prefix("cd "))) {
				return true;
			}
			return false;
		}
		
		/**
		 * Detects if command matches simple pattern for permission caching.
		 * 
		 * @param cmd The command to check
		 * @return true if it's a simple pattern
		 */
		private bool is_simple_pattern(string cmd)
		{
			// Check for bash operators first - if present, it's complex
			if (this.has_bash_operators(cmd)) {
				return false;
			}
			
			var parts = cmd.split(" && ");
			
			// Single command (no &&)
			if (parts.length == 1) {
				return true;
			}
			
			// Pattern: cd <path> && <command>
			if (parts.length != 2) {
				return false;
			}
			
			var first = parts[0].strip();
			
			// First part must start with "cd "
			if (!first.has_prefix("cd ")) {
				return false;
			}
			
			return true;
		}
		
		/**
		 * Extracts the executable command from a simple pattern.
		 * 
		 * @param cmd The full command
		 * @return The command part to resolve (without cd if present)
		 */
		private string extract_command_for_resolution(string cmd)
		{
			var parts = cmd.split("&&");
			
			if (parts.length == 1) {
				return parts[0].strip();
			}
			
			if (parts.length == 2) {
				// Return the part after &&
				return parts[1].strip();
			}
			
			return cmd;
		}
		
		/**
		 * Extracts the executable name from a command string.
		 * 
		 * @param cmd The command string
		 * @return The executable name (first word)
		 */
		private string extract_executable_name(string cmd)
		{
			var trimmed = cmd.strip();
			if (trimmed == "") {
				return "";
			}
			
			// Find first space or end of string
			int space_pos = trimmed.index_of(" ");
			if (space_pos == -1) {
				return trimmed;
			}
			
			return trimmed.substring(0, space_pos);
		}
		
		protected override bool build_perm_question()
		{
			// Validate required parameter
			if (this.command == "") {
				return false;
			}
			
			// Check if this is a complex pattern
			if (!this.is_simple_pattern(this.command)) {
				// Complex pattern: always require approval
				this.is_complex_command = true;
				this.permission_target_path = this.command;
				this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
				this.permission_question = "Run command: " + this.command + "?";
				return true;
			}
			
			// Simple pattern: extract command and resolve realpath
			var cmd_to_resolve = this.extract_command_for_resolution(this.command);
			var exec_name = this.extract_executable_name(cmd_to_resolve);
			
			if (exec_name == "") {
				// Can't resolve - treat as complex
				this.is_complex_command = true;
				this.permission_target_path = this.command;
				this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
				this.permission_question = "Run command: " + this.command + "?";
				return true;
			}
			
			var realpath = GLib.Environment.find_program_in_path(exec_name) ?? "";
			if (realpath == "") {
				// Can't resolve - treat as complex
				this.is_complex_command = true;
				this.permission_target_path = this.command;
				this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
				this.permission_question = "Run command: " + this.command + "?";
				return true;
			}
			
			// Simple pattern with resolved path
			this.is_complex_command = false;
			this.permission_target_path = realpath;
			this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
			this.permission_question = "Run command: " + this.command + "?";
			return true;
		}
		
		/**
		 * Override execute() to handle complex commands differently and execute async subprocess.
		 * For complex commands, we use a unique path that won't match cache entries,
		 * effectively forcing a new permission request each time.
		 */
		public override async string execute()
		{
			// Parameters are already deserialized in constructor
			// Build permission question
			if (!this.build_perm_question()) {
				return "ERROR: Invalid parameters";
			}
			
			// For complex commands, use a unique identifier to bypass cache
			if (this.is_complex_command) {
				// Add a timestamp to make the path unique (won't match cache)
				var unique_path = this.permission_target_path + "#" + GLib.get_real_time().to_string();
				this.permission_target_path = unique_path;
			}
			
			// Request permission (will always ask for complex commands due to unique path)
			if (!(yield this.chat_call.client.permission_provider.request(this))) {
				return "ERROR: Permission denied: " + this.permission_question;
			}
			
			// Execute the tool async
			try {
				return yield this.execute_tool_async();
			} catch (Error e) {
				return "ERROR: " + e.message;
			}
		}
		
		/**
		 * Async method to execute the command with non-blocking I/O.
		 */
		private async string execute_tool_async() throws Error
		{
			if (this.command == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("Command cannot be empty");
			}
			
			// Get working directory from tool's base_directory
			var run_command_tool = (OLLMchat.Tools.RunCommand) this.tool;
			var work_dir = run_command_tool.base_directory;
			
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
			
			// Send command start message (GTK version will override to add widget)
			this.send_initial_tool_message("$ " + this.command);
			
			// Read from both streams concurrently using async I/O
			var stdout_stream = subprocess.get_stdout_pipe();
			var stderr_stream = subprocess.get_stderr_pipe();
			
			// Read from both streams concurrently
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
			
			// Append exit code to widget or send as message
			this.send_or_append_message("\nExit code: " + exit_status.to_string());
			
			// Merge outputs: stdout first, then stderr
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
			
			// Return merged raw output to LLM
			return merged_output;
		}
		
		/**
		 * Async method to read from a stream line by line and stream to chat.
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
					
					// Add to output
					if (output != "") {
						output += "\n";
					}
					output += line;
					
					// Append to widget (GTK version) or send as message (base version)
					this.send_or_append_message(line);
				}
			} catch (GLib.Error e) {
				// Stream closed or error - return what we have
				return output;
			}
			
			return output;
		}
		
		/**
		 * Sends the initial tool message with optional widget.
		 * GTK version can override to create GTK Message with widget support.
		 * 
		 * @param content The message content
		 */
		protected virtual void send_initial_tool_message(string content)
		{
			this.chat_call.client.tool_message(
				new OLLMchat.Message(this.chat_call, "ui",
				content)
			);
		}
		
		/**
		 * Sends or appends a message to the output.
		 * Base class sends via tool_message, GTK version appends to widget.
		 * 
		 * @param text The text to send or append
		 */
		protected virtual void send_or_append_message(string text)
		{
			// Base class sends as tool message
			this.chat_call.client.tool_message(
				new OLLMchat.Message(this.chat_call, "ui",
				text)
			);
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
