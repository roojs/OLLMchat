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

namespace OLLMapp.SettingsDialog
{
	/**
	 * Models tab content for settings dialog.
	 * 
	 * Manages model list and model-specific options configuration.
	 * Uses Adw.PreferencesGroup with Adw.BoxedList for model list.
	 * Models are grouped by connection with section headers.
	 * 
	 * @since 1.0
	 */
	public class ModelsPage : SettingsPage
	{
		/**
		 * Reference to parent SettingsDialog (which has the app object)
		 */
		public MainDialog dialog { get; construct; }

		/**
		 * Current search filter text
		 */
		public string search_filter { get; private set; default = ""; }
		

		private Gtk.SearchBar search_bar;
		private Gtk.SearchEntry search_entry;
		private Gtk.Button add_model_btn;
		private Gtk.Button refresh_btn;
		private Gtk.ScrolledWindow scrolled_window;
		private Adw.PreferencesGroup group;
		private Gtk.Box boxed_list;
		private Gtk.Box loading_box;
		private Gtk.Spinner loading_spinner;
		private Gtk.Label loading_label;
		public Gee.HashMap<string, ModelRow> model_rows = new Gee.HashMap<string, ModelRow>();
		private Gee.HashMap<string, Gtk.Widget> section_headers = new Gee.HashMap<string, Gtk.Widget>();
		private bool is_rendering = false;
		private AddModelDialog? add_model_dialog = null;
		public OLLMchat.Settings.ConnectionModels connection_models { get; private set; }

		/**
		 * Creates a new ModelsPage.
		 * 
		 * @param dialog Parent SettingsDialog (which has the app object)
		 */
		public ModelsPage(MainDialog dialog)
		{
			Object(
				dialog: dialog,
				page_name: "models",
				page_title: "Models",
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0
			);
			
			// Get ConnectionModels from parent window's history manager
			var parent_window = this.dialog.parent as OllmchatWindow;
			if (parent_window != null && parent_window.history_manager != null) {
				this.connection_models = parent_window.history_manager.connection_models;
			} else {
				// Create a default ConnectionModels instance if parent window is not available
				this.connection_models = new OLLMchat.Settings.ConnectionModels(this.dialog.app.config);
			}
			
			// Create horizontal action bar (set as action_widget for SettingsDialog to manage)
			this.action_widget = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				hexpand = true
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
			this.action_widget.append(this.search_bar);

			// Create Add Model button
			this.add_model_btn = new Gtk.Button.with_label("Add Model") {
				css_classes = {"suggested-action"},
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.add_model_btn.clicked.connect(() => {
				this.show_add_model_dialog();
			});
			this.action_widget.append(this.add_model_btn);

			// Create Refresh button
			this.refresh_btn = new Gtk.Button.from_icon_name("view-refresh") {
				tooltip_text = "Reload downloaded model list from ollama/openapi server",
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.refresh_btn.clicked.connect(() => {
				// Save expanded model options before refreshing
				this.save_all_options();
				this.render_models.begin();
			});
			this.action_widget.append(this.refresh_btn);

			// Create preferences group (no title; tab already shows "Models")
			this.group = new Adw.PreferencesGroup();

			// Create boxed list for models
			this.boxed_list = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.group.add(this.boxed_list);

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

			// Page has its own ScrolledWindow (no shared outer scroll)
			this.scrolled_window = new Gtk.ScrolledWindow() {
				vexpand = true,
				hexpand = true
			};
			this.scrolled_window.set_child(this.group);
			this.scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			this.append(this.scrolled_window);
			
			this.connection_models.items_changed.connect((position, removed, added) => {
				this.sync_ui_from_store.begin();
			});

			this.dialog.pull_manager.model_complete.connect((model_name) => {
				this.connection_models.refresh.begin();
			});
			
			// Action bar will be added to dialog's action_bar_area on activation
		}

		/**
		 * Main method to render/update models list.
		 * 
		 * Uses ConnectionModels to get models from all connections, updates the UI incrementally,
		 * and shows a loading indicator during the process.
		 */
		public async void render_models()
		{
			if (this.is_rendering) {
				return;
			}
			this.is_rendering = true;

			this.show_loading(true);
			yield this.connection_models.refresh();
			yield this.sync_ui_from_store();
			this.show_loading(false);

			this.is_rendering = false;
		}

		/**
		 * Syncs the boxed_list (model rows, section headers) to the current store state.
		 * Does not refetch; use when the store has already been updated (e.g. after items_changed).
		 */
		private async void sync_ui_from_store()
		{
			foreach (var entry in this.connection_models.connection_map.entries) {
				var connection_url = entry.key;
				var connection = this.dialog.app.config.connections.get(connection_url);
				if (connection == null || !connection.is_working) {
					continue;
				}
				var models_list = new Gee.ArrayList<OLLMchat.Settings.ModelUsage>();
				models_list.add_all(entry.value.values);
				yield this.update_models_from_connection_models(connection, models_list);
			}
			this.cleanup_removed_models();
		}

		/**
		 * Updates models for a single connection using ConnectionModels.
		 * 
		 * Updates the UI incrementally based on ModelUsage objects from ConnectionModels.
		 * 
		 * @param connection Connection object
		 * @param models_list List of ModelUsage objects for this connection
		 */
		private async void update_models_from_connection_models(OLLMchat.Settings.Connection connection, Gee.ArrayList<OLLMchat.Settings.ModelUsage> models_list)
		{
			// Skip if connection is not working
			if (!connection.is_working) {
				GLib.debug("Skipping models update for connection %s (not working)", connection.url);
				return;
			}

			// Sort models by model name using ModelUsageSort
			var sorter = new OLLMchatGtk.List.ModelUsageSort();
			models_list.sort((a, b) => {
				return (int)sorter.compare(a, b);
			});

			// Get or create section header for connection
			Gtk.Widget header_row;
			if (this.section_headers.has_key(connection.url)) {
				header_row = this.section_headers.get(connection.url);
			} else {
				header_row = new Adw.PreferencesRow() {
					title = connection.name
				};
				this.section_headers.set(connection.url, header_row);
				this.boxed_list.append(header_row);
			}
			header_row.visible = true;

			// Update/create model rows for this connection
			var existing_keys = new Gee.HashSet<string>();
			foreach (var model_usage in models_list) {
				var composite_key = "%s#%s".printf(connection.url, model_usage.model);
				existing_keys.add(composite_key);

				// Use model_obj from ModelUsage if available, otherwise create a basic one
				OLLMchat.Response.Model detailed_model;
				if (model_usage.model_obj != null) {
					detailed_model = model_usage.model_obj;
				} else {
					// Create a basic model object if model_obj is not set
					detailed_model = new OLLMchat.Response.Model();
					detailed_model.name = model_usage.model;
				}

				// Get or create options
				var options = new OLLMchat.Call.Options();
				if (this.dialog.app.config.model_options.has_key(model_usage.model)) {
					var config_options = this.dialog.app.config.model_options.get(model_usage.model);
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
				model_row = new ModelRow(detailed_model, connection, options, this);
				this.model_rows.set(composite_key, model_row);
				this.boxed_list.append(model_row);
				
				model_row.visible = true;
			}

			// Remove models from this connection that no longer exist
			var keys_to_remove = new Gee.ArrayList<string>();
			foreach (var key in this.model_rows.keys) {
				if (key.has_prefix(connection.url + "#") && !existing_keys.contains(key)) {
					keys_to_remove.add(key);
				}
			}
			foreach (var key in keys_to_remove) {
				var row = this.model_rows.get(key);
				row.unparent();
				this.model_rows.unset(key);
			}

			// Desired order (already sorted by ModelUsageSort / display name)
			var desired_rows = new Gee.ArrayList<ModelRow>();
			foreach (var model_usage in models_list) {
				var composite_key = "%s#%s".printf(connection.url, model_usage.model);
				if (this.model_rows.has_key(composite_key)) {
					desired_rows.add(this.model_rows.get(composite_key));
				}
			}
			Gtk.Widget? prev = header_row;
			foreach (var row in desired_rows) {
				// Only reorder if this row is not already immediately after prev
				if (row.get_prev_sibling() != prev) {
					this.boxed_list.reorder_child_after(row, prev);
				}
				prev = row;
			}
		}

		/**
		 * Removes section headers for connections that no longer exist.
		 */
		private void cleanup_removed_models()
		{
			var headers_to_remove = new Gee.ArrayList<string>();
			foreach (var key in this.section_headers.keys) {
				if (!this.dialog.app.config.connections.has_key(key)) {
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
				this.dialog.app.config.model_options.set(model_name, options.clone());
			} else {
				// Remove from config if no values are set
				this.dialog.app.config.model_options.unset(model_name);
			}
		}

		/**
		 * Saves all model options to config (called when window closes).
		 */
		public void save_all_options()
		{
			// If there's an expanded row, collapse it (which saves widget options and saves to config)
			foreach (var row in this.model_rows.values) {
				if (row.expanded) {
					row.collapse();
				}
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
				// Extract model name from composite key
				var parts = entry.key.split("#", 2);
				if (parts.length != 2) {
					entry.value.visible = false;
					continue;
				}
				
				// Check if model name matches search
				entry.value.visible = (search_lower == "" || parts[1].down().contains(search_lower));
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

		/**
		 * Scrolls a widget to 20px below the top of the viewport.
		 * 
		 * @param widget The widget to scroll into view
		 */
		public void scroll_to(Gtk.Widget widget)
		{
			var vadjustment = this.scrolled_window.vadjustment;
			
			// Get the scrolled content (this page's group) as reference point
			var viewport_child = this.scrolled_window.get_child();
		
			
			// Y from allocation walk is in viewport coords (negative when widget is above visible area).
			// Add current scroll to get position in content space.
			double y_viewport = 0.0;
			Gtk.Widget? current_widget = widget;
			while (current_widget != null && current_widget != viewport_child) {
				Gdk.Rectangle widget_alloc;
				current_widget.get_allocation(out widget_alloc);
				y_viewport += widget_alloc.y;
				current_widget = current_widget.get_parent();
			}
			double y_content = y_viewport + vadjustment.value;

			// Scroll so the top of the widget is 20px below the top of the viewport
			double target = y_content - 20.0;
			double max_val = double.max(vadjustment.lower, vadjustment.upper - vadjustment.page_size);
			vadjustment.value = target.clamp(vadjustment.lower, max_val);
			GLib.debug("scroll_to: y_viewport=%.0f y_content=%.0f target=%.0f -> value=%.0f",
				y_viewport, y_content, target, vadjustment.value);
		}
		
		/**
		 * Shows the Add Model dialog.
		 */
		private void show_add_model_dialog()
		{
			// Create dialog if it doesn't exist
			if (this.add_model_dialog == null) {
				this.add_model_dialog = new AddModelDialog(this.dialog);
			}
			
			this.add_model_dialog.load.begin((obj, res) => {
				try {
					this.add_model_dialog.load.end(res);
					this.add_model_dialog.present(this.dialog);
				} catch (GLib.Error e) {
					GLib.warning("Failed to load AddModelDialog: %s", e.message);
				}
			});
		}
		

	}
}
