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

		var app = new Gtk.Application("org.roojs.roobuilder.test", GLib.ApplicationFlags.DEFAULT_FLAGS);

		app.activate.connect(() => {
			var window = new TestWindow(app);
			app.add_window(window);
			window.present();
		});

		return app.run(args);
	}

	/**
	 * Test window for testing ChatWidget.
	 * 
	 * This is a simple wrapper around ChatWidget for standalone testing.
	 * It includes a main() function and can be compiled independently.
	 * 
	 * @since 1.0
	 */
		public class TestWindow : Adw.Window
		{
			private OLLMchatGtk.ChatWidget chat_widget;
			private OLLMchat.History.Manager? history_manager = null;
			private Adw.OverlaySplitView split_view;
			private OLLMchatGtk.HistoryBrowser? history_browser = null;

		/**
		 * Creates a new TestWindow instance.
		 * 
		 * @param app The Gtk.Application instance
		 * @since 1.0
		 */
		public TestWindow(Gtk.Application app)
		{
			this.title = "OLL Chat Test";
			this.set_default_size(800, 600);

			// Create toolbar view to manage header bar and content
			var toolbar_view = new Adw.ToolbarView();
			
			// Create header bar with toggle button and new chat button
			var header_bar = new Adw.HeaderBar();
			var toggle_button = new Gtk.ToggleButton() {
				icon_name = "sidebar-show-symbolic",
				tooltip_text = "Toggle History"
			};
			header_bar.pack_start(toggle_button);
			
			var new_chat_button = new Gtk.Button() {
				icon_name = "list-add-symbolic",
				tooltip_text = "New Chat"
			};
			header_bar.pack_start(new_chat_button);
			
			// Connect new chat button to create new session
			new_chat_button.clicked.connect(() => {
				var new_session = this.history_manager.create_new_session();
				this.chat_widget.switch_to_session.begin(new_session);
			});
			
			// Add header bar to toolbar view's top slot
			toolbar_view.add_top_bar(header_bar);

			// Create overlay split view
			this.split_view = new Adw.OverlaySplitView();
			this.split_view.show_sidebar = false; // Hidden at start
			// Set sidebar width as fraction of total width (0.25 = 25% of window width)
			this.split_view.set_sidebar_width_fraction(0.25);
			// this.split_view.collapsed = true; // should we do it as expandy or overlay
			
			// Connect toggle button to show/hide sidebar
			toggle_button.toggled.connect(() => {
				this.split_view.show_sidebar = toggle_button.active;
				toggle_button.icon_name = toggle_button.active ? "sidebar-hide-symbolic" : "sidebar-show-symbolic";
			});

			// Read configuration from ~/.config/ollmchat/ollama.json
			// Example file content:
			/* 
{
	"url": "http://192.168.88.14:11434/api",
	//"model": "MichelRosselli/GLM-4.5-Air:Q4_K_M",
	"api_key": "your-api-key-here"
}
			 */
			var config_path = Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "ollmchat", "ollama.json"
			);
			if (!File.new_for_path(config_path).query_exists()) {
				throw new GLib.FileError.NOENT("Missing file: ~/.config/ollmchat/ollama.json");
			}
			
			var parser = new Json.Parser();
			try {
				parser.load_from_file(config_path);
			} catch (GLib.Error e) {
				throw new GLib.FileError.FAILED("Failed to load ollama.json: %s", e.message);
			}
			
			var obj = parser.get_root().get_object();
			if (obj == null) {
				throw new GLib.FileError.INVAL("Invalid ollama.json: file is empty or not valid JSON");
			}

			// Create CodeAssistant prompt generator with dummy provider
			var code_assistant = new Prompt.CodeAssistant(new Prompt.CodeAssistantDummy()) {
				shell = GLib.Environment.get_variable("SHELL") ?? "/usr/bin/bash",
			};
			
			var client = new OLLMchat.Client() {
				url = obj.get_string_member("url"),
				//model = obj.get_string_member("model"),
				api_key = obj.get_string_member("api_key"),
				stream = true,
				think =  obj.has_member("think") ?  obj.get_boolean_member("api_key") : false,
				keep_alive = "5m",
				prompt_assistant = code_assistant
			};
			
			// Try to set model from running models on server
			client.set_model_from_ps();
			
			// Set up history manager
			var data_dir = Path.build_filename(
				GLib.Environment.get_home_dir(), ".local", "share", "ollmchat"
			);
			// Ensure directory exists
			var data_dir_file = File.new_for_path(data_dir);
			if (!data_dir_file.query_exists()) {
				try {
					data_dir_file.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					GLib.warning("Failed to create data directory %s: %s", data_dir, e.message);
				}
			}
			
			// Create history manager with base client
			this.history_manager = new OLLMchat.History.Manager(client, data_dir);
			
			// Create history browser and add to split view sidebar
			this.history_browser = new OLLMchatGtk.HistoryBrowser(this.history_manager);
			this.split_view.sidebar = this.history_browser;
			
			// Connect history browser to load sessions
			this.connect_history_browser(this.history_browser);
			
			// Set up title generator if configured (async, don't wait)
			this.setup_title_generator.begin(obj);
			
			// Add tools to the client
			client.addTool(new OLLMchat.Tools.ReadFile(client));
			client.addTool(new OLLMchat.Tools.EditMode(client));
			client.addTool(new OLLMchatGtk.Tools.RunCommand(client, GLib.Environment.get_home_dir()));

			// Create chat widget with manager
			this.chat_widget = new OLLMchatGtk.ChatWidget(this.history_manager);
			
			// Create ChatView permission provider and set it on the base client
			var permission_provider = new OLLMchatGtk.Tools.Permission(
				this.chat_widget,
				Path.build_filename(
					GLib.Environment.get_home_dir(), ".config", "ollmchat"
				)) {
				application = app as GLib.Application,
			};
			client.permission_provider = permission_provider;
			
		 
		
			this.chat_widget.error_occurred.connect((error) => {
				stderr.printf("Error: %s\n", error);
			});

			// Set chat widget as main content
			this.split_view.content = this.chat_widget;

			// Set split view as toolbar view content
			toolbar_view.content = this.split_view;
			
			// Set toolbar view as window content
			this.set_content(toolbar_view);
		}

		/**
		 * Connects a HistoryBrowser to load sessions when selected.
		 * 
		 * Call this method after creating a HistoryBrowser to enable session loading.
		 * 
		 * @param history_browser The HistoryBrowser instance to connect
		 * @since 1.0
		 */
		public void connect_history_browser(OLLMchatGtk.HistoryBrowser history_browser)
		{
			history_browser.session_selected.connect((session) => {
				// switch_to_session() handles loading internally via load()
				this.chat_widget.switch_to_session.begin(session);
			});
		}
		
		/**
		 * Set up title generator if title_model is configured.
		 * Only sets up title generator if title_model is valid.
		 * Uses early returns for fail-fast pattern.
		 * 
		 * @param obj The JSON config object
		 */
		private async void setup_title_generator(Json.Object obj)
		{
			// Fail fast: check if title_model is configured
			if (!obj.has_member("title_model")) {
				GLib.warning("title_model not set in config - title generation disabled");
				return;
			}
			
			var title_model = obj.get_string_member("title_model");
			if (title_model == "") {
				GLib.warning("title_model is set but empty in config - title generation disabled");
				return;
			}
			
			// Create separate client for title generation
			var title_client = new OLLMchat.Client() {
				url = obj.get_string_member("url"),
				api_key = obj.get_string_member("api_key"),
				model = title_model,
				stream = false
			};
			
			// Fail fast: verify model exists on server
			try {
				yield title_client.show_model(title_model);
			} catch (Error e) {
				GLib.warning("title_model '%s' not found on server - title generation disabled: %s", title_model, e.message);
				return;
			}
			
			// Model exists - set up title generator
			if (this.history_manager != null) {
				this.history_manager.title_generator = new OLLMchat.History.TitleGenerator(title_client);
			}
		}
	}
}

