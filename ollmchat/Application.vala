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

namespace OLLMchat 
{
	// Global log file stream (opened lazily on first use, kept open for app lifetime)
	private GLib.FileStream? debug_log_file = null;
	// Flag to prevent recursive logging when errors occur in debug_log itself
	private bool debug_log_in_progress = false;

	/**
	 * Debug logging function that writes to ~/.cache/ollmchat/ollmchat.debug.log
	 * Also writes to stderr for immediate console output.
	 * To disable, comment out the function body or the call to this function.
	 */
	private void debug_log(string? in_domain, GLib.LogLevelFlags level, string message)
	{
		// Prevent recursive logging if an error occurs during logging
		if (debug_log_in_progress) {
			return;
		}
		var domain = in_domain == null ? "" : in_domain;
		// Always write to stderr for immediate console output
		var timestamp = (new DateTime.now_local()).format("%H:%M:%S.%f");
		stderr.printf(timestamp + ": " + level.to_string() + " : " + message + "\n");

		// Handle critical errors
		if ((level & GLib.LogLevelFlags.LEVEL_CRITICAL) != 0) {
			GLib.error("critical");
		}

		debug_log_in_progress = true;

		// Open log file lazily on first use (using FileStream to avoid GIO initialization deadlock)
		if (debug_log_file == null) {
			var log_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".cache", "ollmchat"
			);
			var log_file_path = GLib.Path.build_filename(log_dir, "ollmchat.debug.log");

			// Try to create directory if it doesn't exist (simple recursive approach)
			var parts = log_dir.split("/");
			var current_path = "";
			foreach (var part in parts) {
				if (part == "") {
					current_path = "/";
					continue;
				}
				if (current_path == "") {
					current_path = part;
				} else {
					current_path = current_path + "/" + part;
				}
				// Try to create directory (ignore errors if it already exists)
				try {
					GLib.DirUtils.create(current_path, 0755);
				} catch (GLib.FileError e) {
					// Ignore if directory already exists
					if (e.code != GLib.FileError.EXIST) {
						// For other errors, continue anyway - file open might still work
					}
				}
			}

			// Open file in write mode (truncates existing file) using FileStream (doesn't require GIO initialization)
			debug_log_file = GLib.FileStream.open(log_file_path, "w");
			if (debug_log_file == null) {
				stderr.printf("ERROR: FAILED TO OPEN DEBUG LOG FILE: Unable to open file stream\n");
				debug_log_in_progress = false;
				return;
			}
		}

		// Write to log file
		try {
			if (debug_log_file != null) {
				debug_log_file.puts(timestamp + ": " + level.to_string() + " : " + message + "\n");
				debug_log_file.flush();
			}
		} catch (GLib.Error e) {
			stderr.printf("ERROR: FAILED TO WRITE TO DEBUG LOG FILE: " + e.message + "\n");
		}  
		debug_log_in_progress = false;
		
	}

	int main(string[] args)
	{
		// Set up debug handler to write to ~/.cache/ollmchat/ollmchat.debug.log
		// To disable logging, comment out the debug_log() call below
		GLib.Log.set_default_handler((dom, lvl, msg) => {
			debug_log(dom, lvl, msg);  // Comment out this line to disable file logging
		});

		var app = new Gtk.Application("org.roojs.ollmchat", GLib.ApplicationFlags.DEFAULT_FLAGS);

		app.activate.connect(() => {
			var window = new OllmchatWindow(app);
			app.add_window(window);
			window.present();
		});

		return app.run(args);
	}
}
