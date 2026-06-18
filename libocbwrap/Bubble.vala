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

namespace OLLMbwrap
{
	/**
	 * Bubble class for executing commands in bubblewrap sandbox.
	 * 
	 * This class provides secure command execution using bubblewrap (bwrap) to sandbox
	 * commands. It creates a read-only root filesystem with read-write access only to
	 * specific project directories identified by the project's build_roots() method.
	 * 
	 * The sandbox configuration:
	 * - Mounts the entire filesystem as read-only (--ro-bind / /) unless write_array adds --bind roots
	 * - Provides read-write access to project directories via overlay filesystem
	 * - Blocks network access by default (--unshare-net, unless allow_network is true)
	 * - Executes commands via /bin/sh -c
	 * - Provides isolated temporary directory (/tmp) via tmpfs
	 * - Mounts /dev read-only (like the rest of the system) with /dev/null writable for output redirection
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
	public class Bubble : GLib.Object
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
		 * Project root path; empty means no-project mode (overlay create/cleanup no-op).
		 */
		public string project_path { get; construct; default = ""; }

		/**
		 * When false, bwrap uses --unshare-net and seccomp can monitor socket syscalls.
		 */
		public bool allow_network { get; construct; default = false; }

		/**
		 * Parsed allow_write tokens: no, project, or absolute paths.
		 */
		public string[] write_tokens { get; construct; default = {}; }

		/**
		 * Writable project root paths for overlay subdirectories.
		 */
		public Gee.HashMap<string, string> write_roots {
			get; construct; default = new Gee.HashMap<string, string> ();
		}

		public FileVerification verification { get; construct; }

		/**
		 * Overlay for this run; created in ctor, profile synced before {@link exec}
		 * and {@link build_bubble_args}.
		 */
		public Overlay overlay { get; private set; }

		/**
		 * Absolute path to the bubblewrap binary, or empty if not found.
		 *
		 * Callers should use {@link can_wrap} before constructing {@link Bubble}.
		 */
		public string bwrap_exe { get; private set; default = ""; }

		/**
		 * Accumulator for stdout output (for success case).
		 */
		public string ret_str { get; private set; default = ""; }
		
		/**
		 * Accumulator for stderr output (for failure case).
		 */
		public string fail_str { get; private set; default = ""; }
		
		/**
		 * @param verification Non-null apply hook wired into {@link Overlay} / {@link Scan}
		 */
		public Bubble (FileVerification verification)
		{
			Object (verification: verification);

			string? bp = GLib.Environment.find_program_in_path("bwrap");
			this.bwrap_exe = bp != null ? bp : "";
			this.overlay = new Overlay (this.verification);
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
		 * @param working_dir Optional working directory (absolute path). If empty, defaults to first project root.
		 * @return String containing command output (stdout + stderr, with exit code if non-zero)
		 * @throws Error if command execution fails, subprocess creation fails, or I/O errors occur
		 */
		public async string exec(string command, string working_dir = "") throws Error
		{
			this.overlay.project_path = this.project_path;
			this.overlay.write_roots = this.write_roots;
			this.overlay.create();
			var run_seccomp = new RunSeccomp(this);
			var launcher = new GLib.SubprocessLauncher(
				GLib.SubprocessFlags.STDOUT_PIPE |
				GLib.SubprocessFlags.STDERR_PIPE |
				GLib.SubprocessFlags.STDIN_INHERIT);
			run_seccomp.wire_launcher(launcher);
			
			
			string[] args;
			try {
				args = this.build_bubble_args(command, working_dir);
			} catch (Error e) {
				this.overlay.cleanup();
				run_seccomp.detach_sources();
				throw e;
			}


			GLib.debug("running command: %s", string.joinv(" ", args));
			Error? err = null;
			GLib.Subprocess? subprocess = null;
			try {
				subprocess = launcher.spawnv(args);
			} catch (GLib.Error se) {
				err = new GLib.IOError.FAILED(
					"Failed to create bubblewrap subprocess: " + se.message);
			}
			var result = "";
			 
			if (err == null) {
				try {
					run_seccomp.finish_handshake();
					run_seccomp.attach_notify_loop();
					result = yield this.read_subprocess_output(subprocess, run_seccomp);
					yield this.overlay.scan.run();
				} catch (Error e) {
					err = e;
				}
			}
			run_seccomp.detach_sources();
			this.overlay.cleanup();
			if (err != null) {
				throw err;
			}
			return result;
		}
		
		/**
		 * Get the playground directory path, ensuring it exists.
		 * 
		 * Returns the fixed path to the playground directory:
		 * ~/.local/share/ollmchat/playground
		 * Creates the directory if it doesn't exist.
		 * 
		 * @return Absolute path to playground directory
		 * @throws Error if the directory cannot be created
		 */
		private string playground_path() throws Error
		{
			var playground_path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(),
				".local",
				"share",
				"ollmchat",
				"playground"
			);
			var playground_file = GLib.File.new_for_path(playground_path);
			if (!playground_file.query_exists()) {
				playground_file.make_directory_with_parents(null);
			}
			return playground_path;
		}
		
		/**
		 * Ensure $HOME/playground exists on the host so bwrap can use it as a bind mount point.
		 * After --ro-bind / /, the mount point must exist; we create it if missing and set
		 * home_playground_created so we remove it in the exec() finally block when bwrap ends.
		 */
	 
		
		/**
		 * Build complete bubblewrap command line arguments.
		 * 
		 * Constructs the full command line for bubblewrap, including:
		 * - Read-only root filesystem bind (--ro-bind / /)
		 * - Device filesystem mount (--ro-bind /dev /dev) with /dev/null override (--dev-bind) for output redirection
		 * - Read-write binds for overlay mount point at each project root location
		 * - Playground directory mount (--bind) at $HOME/playground
		 * - Temporary directory mount (--tmpfs /tmp)
		 * - Network isolation flag (--unshare-net) if network is not allowed
		 * - Working directory flag (--chdir) if working_dir is provided
		 * - Command separator (--)
		 * - Shell command (/bin/sh -c "command")
		 * 
		 * The resulting array can be passed directly to GLib.Subprocess.newv().
		 * 
		 * @param command Shell command after "--" via /bin/sh -c when non-empty; when empty, only "--" is added and caller appends argv (MCP stdio).
		 * @param working_dir Optional working directory (absolute path). If empty, defaults to first project root.
		 * @return Array of arguments for bubblewrap
		 * @throws Error if argument building fails
		 */
		public string[] build_bubble_args(string command, string working_dir = "") throws Error
		{
			this.overlay.project_path = this.project_path;
			this.overlay.write_roots = this.write_roots;

			// Start with empty array and use += to build it
			string[] args = {};

			// Start with: ["bwrap"]
			args += this.bwrap_exe;
			
			args += "--unshare-user";

			var home = GLib.Environment.get_home_dir();

			if (this.project_path != "") {
				// Project mode: mount playground before ro-bind
				args += "--dir";
				args += GLib.Path.build_filename(home, "playground");
				args += "--bind";
				args += this.playground_path();
				args += GLib.Path.build_filename(home, "playground");
			}

			args += "--ro-bind";
			args += "/";
			args += "/";

			// Extra --bind pairs from validated write_array (absolute roots only after first segment rules).
			for (var i = 0; i < this.write_tokens.length; i++) {
				var root = this.write_tokens[i];
				if (i == 0 && (root.down() == "no" || root.down() == "project")) {
					break;
				}
				args += "--bind";
				args += root;
				args += root;
			}

			args += "--tmpfs";
			args += "/tmp";

			args += "--ro-bind";
			args += "/dev";
			args += "/dev";
			args += "--dev-bind";
			args += "/dev/null";
			args += "/dev/null";

			if (this.overlay.overlay_map.size > 0) {
				var upper_dir = GLib.Path.build_filename(this.overlay.overlay_dir, "upper");
				var work_dir = GLib.Path.build_filename(this.overlay.overlay_dir, "work");
				var entries_array = this.overlay.overlay_map.entries.to_array();
				for (int i = 0; i < entries_array.length; i++) {
					var entry = entries_array[i];
					var overlay_name = "overlay" + (i + 1).to_string();
					var work_name = "work" + (i + 1).to_string();
					args += "--dir";
					args += entry.value;
					args += "--overlay-src";
					args += entry.value;
					args += "--overlay";
					args += GLib.Path.build_filename(upper_dir, overlay_name);
					args += GLib.Path.build_filename(work_dir, work_name);
					args += entry.value;
				}
			}

			if (working_dir != "") {
				args += "--chdir";
				args += working_dir;
			} else if (this.overlay.overlay_map.size > 0) {
				var entries = this.overlay.overlay_map.entries.to_array();
				var first = entries[0].value;
				args += "--chdir";
				args += first;
			} else {
				args += "--chdir";
				args += home;
			}
			
			// Add network args: If allow_network == false, add "--unshare-net"
			if (!this.allow_network) {
				args += "--unshare-net";
			}
			
			// Add separator: "--"
			args += "--";
			if (command != "") {
				args += "/bin/sh";
				args += "-c";
				args += command;
			}
			return args;
		}

		/**
		 * Whether writes to @path are permitted for this sandbox profile.
		 * Must match {@link build_bubble_args} (bind / overlay / tmpfs / dev-bind).
		 *
		 * @param path absolute path from NOTIFY (caller must not pass raw tool strings to re-tokenize)
		 */
		public bool can_write (string path)
		{
			if (path == "/tmp" || path.has_prefix("/tmp/")) {
				return true;
			}
			if (path == "/dev/null") {
				return true;
			}
			if (path == "/dev/tty") {
				return true;
			}
			var home = GLib.Environment.get_home_dir();
			var bind_play = GLib.Path.build_filename(home, "playground");
			if (path == bind_play || path.has_prefix(bind_play + "/")) {
				return true;
			}
			if (this.overlay.overlay_map.size > 0) {
				foreach (var e in this.overlay.overlay_map.entries) {
					var lower = e.value;
					if (path == lower || path.has_prefix(lower + "/")) {
						return true;
					}
				}
			}
			for (var i = 0; i < this.write_tokens.length; i++) {
				var root = this.write_tokens[i];
				if (i == 0 && (root.down() == "no" || root.down() == "project")) {
					return false;
				}
				if (path == root || path.has_prefix(root + "/")) {
					return true;
				}
			}
			return false;
		}

		/**
		 * Read stdout and stderr from subprocess and return combined output.
	 * 
	 * Uses IOChannel.add_watch() pattern from Spawn.vala to read from both
	 * streams concurrently as data arrives.
	 * 
	 * @param subprocess The Subprocess instance to read from
	 * @param run_seccomp NOTIFY aggregator for this run (same main loop as this async method)
	 * @return Combined stdout + stderr output as string, with exit code appended if non-zero
	 * @throws Error if reading fails, waiting for process fails, or I/O errors occur
	 */
	private async string read_subprocess_output (
		GLib.Subprocess subprocess,
		RunSeccomp run_seccomp) throws Error
	{
		// Get stdout and stderr streams from subprocess
		var stdout_stream = subprocess.get_stdout_pipe();
		var stderr_stream = subprocess.get_stderr_pipe();
		
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
		int exit_status = 0;
		try {
			yield subprocess.wait_async(null);
			// Always get exit status, regardless of success/failure
			exit_status = subprocess.get_exit_status();
		} catch (GLib.Error e) {
			// If wait_async failed, try to get exit status if process has terminated
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
		
		// Read any remaining data
		if (stdout_open) {
			this.read_from_channel(stdout_ch, true);
		}
		if (stderr_open) {
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

		run_seccomp.drain_notify_readable();
		run_seccomp.finish_evidence_formatting();

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
		final_fail_str += "Exit code: " + exit_status.to_string();
		string[] appendix = {};
		foreach (string part in new string[] {
			run_seccomp.network,
			run_seccomp.skipped,
			run_seccomp.fs
		}) {
			string t = part.chomp();
			if (t == "") {
				continue;
			}
			appendix += t;
		}
		if (appendix.length > 0) {
			final_fail_str += "\n" + string.joinv("\n", appendix);
		}
		final_fail_str += "\n";

		// Return appropriate string based on exit status
		if (exit_status == 0) {
			if (run_seccomp.fs != "") {
				if (this.ret_str != "") {
					return this.ret_str + "\n" + run_seccomp.fs;
				}
				return run_seccomp.fs;
			}
			if (run_seccomp.skipped != "") {
				if (this.ret_str != "") {
					return this.ret_str + "\n" + run_seccomp.skipped;
				}
				return run_seccomp.skipped;
			}
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
				return; // Error reading, stop
			}
			
			if (buffer == null) {
				return; // No more data
			}
			
			// If status is not NORMAL, return early
			if (status != GLib.IOStatus.NORMAL) {
				return; // AGAIN, EOF, or ERROR - stop reading
			}
			
			// Status is NORMAL - accumulate output
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

