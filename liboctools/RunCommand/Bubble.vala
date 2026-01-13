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

namespace OLLMtools.RunCommand
{
	/**
	 * Bubble class for executing commands in bubblewrap sandbox.
	 * 
	 * A new Bubble instance is created for each command execution. The instance is used
	 * once and then goes out of scope, so no cleanup logic is needed for old instances.
	 */
	public class Bubble
	{
		// Properties
		private OLLMfiles.Folder project;           // Project folder (is_project = true)
		private Gee.HashMap<string, OLLMfiles.Folder> roots;  // Map of path -> Folder objects to share (read-write access)
		private bool allow_network;                 // Network access flag (default: false)
		
		/**
		 * Constructor.
		 * 
		 * @param project Project folder object (is_project = true) - the main project directory
		 * @param allow_network Whether to allow network access (default: false, Phase 7 feature)
		 * @throws Error if project is invalid or build_roots() fails
		 */
		public Bubble(OLLMfiles.Folder project, bool allow_network = false) throws Error
		{
			// Store parameters as instance variables
			this.project = project;
			this.allow_network = allow_network;
			
			// Initialize roots as empty HashMap
			this.roots = new Gee.HashMap<string, OLLMfiles.Folder>();
			
			// Call project.build_roots() to get array of paths that need write access
			var root_folders = project.build_roots();
			
			// For each path returned:
			foreach (var folder in root_folders) {
				// Validate path exists and is absolute
				if (!GLib.Path.is_absolute(folder.path)) {
					throw new GLib.IOError.INVALID_ARGUMENT("Path is not absolute: " + folder.path);
				}
				
				// Add to HashMap: roots.set(path, project) (use project as the Folder reference)
				this.roots.set(folder.path, project);
			}
		}
		
		/**
		 * Execute command string in bubblewrap sandbox and return output as string.
		 * 
		 * @param command Command string to execute (e.g., "ls -la" or "cd /path && make")
		 * @return String containing command output (stdout + stderr, with exit code if non-zero)
		 * @throws Error if command execution fails
		 */
		public async string exec(string command) throws Error
		{
			// Build bubblewrap command arguments using build_bubble_args(command)
			var args = this.build_bubble_args(command);
			
			// Create GLib.Subprocess with bubblewrap as executable
			GLib.Subprocess subprocess;
			try {
				subprocess = new GLib.Subprocess.newv(
					args,
					GLib.SubprocessFlags.STDOUT_PIPE | 
					GLib.SubprocessFlags.STDERR_PIPE |
					GLib.SubprocessFlags.STDIN_INHERIT
				);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to create bubblewrap subprocess: " + e.message);
			}
			
			// Read output using read_subprocess_output()
			var output = yield this.read_subprocess_output(subprocess);
			
			// Return formatted string
			return output;
		}
		
		/**
		 * Build complete bubblewrap command line arguments.
		 * 
		 * @param command Command string to execute
		 * @return Array of arguments for bubblewrap command (including /bin/sh -c "command")
		 * @throws Error if argument building fails
		 */
		private string[] build_bubble_args(string command) throws Error
		{
			// Start with array: ["bwrap"]
			var args = new Gee.ArrayList<string>();
			args.add("bwrap");
			
			// Add read-only bind: "--ro-bind", "/", "/"
			args.add("--ro-bind");
			args.add("/");
			args.add("/");
			
			// Add root folder binds: Iterate over roots HashMap, for each path add "--bind", path, path
			foreach (var entry in this.roots.entries) {
				args.add("--bind");
				args.add(entry.key);
				args.add(entry.key);
			}
			
			// Add network args: If allow_network == false, add "--unshare-net"
			if (!this.allow_network) {
				args.add("--unshare-net");
			}
			
			// Add separator: "--"
			args.add("--");
			
			// Add shell command: "/bin/sh", "-c", command
			args.add("/bin/sh");
			args.add("-c");
			args.add(command);
			
			// Return final array
			return args.to_array();
		}
		
		/**
		 * Read stdout and stderr from subprocess and return combined output.
		 * 
		 * @param subprocess The Subprocess instance to read from
		 * @return Combined stdout + stderr output as string
		 * @throws Error if reading fails
		 */
		private async string read_subprocess_output(GLib.Subprocess subprocess) throws Error
		{
			// Get stdout and stderr streams from subprocess
			var stdout_stream = subprocess.get_stdout_pipe();
			var stderr_stream = subprocess.get_stderr_pipe();
			
			// Read from both streams concurrently (async)
			var stdout_output = yield this.read_stream_async(stdout_stream);
			var stderr_output = yield this.read_stream_async(stderr_stream);
			
			// Wait for process to complete
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
			
			// Combine outputs (stdout first, then stderr if present)
			var output_content = stdout_output;
			
			// Add stderr output (if any)
			if (stderr_output != "") {
				if (stdout_output != "") {
					output_content += "\n";
				}
				output_content += stderr_output;
			}
			
			// Append exit code to output if non-zero
			if (exit_status != 0) {
				if (stdout_output != "" || stderr_output != "") {
					output_content += "\n";
				}
				output_content += "Exit code: " + exit_status.to_string() + "\n";
			}
			
			// Return formatted string
			return output_content;
		}
		
		/**
		 * Async method to read from a stream and accumulate output.
		 * 
		 * @param stream The input stream to read from
		 * @return Accumulated output as string
		 */
		private async string read_stream_async(GLib.InputStream? stream)
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
				}
			} catch (GLib.Error e) {
				// Stream closed or error - return what we have
				return output;
			}
			
			return output;
		}
	}
}

