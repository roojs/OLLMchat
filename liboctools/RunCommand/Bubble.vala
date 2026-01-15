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
	 * This class provides secure command execution using bubblewrap (bwrap) to sandbox
	 * commands. It creates a read-only root filesystem with read-write access only to
	 * specific project directories identified by the project's build_roots() method.
	 * 
	 * The sandbox configuration:
	 * - Mounts the entire filesystem as read-only (--ro-bind / /)
	 * - Provides read-write access to project directories via overlay filesystem
	 * - Blocks network access by default (--unshare-net, unless allow_network is true)
	 * - Executes commands via /bin/sh -c
	 * - Provides isolated temporary directory (/tmp) via tmpfs
	 * 
	 * A new Bubble instance is created for each command execution. The instance is used
	 * once and then goes out of scope, so no cleanup logic is needed for old instances.
	 * 
	 * Environment variables are automatically inherited from the user's environment
	 * when using GLib.Subprocess. No explicit --setenv flags are needed.
	 * 
	 * Overlay filesystem is used for write isolation. All writes to project directories
	 * go to the overlay upper directory and are copied back to the live system after
	 * command execution completes.
	 */
	public class Bubble
	{
		/**
		 * Check if bubblewrap can be used for sandboxing.
		 * 
		 * Returns true only if:
		 * - bubblewrap (bwrap) executable is found in PATH
		 * - Not running inside Flatpak (bubblewrap is disabled in Flatpak)
		 * 
		 * This method should be called before creating a Bubble instance to determine
		 * if bubblewrap sandboxing is available.
		 * 
		 * @return true if bubblewrap can be used, false otherwise
		 */
		public static bool can_wrap()
		{
			// Check if running in Flatpak - bubblewrap is disabled in Flatpak
			if (GLib.Environment.get_variable("FLATPAK_ID") != null) {
				return false;
			}
			
			// Check if bwrap executable exists in PATH
			var bwrap_path = GLib.Environment.find_program_in_path("bwrap");
			if (bwrap_path == null) {
				return false;
			}
			
			return true;
		}
		
		/**
		 * Project folder object (is_project = true) - the main project directory.
		 */
		private OLLMfiles.Folder project;
		
		/**
		 * Overlay instance for write isolation.
		 * 
		 * The overlay filesystem is used for write isolation.
		 * The overlay mount point is bind-mounted into the sandbox instead of
		 * directly binding project roots. All project root binds are replaced with
		 * a single overlay mount point bind.
		 */
		private Overlay overlay;
		
		/**
		 * Network access flag (default: false).
		 * 
		 * When false, network access is blocked using --unshare-net. When true, network
		 * access is allowed (Phase 7 feature).
		 */
		private bool allow_network;
		
		/**
		 * Accumulator for stdout output (for success case).
		 */
		public string ret_str { get; private set; default = ""; }
		
		/**
		 * Accumulator for stderr output (for failure case).
		 */
		public string fail_str { get; private set; default = ""; }
		
		/**
		 * Constructor.
		 * 
		 * Initializes a Bubble instance with the specified project folder and network
		 * access setting. Creates an Overlay instance for write isolation (but doesn't
		 * create/mount it yet - that happens in exec()).
		 * 
		 * @param project Project folder object (is_project = true) - the main project directory
		 * @param allow_network Whether to allow network access (default: false, Phase 7 feature)
		 * @throws Error if project is invalid or overlay creation fails
		 */
		public Bubble(OLLMfiles.Folder project, bool allow_network = false) throws Error
		{
			// Store parameters as instance variables
			this.project = project;
			this.allow_network = allow_network;
			
			// Create overlay instance for write isolation (but don't create/mount yet)
			// Overlay constructor already calls project.build_roots() internally and builds overlay_map
			this.overlay = new Overlay(project);
		}
		
		/**
		 * Execute command string in bubblewrap sandbox and return output as string.
		 * 
		 * This is the main public API for executing commands. It creates and mounts the overlay,
		 * builds the bubblewrap command arguments, creates a subprocess, reads stdout and stderr,
		 * copies files from overlay to live system, and cleans up the overlay.
		 * 
		 * The output includes stdout, stderr (if any), and the exit code (if non-zero).
		 * 
		 * The command is executed via /bin/sh -c, so shell features like pipes, redirects,
		 * and command chaining are supported.
		 * 
		 * @param command Command string to execute (e.g., "ls -la" or "cd /path && make")
		 * @return String containing command output (stdout + stderr, with exit code if non-zero)
		 * @throws Error if command execution fails, subprocess creation fails, or I/O errors occur
		 */
		public async string exec(string command) throws Error
		{
			// Create overlay directory structure (lazy initialization)
			this.overlay.create();
			this.overlay.start_monitor();
			
			try {
				// Build bubblewrap command arguments using build_bubble_args(command)
				var args = this.build_bubble_args(command);
				
				// Debug: Output the exact command being run
				var cmd_str = string.joinv(" ", args);
				GLib.debug("Bubble.exec() running command: %s", cmd_str);
				
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
				
				// Copy files from overlay to live system (stops Monitor, copies files)
				yield this.overlay.copy_files();
				
				// Return formatted string
				return output;
				
			} finally {
				// Always cleanup overlay (removes directories)
				try {
					this.overlay.cleanup();
				} catch (Error cleanup_error) {
					GLib.warning("Failed to cleanup overlay: %s", cleanup_error.message);
				}
			}
		}
		
		/**
		 * Build complete bubblewrap command line arguments.
		 * 
		 * Constructs the full command line for bubblewrap, including:
		 * - Read-only root filesystem bind (--ro-bind / /)
		 * - Read-write binds for overlay mount point at each project root location
		 * - Temporary directory mount (--tmpfs /tmp)
		 * - Network isolation flag (--unshare-net) if network is not allowed
		 * - Command separator (--)
		 * - Shell command (/bin/sh -c "command")
		 * 
		 * The resulting array can be passed directly to GLib.Subprocess.newv().
		 * 
		 * @param command Command string to execute
		 * @return Array of arguments for bubblewrap command (including /bin/sh -c "command")
		 * @throws Error if argument building fails
		 */
		private string[] build_bubble_args(string command) throws Error
		{
			// Find full path to bwrap executable
			var bwrap_path = GLib.Environment.find_program_in_path("bwrap");
			if (bwrap_path == null) {
				throw new GLib.IOError.NOT_FOUND("bubblewrap (bwrap) not found in PATH");
			}
			
			// Start with empty array and use += to build it
			string[] args = {};
			
			// Start with: ["bwrap"]
			args += bwrap_path;
			
			// Add user namespace (required for overlay support without root)
			args += "--unshare-user";
			
			// Add tmpfs mount for /tmp first (needs to be writable before creating directories)
			args += "--tmpfs";
			args += "/tmp";
			
			// Add read-only bind: "--ro-bind", "/", "/"
			args += "--ro-bind";
			args += "/";
			args += "/";
			
			// Use bubblewrap's --overlay for each project root
			// For each project root: --overlay-src (lower layer) and --overlay (RWSRC, WORKDIR, DEST)
			var upper_dir = GLib.Path.build_filename(this.overlay.overlay_dir, "upper");
			var work_dir = GLib.Path.build_filename(this.overlay.overlay_dir, "work");
			
			var entries_array = this.overlay.overlay_map.entries.to_array();
			for (int i = 0; i < entries_array.length; i++) {
				var entry = entries_array[i];
				var overlay_name = "overlay" + (i + 1).to_string();
				var work_name = "work" + (i + 1).to_string();
				
				// Create destination directory in sandbox (overlay will mount on it)
				args += "--dir";
				args += entry.value;  // Project root path
				
				// Lower layer (read-only source)
				args += "--overlay-src";
				args += entry.value;  // Project root path
				
				// Overlay mount: RWSRC (upper/overlayN), WORKDIR (work/workN), DEST (project root in sandbox)
				args += "--overlay";
				args += GLib.Path.build_filename(upper_dir, overlay_name);  // RWSRC
				args += GLib.Path.build_filename(work_dir, work_name);       // WORKDIR
				args += entry.value;  // DEST (project root path in sandbox)
			}
			
			// Set working directory to project folder (first project root)
			// This ensures commands run in the project directory context
			if (entries_array.length > 0) {
				args += "--chdir";
				args += entries_array[0].value;  // First project root path
			}
			
			// Add network args: If allow_network == false, add "--unshare-net"
			if (!this.allow_network) {
				args += "--unshare-net";
			}
			
			// Add separator: "--"
			args += "--";
			
			// Add shell command: "/bin/sh", "-c", command
			args += "/bin/sh";
			args += "-c";
			args += command;
			
			// Return final array
			return args;
		}
		
		/**
		 * Read stdout and stderr from subprocess and return combined output.
	 * 
	 * Uses IOChannel.add_watch() pattern from Spawn.vala to read from both
	 * streams concurrently as data arrives.
	 * 
	 * @param subprocess The Subprocess instance to read from
	 * @return Combined stdout + stderr output as string, with exit code appended if non-zero
	 * @throws Error if reading fails, waiting for process fails, or I/O errors occur
	 */
	private async string read_subprocess_output(GLib.Subprocess subprocess) throws Error
	{
		GLib.debug("read_subprocess_output: Starting to read from subprocess");
		
		// Get stdout and stderr streams from subprocess
		var stdout_stream = subprocess.get_stdout_pipe();
		var stderr_stream = subprocess.get_stderr_pipe();
		
		GLib.debug("read_subprocess_output: Got streams, stdout=%p, stderr=%p", stdout_stream, stderr_stream);
		
		// Reset accumulators for this execution
		this.ret_str = "";
		this.fail_str = "";
		
		// Convert InputStreams to IOChannels for concurrent monitoring
		// Note: We need to get file descriptors from the streams
		// For UnixInputStream, we can use get_fd()
		GLib.IOChannel? stdout_ch = null;
		GLib.IOChannel? stderr_ch = null;
		
		if (stdout_stream is GLib.UnixInputStream) {
			var unix_stdout = stdout_stream as GLib.UnixInputStream;
			stdout_ch = new GLib.IOChannel.unix_new(unix_stdout.get_fd());
		}
		
		if (stderr_stream is GLib.UnixInputStream) {
			var unix_stderr = stderr_stream as GLib.UnixInputStream;
			stderr_ch = new GLib.IOChannel.unix_new(unix_stderr.get_fd());
		}
		
		if (stdout_ch == null || stderr_ch == null) {
			throw new GLib.IOError.NOT_SUPPORTED(
				"Command execution is not supported on this system. The machine running this does not support command line execution because it lacks Unix stream support. Commands cannot be executed in this environment.");
		}
		
		// Make channels non-blocking
		stdout_ch.set_flags(GLib.IOFlags.NONBLOCK);
		stderr_ch.set_flags(GLib.IOFlags.NONBLOCK);
		
		// Track if streams are still open
		bool stdout_open = true;
		bool stderr_open = true;
		
		// Add watches to monitor both channels concurrently
		uint stdout_watch = stdout_ch.add_watch(
			GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
			(channel, condition) => {
				if ((condition & GLib.IOCondition.IN) != 0) {
					this.read_from_channel(channel, true);
				}
				if ((condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
					stdout_open = false;
					return false; // Remove watch
				}
				return stdout_open; // Keep watching if still open
			}
		);
		
		uint stderr_watch = stderr_ch.add_watch(
			GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
			(channel, condition) => {
				if ((condition & GLib.IOCondition.IN) != 0) {
					this.read_from_channel(channel, false);
				}
				if ((condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
					stderr_open = false;
					return false; // Remove watch
				}
				return stderr_open; // Keep watching if still open
			}
		);
		
		// Wait for process to complete
		GLib.debug("read_subprocess_output: Waiting for process to complete");
		int exit_status = 0;
		try {
			if (!(yield subprocess.wait_async(null))) {
				exit_status = subprocess.get_exit_status();
			}
		} catch (GLib.Error e) {
			if (!subprocess.get_successful()) {
				exit_status = subprocess.get_exit_status();
			}
			// Clean up watches - only remove if they haven't been removed already
			// (watch callbacks remove themselves when HUP/ERR is detected)
			if (stdout_open) {
				GLib.Source.remove(stdout_watch);
			}
			if (stderr_open) {
				GLib.Source.remove(stderr_watch);
			}
			throw new GLib.IOError.FAILED("Failed to wait for process: " + e.message);
		}
		
		GLib.debug("read_subprocess_output: Process completed with exit_status=%d, stdout_open=%s, stderr_open=%s", exit_status, stdout_open.to_string(), stderr_open.to_string());
		
		// Read any remaining data
		if (stdout_open) {
			GLib.debug("read_subprocess_output: Reading remaining stdout data");
			this.read_from_channel(stdout_ch, true);
		}
		if (stderr_open) {
			GLib.debug("read_subprocess_output: Reading remaining stderr data");
			this.read_from_channel(stderr_ch, false);
		}
		
		// Clean up watches - only remove if they haven't been removed already
		// (watch callbacks remove themselves when HUP/ERR is detected)
		if (stdout_open) {
			GLib.Source.remove(stdout_watch);
		}
		if (stderr_open) {
			GLib.Source.remove(stderr_watch);
		}
		
		// Build failure string (stderr + stdout + exit code) for failure case
		// fail_str already contains stderr, now add stdout
		var final_fail_str = this.fail_str;
		if (this.ret_str != "") {
			if (final_fail_str != "") {
				final_fail_str += "\n";
			}
			final_fail_str += this.ret_str;
		}
		
		// Add exit code to fail_str
		if (final_fail_str != "") {
			final_fail_str += "\n";
		}
		final_fail_str += "Exit code: " + exit_status.to_string() + "\n";
		
		// Debug: Output what we captured
		GLib.debug("Bubble.read_subprocess_output: exit_status=%d, ret_str length=%zu, fail_str length=%zu", exit_status, this.ret_str.length, this.fail_str.length);
		if (this.fail_str.length > 0) {
			GLib.debug("Bubble.read_subprocess_output: fail_str content: %s", this.fail_str);
		}
		
		// Return appropriate string based on exit status
		if (exit_status == 0) {
			// Success: return only stdout (no exit code, no stderr)
			return this.ret_str;
		} 
		// Failure: return stderr + stdout + exit code
		return final_fail_str;
		
	}
	
	/**
	 * Read from an IOChannel and accumulate output.
	 * 
	 * Based on Spawn.vala read() method pattern.
	 * Accumulates output into object properties as data arrives.
	 * 
	 * @param channel The IOChannel to read from
	 * @param is_stdout True if reading from stdout, false if stderr
	 */
	private void read_from_channel(GLib.IOChannel channel, bool is_stdout)
	{
		while (true) {
			string? buffer = null;
			size_t len = 0;
			size_t term_pos = 0;
			GLib.IOStatus status;
			
			try {
				status = channel.read_line(out buffer, out len, out term_pos);
			} catch (GLib.Error e) {
				GLib.debug("read_from_channel: Error reading from %s: %s", is_stdout ? "stdout" : "stderr", e.message);
				return; // Error reading, stop
			}
			
			if (buffer == null) {
				GLib.debug("read_from_channel: No more data from %s", is_stdout ? "stdout" : "stderr");
				return; // No more data
			}
			
			// If status is not NORMAL, return early
			if (status != GLib.IOStatus.NORMAL) {
				GLib.debug("read_from_channel: Status %s from %s, stopping", status.to_string(), is_stdout ? "stdout" : "stderr");
				return; // AGAIN, EOF, or ERROR - stop reading
			}
			
			// Status is NORMAL - accumulate output
			GLib.debug("read_from_channel: Read %zu bytes from %s: %s", len, is_stdout ? "stdout" : "stderr", buffer);
			if (is_stdout) {
				this.ret_str += buffer;
				continue; // Read more
			}
			
			if (this.fail_str != "") {
				this.fail_str += "\n";
			}
			this.fail_str += buffer;
			continue; // Read more
		}
	}
	}
}

