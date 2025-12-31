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
	// Static storage for debug logging
	private static GLib.FileStream? debug_log_file = null;
	private static bool debug_log_in_progress = false;
	
	/**
	 * Interface for OLLMchat applications that provides standardized
	 * configuration and data directory management.
	 *
	 * Implementations should call type registration methods (e.g.,
	 * `OLLMvector.Database.register_config()`) directly before calling
	 * `load_config()` if needed. The base_load_config() method handles
	 * Config1 to Config2 migration automatically.
	 *
	 * == Example ==
	 *
	 * {{{
	 * public class MyApp : Object, ApplicationInterface {
	 *     public Settings.Config2 config { get; set; }
	 *     public string data_dir { get; set; default = "~/.local/share/myapp"; }
	 *
	 *     public Settings.Config2 load_config() {
	 *         // Register types if needed
	 *         OLLMvector.Database.register_config();
	 *
	 *         // Use base implementation
	 *         return base_load_config();
	 *     }
	 * }
	 * }}}
	 *
	 * @since 1.0
	 */
	public interface ApplicationInterface : GLib.Object
	{
		/**
		 * The loaded configuration.
		 */
		public abstract OLLMchat.Settings.Config2 config { get; set; }
		
		/**
		 * Data directory path (default: `~/.local/share/ollmchat`).
		 */
		public abstract string data_dir { get; set; }
		
		/**
		 * Ensures the data directory exists, creating it if necessary.
		 *
		 * @throws GLib.Error if the directory cannot be created
		 */
		public void ensure_data_dir() throws GLib.Error
		{
			var data_dir_file = GLib.File.new_for_path(this.data_dir);
			if (!data_dir_file.query_exists()) {
				data_dir_file.make_directory_with_parents(null);
			}
		}
		
		/**
		 * Base implementation that loads configuration, handling Config1 to Config2 migration.
		 *
		 * This method:
		 * - Initializes Config1 and Config2 static properties
		 * - Sets config paths
		 * - Loads Config2 if it exists
		 * - Migrates Config1 to Config2 if needed
		 * - Returns loaded or default Config2 instance
		 *
		 * Implementations should call this from their `load_config()` method
		 * after performing any necessary type registration.
		 *
		 * @return The loaded Config2 instance
		 */
		protected virtual OLLMchat.Settings.Config2 base_load_config()
		{
			var config_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "ollmchat"
			);
			
			// Create instances first to ensure static properties are initialized
			var dummy1 = new OLLMchat.Settings.Config1();
			var dummy2 = new OLLMchat.Settings.Config2();
			
			// Set static config_path for both Config1 and Config2
			OLLMchat.Settings.Config2.config_path = GLib.Path.build_filename(config_dir, "config.2.json");
			OLLMchat.Settings.Config1.config_path = GLib.Path.build_filename(config_dir, "config.json");
			
			// Check for config.2.json first
			if (GLib.FileUtils.test(OLLMchat.Settings.Config2.config_path, GLib.FileTest.EXISTS)) {
				// Load config.2.json
				GLib.debug("Loading config from %s", OLLMchat.Settings.Config2.config_path);
				var config = OLLMchat.Settings.Config2.load();
				return config;
			}
			
			// Check for config.json and convert to config.2.json
			if (!GLib.FileUtils.test(OLLMchat.Settings.Config1.config_path, GLib.FileTest.EXISTS)) {
				return new OLLMchat.Settings.Config2();
			}
			
			GLib.debug("Loading config.json and converting to config.2.json");
			var config1 = OLLMchat.Settings.Config1.load();
			if (!config1.loaded) {
				return new OLLMchat.Settings.Config2();
			}
			var config = config1.toV2();
			
			// Save as config.2.json if conversion was successful
			if (config.loaded) {
				try {
					config.save();
					GLib.debug("Saved converted config as %s", OLLMchat.Settings.Config2.config_path);
				} catch (GLib.Error e) {
					GLib.warning("Failed to save config.2.json: %s", e.message);
				}
			}
			
			return config;
		}
		
		/**
		 * Loads and returns the configuration.
		 *
		 * Implementations should call type registration methods (e.g.,
		 * `OLLMvector.Database.register_config()`) if needed, then call
		 * `base_load_config()` to perform the actual loading.
		 *
		 * @return The loaded Config2 instance
		 */
		public abstract OLLMchat.Settings.Config2 load_config();
		
		/**
		 * Debug logging function that writes to ~/.cache/ollmchat/{app_id}.debug.log
		 * Also writes to stderr for immediate console output.
		 *
		 * @param app_id The application ID to use for the log file name
		 * @param in_domain The log domain (can be null)
		 * @param level The log level
		 * @param message The log message
		 */
		protected static void debug_log(string app_id, string? in_domain, GLib.LogLevelFlags level, string message)
		{
			// Prevent recursive logging if an error occurs during logging
			if (debug_log_in_progress) {
				return;
			}
			
			// Always write to stderr for immediate console output
			var timestamp = (new GLib.DateTime.now_local()).format("%H:%M:%S.%f");
			GLib.stderr.printf(
				timestamp + ": " + level.to_string() + " : " + (in_domain == null ? "" : in_domain) + " : " + message + "\n"
			);

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
				var log_file_path = GLib.Path.build_filename(log_dir, app_id + ".debug.log");

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
					GLib.stderr.printf("ERROR: FAILED TO OPEN DEBUG LOG FILE: Unable to open file stream\n");
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
				GLib.stderr.printf("ERROR: FAILED TO WRITE TO DEBUG LOG FILE: " + e.message + "\n");
			}
			debug_log_in_progress = false;
		}
	}
}

