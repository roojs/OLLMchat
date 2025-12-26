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

namespace OLLMchat.Settings
{
	/**
	 * Models tab content for settings dialog.
	 * 
	 * Manages model list and model-specific options configuration.
	 * Uses Adw.PreferencesPage with Adw.BoxedList for model list.
	 * Models are grouped by connection with section headers.
	 * 
	 * @since 1.0
	 */
	public class ModelsPage : Adw.PreferencesPage
	{
		/**
		 * Reference to parent SettingsDialog (which has the config object)
		 */
		public SettingsDialog settings_dialog { get; construct; }

		/**
		 * Current search filter text
		 */
		public string search_filter { get; private set; default = ""; }

		private Gtk.Box action_box;
		private Gtk.SearchBar search_bar;
		private Gtk.SearchEntry search_entry;
		private Gtk.Button add_model_btn;
		private Gtk.Button refresh_btn;
		private Adw.PreferencesGroup group;
		private Gtk.Box boxed_list;
		private Gtk.Box loading_box;
		private Gtk.Spinner loading_spinner;
		private Gtk.Label loading_label;
		private Gee.HashMap<string, ModelRow> model_rows = new Gee.HashMap<string, ModelRow>();
		private Gee.HashMap<string, Gtk.Widget> section_headers = new Gee.HashMap<string, Gtk.Widget>();
		private bool is_rendering = false;
		public OptionsWidget options_widget { get; private set; }

		/**
		 * Creates a new ModelsPage.
		 * 
		 * @param settings_dialog Parent SettingsDialog (which has the config object)
		 */
		public ModelsPage(SettingsDialog settings_dialog)
		{
			Object(settings_dialog: settings_dialog);

			// Set page title for tab
			this.title = "Models";

			// Create horizontal action bar
			this.action_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 12
			};

			// Create search bar (always visible)
			this.search_bar = new Gtk.SearchBar();
			this.search_entry = new Gtk.SearchEntry() {
				placeholder_text = "Search Models",
				hexpand = true
			};
			this.search_entry.changed.connect(() => {
				this.search_filter = this.search_entry.text;
				this.filter_models(this.search_filter);
			});
			this.search_bar.connect_entry(this.search_entry);
			this.search_bar.set_child(this.search_entry);
			// Make search bar always visible
			this.search_bar.set_key_capture_widget(this);
			this.search_bar.set_search_mode(true);
			this.action_box.append(this.search_bar);

			// Create Add Model button (placeholder - not implemented)
			this.add_model_btn = new Gtk.Button.with_label("Add Model") {
				css_classes = {"suggested-action"},
				sensitive = false,
				tooltip_text = "Not yet implemented"
			};
			this.action_box.append(this.add_model_btn);

			// Create Refresh button
			this.refresh_btn = new Gtk.Button.with_label("Refresh") {
				css_classes = {"suggested-action"}
			};
			this.refresh_btn.clicked.connect(() => {
				this.render_models.begin();
			});
			this.action_box.append(this.refresh_btn);

			// Create preferences group
			this.group = new Adw.PreferencesGroup() {
				title = "Models"
			};

			// Create boxed list for models
			this.boxed_list = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.group.add(this.boxed_list);

			// Create shared options widget (will be reparented to expanded ModelRow)
			this.options_widget = new OptionsWidget();

			// Create loading indicator (will be added/removed as needed)
			this.loading_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				margin_top = 48,
				margin_bottom = 48,
				visible = false
			};
			this.loading_spinner = new Gtk.Spinner() {
				spinning = false,
				halign = Gtk.Align.CENTER
			};
			this.loading_label = new Gtk.Label("Loading models...") {
				halign = Gtk.Align.CENTER
			};
			this.loading_box.append(this.loading_spinner);
			this.loading_box.append(this.loading_label);

			// Add action bar and preferences group to page
			// Note: Adw.PreferencesPage.add() only accepts Adw.PreferencesGroup,
			// so the action bar will be in the scrollable area
			var action_group = new Adw.PreferencesGroup();
			action_group.add(this.action_box);
			this.add(action_group);
			this.add(this.group);
		}

		/**
		 * Main method to render/update models list.
		 * 
		 * Fetches models from all connections, updates the UI incrementally,
		 * and shows a loading indicator during the process.
		 */
		public async void render_models()
		{
			if (this.is_rendering) {
				return;
			}
			this.is_rendering = true;

			// Show loading indicator and hide existing items
			this.show_loading(true);

			// Update models for each connection
			foreach (var entry in this.settings_dialog.config.connections.entries) {
				var connection = entry.value;
				var connection_url = entry.key;
				yield this.update_models(connection_url, connection);
			}

			// Remove models that no longer exist in any connection
			this.cleanup_removed_models();

			// Hide loading indicator and show items
			this.show_loading(false);

			this.is_rendering = false;
		}

		/**
		 * Updates models for a single connection.
		 * 
		 * Fetches models from the connection and updates the UI incrementally.
		 * 
		 * @param connection_url Connection URL (key in config.connections)
		 * @param connection Connection object
		 */
		private async void update_models(string connection_url, OLLMchat.Settings.Connection connection)
		{
			try {
				var client = new OLLMchat.Client(connection) {
					config = this.settings_dialog.config
				};
				var models_list = yield client.models();

				// Sort models alphabetically by name (case-insensitive)
				// Split by "/" and sort by the second part (model name) if present,
				// otherwise sort by the full name
				models_list.sort((a, b) => {
					string name_a = a.name;
					string name_b = b.name;
					
					// Split by "/" and use the second part if it exists
					var parts_a = name_a.split("/", 2);
					var parts_b = name_b.split("/", 2);
					
					string sort_key_a = parts_a.length > 1 ? parts_a[1] : parts_a[0];
					string sort_key_b = parts_b.length > 1 ? parts_b[1] : parts_b[0];
					
					// Case-insensitive comparison
					return strcmp(sort_key_a.down(), sort_key_b.down());
				});

				// Get or create section header for connection
				Gtk.Widget header_row;
				if (this.section_headers.has_key(connection_url)) {
					header_row = this.section_headers.get(connection_url);
				} else {
					header_row = new Adw.PreferencesRow() {
						title = connection.name
					};
					this.section_headers.set(connection_url, header_row);
					this.boxed_list.append(header_row);
				}
				header_row.visible = true;

				// Update/create model rows for this connection
				var existing_keys = new Gee.HashSet<string>();
				foreach (var model in models_list) {
					var composite_key = "%s#%s".printf(connection_url, model.name);
					existing_keys.add(composite_key);

					// Get or create options
					var options = new OLLMchat.Call.Options();
					if (this.settings_dialog.config.model_options.has_key(model.name)) {
						var config_options = this.settings_dialog.config.model_options.get(model.name);
						options = config_options.clone();
					}

					// Get or create model row
					ModelRow model_row;
					if (this.model_rows.has_key(composite_key)) {
						model_row = this.model_rows.get(composite_key);
					// Update options in case config changed
						model_row.load_options(options); 
						model_row.visible = true;
						continue;
					} 
					model_row = new ModelRow(model, connection, options, this);
					this.model_rows.set(composite_key, model_row);
					this.boxed_list.append(model_row);
					
					model_row.visible = true;
				}

				// Remove models from this connection that no longer exist
				var keys_to_remove = new Gee.ArrayList<string>();
				foreach (var key in this.model_rows.keys) {
					if (key.has_prefix(connection_url + "#") && !existing_keys.contains(key)) {
						keys_to_remove.add(key);
					}
				}
				foreach (var key in keys_to_remove) {
					var row = this.model_rows.get(key);
					row.unparent();
					this.model_rows.unset(key);
				}

			} catch (Error e) {
				GLib.warning("Failed to fetch models from connection %s: %s", connection.name, e.message);
			}
		}

		/**
		 * Removes section headers for connections that no longer exist.
		 */
		private void cleanup_removed_models()
		{
			var headers_to_remove = new Gee.ArrayList<string>();
			foreach (var key in this.section_headers.keys) {
				if (!this.settings_dialog.config.connections.has_key(key)) {
					headers_to_remove.add(key);
				}
			}
			foreach (var key in headers_to_remove) {
				var header = this.section_headers.get(key);
				header.unparent();
				this.section_headers.unset(key);
			}
		}

		/**
		 * Shows or hides the loading indicator.
		 * 
		 * @param show Whether to show the loading indicator
		 */
		private void show_loading(bool show)
		{
			if (show) {
				// Add loading indicator if not already added
				if (this.loading_box.get_parent() == null) {
					this.boxed_list.append(this.loading_box);
				}
				this.loading_spinner.spinning = true;
				this.loading_box.visible = true;

				// Hide all model rows and headers
				foreach (var row in this.model_rows.values) {
					row.visible = false;
				}
				foreach (var header in this.section_headers.values) {
					header.visible = false;
				}
				return;

			} 
			// Remove loading indicator
			if (this.loading_box.get_parent() != null) {
				this.boxed_list.remove(this.loading_box);
			}
			this.loading_spinner.spinning = false;
			this.loading_box.visible = false;

			// Show all model rows and headers
			foreach (var row in this.model_rows.values) {
				row.visible = true;
			}
			foreach (var header in this.section_headers.values) {
				header.visible = true;
			}
			
		}

		/**
		 * Saves model options to config if user has set any values.
		 * 
		 * Only saves models to config where user has set options (using model name only as key in Config2.model_options).
		 * 
		 * @param model_name Model name (used as key in config)
		 * @param options Options object to save
		 */
		public void save_options(string model_name, OLLMchat.Call.Options options)
		{
			if (options.has_values()) {
				// Save to config using model name only as key
				this.settings_dialog.config.model_options.set(model_name, options.clone());
			} else {
				// Remove from config if no values are set
				this.settings_dialog.config.model_options.unset(model_name);
			}
		}

		/**
		 * Saves all model options to config (called when window closes).
		 */
		public void save_all_options()
		{
			// If there's an expanded row, collapse it (which saves widget options and saves to config)
			var current_row = this.options_widget.current_model_row;
			if (current_row != null) {
				current_row.collapse();
			}
		}

		/**
		 * Filters model list by search text using show/hide visibility.
		 * 
		 * Does not remove models from list, just shows/hides them.
		 * Also hides connection section headers with no matching models.
		 * 
		 * @param search_text Search text to filter by
		 */
		public void filter_models(string search_text)
		{
			var search_lower = search_text.down();

			// Filter models
			foreach (var entry in this.model_rows.entries) {
				var composite_key = entry.key;
				var row = entry.value;
				
				// Extract model name from composite key
				var parts = composite_key.split("#", 2);
				if (parts.length != 2) {
					row.visible = false;
					continue;
				}
				var model_name = parts[1];
				
				// Check if model name matches search
				if (search_lower == "" || model_name.down().contains(search_lower)) {
					row.visible = true;
				} else {
					row.visible = false;
				}
			}
/*
			// Filter section headers - hide if no visible models in that connection
			foreach (var entry in this.section_headers.entries) {
				var connection_url = entry.key;
				var header = entry.value;
				bool connection_has_visible = false;

				// Check if any model from this connection is visible
				foreach (var model_entry in this.model_rows.entries) {
					var composite_key = model_entry.key;
					var model_row = model_entry.value;
					
					if (composite_key.has_prefix(connection_url + "#") && model_row.visible) {
						connection_has_visible = true;
						break;
					}
				}

				header.visible = connection_has_visible;
			}
				*/
		}
	}
}
