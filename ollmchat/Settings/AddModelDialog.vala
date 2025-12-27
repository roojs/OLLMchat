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
	 * Dialog for adding models by selecting from available models list.
	 * 
	 * Uses AdwPreferencesDialog with connection selection and model search.
	 * 
	 * @since 1.3.4
	 */
	public class AddModelDialog : Adw.PreferencesDialog
	{
		private Gtk.DropDown connection_dropdown;
		private SearchablePulldown model_pulldown;
		private Gtk.Button start_download_button;
		private Adw.ActionRow connection_row;
		private Adw.ActionRow model_row;
		private Adw.PreferencesGroup group;
		private AvailableModels available_models;
		private Gtk.StringList connection_list;
		private Gee.ArrayList<string> connection_urls;
		private Config2 config;
		private string data_dir;
		
		// Model chain for SearchablePulldown
		private Gtk.FilterListModel filtered_models;
		private Gtk.SortListModel sorted_models;
		private Gtk.SingleSelection selection;
		private Gtk.CustomFilter model_filter;
		private Gtk.CustomSorter model_sorter;
		private Gtk.PropertyExpression display_expr;
		
		/**
		 * The selected connection URL (set when dialog is used).
		 */
		public string? selected_connection_url { get; private set; }
		
		/**
		 * The selected model name (set when dialog is used).
		 */
		public string? selected_model_name { get; private set; }
		
		/**
		 * Creates a new AddModelDialog.
		 * 
		 * @param config Configuration object (contains connections map)
		 * @param data_dir Directory where model cache is stored
		 */
		public AddModelDialog(Config2 config, string data_dir)
		{
			this.config = config;
			this.data_dir = data_dir;
			
			this.set_content_height(400);
			this.set_content_width(800);
			
			// Create preferences page
			var page = new Adw.PreferencesPage();
			
			// Create preferences group
			this.group = new Adw.PreferencesGroup() {
				title = "Add Model",
				description = "Select a connection and model to download"
			};
			
			// Initialize connection list (will be populated in load())
			this.connection_urls = new Gee.ArrayList<string>();
			this.connection_list = new Gtk.StringList(null);
			
			// Connection row
			this.connection_dropdown = new Gtk.DropDown(this.connection_list, null);
			this.connection_row = new Adw.ActionRow() {
				title = "Connection",
				subtitle = "Select the server connection to use"
			};
			this.connection_row.add_suffix(this.connection_dropdown);
			this.group.add(this.connection_row);
			
			// Model row
			this.model_pulldown = new SearchablePulldown() {
				placeholder_text = "Search models (e.g., llama3:8b 4.7GB)"
			};
			this.model_row = new Adw.ActionRow() {
				title = "Model",
				subtitle = "Search and select a model to download"
			};
			this.model_row.add_suffix(this.model_pulldown);
			this.group.add(this.model_row);
			
			// Add group to page
			page.add(this.group);
			
			// Create Start Download button
			this.start_download_button = new Gtk.Button.with_label("Start Download") {
				css_classes = {"suggested-action"}
			};
			
			// For now: just closes the dialog (background pull not implemented yet)
			this.start_download_button.clicked.connect(() => {
				// Get selected connection URL
				var selected_index = this.connection_dropdown.selected;
				if (selected_index != Gtk.INVALID_LIST_POSITION && 
				    (int)selected_index < this.connection_urls.size) {
					this.selected_connection_url = this.connection_urls.get((int)selected_index);
				}
				
				// Get selected model
				var selected_model = this.model_pulldown.get_selected_object() as AvailableModel;
				if (selected_model != null) {
					this.selected_model_name = selected_model.name;
				}
				
				// Close dialog
				this.force_close();
			});
			
			// Add Start Download button to page footer
			var footer = new Adw.PreferencesGroup();
			footer.add(this.start_download_button);
			page.add(footer);
			
			// Add page to dialog
			this.add(page);
			
			// Create AvailableModels instance (will be loaded in load())
			this.available_models = new AvailableModels(this.data_dir);
		}
		
		/**
		 * Loads connections and models asynchronously.
		 */
		public async void load()
		{
		
			this.connection_urls.clear();
			
			// Create new StringList (StringList doesn't have remove_all)
			this.connection_list = new Gtk.StringList(null);
			
			int default_index = 0;
			int index = 0;
			foreach (var entry in this.config.connections.entries) {
				this.connection_urls.add(entry.key);
				// Display format: "name (url)" or just "name" if name is set
				var display_name = entry.value.name != "" ? 
					entry.value.name + " (" + entry.key + ")" : 
					entry.key;
				this.connection_list.append(display_name);
				
				// Track default connection index
				if (entry.value.is_default) {
					default_index = index;
				}
				index++;
			}
			
			// Update dropdown model
			this.connection_dropdown.model = this.connection_list;
			
			// Set default to 'default' connection
			this.connection_dropdown.selected = default_index;
		
			try {
				yield this.available_models.load();
				
				// Set up model chain: available_models -> filtered -> sorted -> selection
				this.setup_model_chain();
				
				GLib.debug("Loaded %u models into AddModelDialog", this.available_models.get_n_items());
			} catch (GLib.Error e) {
				GLib.warning("Failed to load available models: %s", e.message);
			}
		}
		
		/**
		 * Sets up the model chain (filter, sort, selection) and factory for the model pulldown.
		 */
		private void setup_model_chain()
		{
			// Create property expression for display property
			this.display_expr = new Gtk.PropertyExpression(
				typeof(AvailableModel), null, "display"
			);
			
			// Create filter that uses search text
			this.model_filter = new Gtk.CustomFilter((item) => {
				if (item == null) {
					return true;
				}
				var search_text = this.model_pulldown.get_search_text();
				if (search_text == "") {
					return true;
				}
				var value = this.display_expr.evaluate(item);
				if (value == null || !value.holds(typeof(string))) {
					return true;
				}
				var display_str = value.get_string();
				return display_str.down().contains(search_text.down());
			});
			
			// Create filtered model
			this.filtered_models = new Gtk.FilterListModel(
				this.available_models, this.model_filter);
			
			// Create sorter that prioritizes items starting with search term, then sorts alphabetically
			this.model_sorter = new Gtk.CustomSorter((a, b) => {
				if (a == null || b == null) {
					return Gtk.Ordering.EQUAL;
				}
				
				var value_a = this.display_expr.evaluate(a);
				var value_b = this.display_expr.evaluate(b);
				if (value_a == null || value_b == null || 
				    !value_a.holds(typeof(string)) || !value_b.holds(typeof(string))) {
					return Gtk.Ordering.EQUAL;
				}
				
				var str_a = value_a.get_string().down();
				var str_b = value_b.get_string().down();
				var search_text = this.model_pulldown.get_search_text();
				
				// If searching, prioritize items starting with search term
				if (search_text != "") {
					var search_lower = search_text.down();
					var a_starts_with = str_a.has_prefix(search_lower);
					var b_starts_with = str_b.has_prefix(search_lower);
					
					if (a_starts_with != b_starts_with) {
						return a_starts_with ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
					}
				}
				
				// Sort alphabetically
				if (str_a < str_b) {
					return Gtk.Ordering.SMALLER;
				} else if (str_a > str_b) {
					return Gtk.Ordering.LARGER;
				}
				return Gtk.Ordering.EQUAL;
			});
			
			// Create sorted model
			this.sorted_models = new Gtk.SortListModel(this.filtered_models, this.model_sorter);
			
			// Create selection model
			this.selection = new Gtk.SingleSelection(this.sorted_models) {
				autoselect = false,
				can_unselect = true,
				selected = Gtk.INVALID_LIST_POSITION
			};
			
			// Create factory with property binding
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null) {
					return;
				}
				
				var label = new Gtk.Label("") {
					halign = Gtk.Align.START
				};
				list_item.set_data<Gtk.Label>("label", label);
				list_item.child = label;
			});
			
			factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				
				var model = list_item.item as AvailableModel;
				var label = list_item.get_data<Gtk.Label>("label");
				if (model == null || label == null) {
					return;
				}
				
				// Bind display property to label
				model.bind_property("display", label, "label", BindingFlags.SYNC_CREATE);
				model.bind_property("display", label, "tooltip-text", BindingFlags.SYNC_CREATE);
			});
			
			// Set model and factory on list view
			this.model_pulldown.list.model = this.selection;
			this.model_pulldown.list.factory = factory;
			
			// Connect to search_changed signal to update filter
			this.model_pulldown.search_changed.connect((search_text) => {
				this.model_filter.changed(Gtk.FilterChange.DIFFERENT);
				this.model_sorter.changed(Gtk.SorterChange.DIFFERENT);
				
				// Show popup if there are filtered items
				if (search_text != "" && this.sorted_models.get_n_items() > 0) {
					this.model_pulldown.set_popup_visible(true);
				} else if (search_text == "") {
					this.model_pulldown.set_popup_visible(false);
				}
			});
		}
	}
}

