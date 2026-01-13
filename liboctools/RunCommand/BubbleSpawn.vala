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
		// Get stdout and stderr streams from subprocess
		var stdout_stream = subprocess.get_stdout_pipe();
		var stderr_stream = subprocess.get_stderr_pipe();
		
		// Accumulators for output as it arrives
		string ret_str = "";  // stdout only (for success)
		string fail_str = "";  // stderr + stdout (for failure)
		
		// Convert InputStreams to IOChannels for concurrent monitoring
		// Note: We need to get file descriptors from the streams
		// For UnixInputStream, we can use get_fd()
		GLib.IOChannel? stdout_ch = null;
		GLib.IOChannel? stderr_ch = null;
		
		if (stdout_stream is GLib.UnixInputStream) {
			var unix_stdout = stdout_stream as GLib.UnixInputStream;
			stdout_ch = new GLib.IOChannel.unix_new(unix_stdout.get_fd());
		} else {
			// Fallback: use async read if we can't get FD
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
			
			// Build return string (stdout only) for success case
			ret_str = stdout_output;
			
			// Build failure string (stderr + stdout + exit code) for failure case
			if (stderr_output != "") {
				fail_str = stderr_output;
			}
			if (stdout_output != "") {
				if (fail_str != "") {
					fail_str += "\n";
				}
				fail_str += stdout_output;
			}
			if (fail_str != "") {
				fail_str += "\n";
			}
			fail_str += "Exit code: " + exit_status.to_string() + "\n";
			
			if (exit_status == 0) {
				return ret_str;
			} else {
				return fail_str;
			}
		}
		
		if (stderr_stream is GLib.UnixInputStream) {
			var unix_stderr = stderr_stream as GLib.UnixInputStream;
			stderr_ch = new GLib.IOChannel.unix_new(unix_stderr.get_fd());
		}
		
		if (stdout_ch == null || stderr_ch == null) {
			// Fallback to sequential reading
			var stdout_output = yield this.read_stream_async(stdout_stream);
			var stderr_output = yield this.read_stream_async(stderr_stream);
			
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
			
			ret_str = stdout_output;
			if (stderr_output != "") {
				fail_str = stderr_output;
			}
			if (stdout_output != "") {
				if (fail_str != "") {
					fail_str += "\n";
				}
				fail_str += stdout_output;
			}
			if (fail_str != "") {
				fail_str += "\n";
			}
			fail_str += "Exit code: " + exit_status.to_string() + "\n";
			
			if (exit_status == 0) {
				return ret_str;
			} else {
				return fail_str;
			}
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
					this.read_from_channel(channel, ref ret_str, ref fail_str, true);
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
					this.read_from_channel(channel, ref ret_str, ref fail_str, false);
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
			if (!(yield subprocess.wait_async(null))) {
				exit_status = subprocess.get_exit_status();
			}
		} catch (GLib.Error e) {
			if (!subprocess.get_successful()) {
				exit_status = subprocess.get_exit_status();
			}
			// Clean up watches
			GLib.Source.remove(stdout_watch);
			GLib.Source.remove(stderr_watch);
			throw new GLib.IOError.FAILED("Failed to wait for process: " + e.message);
		}
		
		// Read any remaining data
		if (stdout_open) {
			this.read_from_channel(stdout_ch, ref ret_str, ref fail_str, true);
		}
		if (stderr_open) {
			this.read_from_channel(stderr_ch, ref ret_str, ref fail_str, false);
		}
		
		// Clean up watches
		GLib.Source.remove(stdout_watch);
		GLib.Source.remove(stderr_watch);
		
		// Build failure string (stderr + stdout + exit code) for failure case
		// fail_str already contains stderr, now add stdout
		if (ret_str != "") {
			if (fail_str != "") {
				fail_str += "\n";
			}
			fail_str += ret_str;
		}
		
		// Add exit code to fail_str
		if (fail_str != "") {
			fail_str += "\n";
		}
		fail_str += "Exit code: " + exit_status.to_string() + "\n";
		
		// Return appropriate string based on exit status
		if (exit_status == 0) {
			// Success: return only stdout (no exit code, no stderr)
			return ret_str;
		} else {
			// Failure: return stderr + stdout + exit code
			return fail_str;
		}
	}
	
	/**
	 * Read from an IOChannel and accumulate output.
	 * 
	 * Based on Spawn.vala read() method pattern.
	 * 
	 * @param channel The IOChannel to read from
	 * @param ret_str Reference to stdout accumulator
	 * @param fail_str Reference to stderr accumulator
	 * @param is_stdout True if reading from stdout, false if stderr
	 */
	private void read_from_channel(GLib.IOChannel channel, ref string ret_str, ref string fail_str, bool is_stdout)
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
			
			switch (status) {
				case GLib.IOStatus.NORMAL:
					if (is_stdout) {
						ret_str += buffer;
					} else {
						if (fail_str != "") {
							fail_str += "\n";
						}
						fail_str += buffer;
					}
					continue; // Read more
				case GLib.IOStatus.AGAIN:
					return; // No data available now, will be called again
				case GLib.IOStatus.EOF:
				case GLib.IOStatus.ERROR:
					return; // Stream closed or error
			}
			break;
		}
	}

