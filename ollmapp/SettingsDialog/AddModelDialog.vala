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
		private Gtk.DropDown size_dropdown;
		private Gtk.Button start_download_button;
		private Adw.ActionRow connection_row;
		private Adw.ActionRow model_row;
		private Adw.ActionRow size_row;
		private Adw.PreferencesGroup group;
		private OLLMchat.Settings.AvailableModels available_models;
		private Gtk.StringList connection_list;
		private GLib.ListStore size_list_store;
		private Gee.ArrayList<string> connection_urls;
		public MainDialog dialog { get; construct; }
		private OLLMchat.Settings.AvailableModel? selected_model = null;
		
		// Model chain for SearchablePulldown
		private Gtk.FilterListModel filtered_models;
		private Gtk.SortListModel sorted_models;
		private Gtk.SingleSelection selection;
		private Gtk.StringFilter model_filter;
		private Gtk.CustomSorter model_sorter;
		
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
		 * @param dialog Parent SettingsDialog (provides app with config and data_dir)
		 */
		public AddModelDialog(MainDialog dialog)
		{
			Object(dialog: dialog);
			
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
			
			// Connection row: factory avoids PropertyExpression on gchararray (GTK does not support it)
		 
			this.connection_dropdown = new Gtk.DropDown(this.connection_list, null) {
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
 			this.connection_row = new Adw.ActionRow() {
				title = "OpenAPI / Ollama server",
				subtitle = "Select the server connection to use"
			};
			this.connection_row.add_suffix(this.connection_dropdown);
			this.group.add(this.connection_row);
			
			// Model row
			this.model_pulldown = new SearchablePulldown() {
				placeholder_text = "Search models (e.g., gemma3, qwen3)"
			};
			this.model_row = new Adw.ActionRow() {
				title = "Model",
				subtitle = "Search and select a model to download"
			};
			this.model_row.add_suffix(this.model_pulldown);
			this.group.add(this.model_row);
			
			// Size row (hidden until model is selected)
			this.size_list_store = new GLib.ListStore(typeof(OLLMchat.Settings.ModelTag));
			this.size_dropdown = new Gtk.DropDown(this.size_list_store, null) {
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			
			// Create factory for rendering OLLMchat.Settings.ModelTag objects
			var size_factory = new Gtk.SignalListItemFactory();
			size_factory.setup.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null) {
					return;
				}
				var label = new Gtk.Label("") {
					halign = Gtk.Align.START,
					use_markup = true
				};
				list_item.set_data<Gtk.Label>("label", label);
				list_item.child = label;
			});
			size_factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				var tag = list_item.item as OLLMchat.Settings.ModelTag;
				var label = list_item.get_data<Gtk.Label>("label");
				
				tag.bind_property("dropdown_markup", label, "label", BindingFlags.SYNC_CREATE);
			});
			this.size_dropdown.factory = size_factory;
			
			this.size_row = new Adw.ActionRow() {
				title = "Size",
				subtitle = "Select the model size variant",
				visible = false
			};
			this.size_row.add_suffix(this.size_dropdown);
			this.group.add(this.size_row);
			
			// Add group to page
			page.add(this.group);
			
			// Create Start Download button
			this.start_download_button = new Gtk.Button.with_label("Start Download") {
				css_classes = {"suggested-action"}
			};
			
			// Start download button handler
			this.start_download_button.clicked.connect(() => {
				// Get selected connection URL
				var selected_index = this.connection_dropdown.selected;
				if (selected_index == Gtk.INVALID_LIST_POSITION || 
				    (int)selected_index >= this.connection_urls.size) {
					return; // No connection selected
				}
				var connection_url = this.connection_urls.get((int)selected_index);
				
				// Get connection object from config
				if (!this.dialog.app.config.connections.has_key(connection_url)) {
					GLib.warning("Connection not found: %s", connection_url);
					return;
				}
				var connection = this.dialog.app.config.connections.get(connection_url);
				
				// Get selected model and size
				if (this.selected_model == null) {
					return; // No model selected
				}
				var model_name = this.selected_model.name;
				
				// Append size tag if one is selected
				var size_index = this.size_dropdown.selected;
				if (size_index != Gtk.INVALID_LIST_POSITION && 
				    (int)size_index < this.size_list_store.get_n_items()) {
					var tag = this.size_list_store.get_item((uint)size_index) as OLLMchat.Settings.ModelTag;
					if (tag != null) {
						model_name = model_name + ":" + tag.name;
					}
				}
				
				// Start pull operation
				this.dialog.pull_manager.start_pull(model_name, connection);
				// this.dialog.pull_manager.start_pull(model_name, connection);
				
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
			this.available_models = new OLLMchat.Settings.AvailableModels(this.dialog.app.data_dir);
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
			foreach (var entry in this.dialog.app.config.connections.entries) {
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
			// Create string filter using name property only (not description)
			this.model_filter = new Gtk.StringFilter(
				new Gtk.PropertyExpression(typeof(OLLMchat.Settings.AvailableModel), null, "name")
			) {
				match_mode = Gtk.StringFilterMatchMode.SUBSTRING,
				ignore_case = true
			};
			
			// Create filtered model
			this.filtered_models = new Gtk.FilterListModel(
				this.available_models, this.model_filter);
			
			// Create sorter that prioritizes items starting with search term (by length, then alphabetical),
			// then items containing search term (alphabetical)
			this.model_sorter = new Gtk.CustomSorter((a, b) => {
				var search_text = this.model_pulldown.get_search_text();
				
				// If not searching, sort alphabetically
				if (search_text == "") {
					var name_a = (a as OLLMchat.Settings.AvailableModel).name.down();
					var name_b = (b as OLLMchat.Settings.AvailableModel).name.down();
					if (name_a < name_b) {
						return Gtk.Ordering.SMALLER;
					} else if (name_a > name_b) {
						return Gtk.Ordering.LARGER;
					}
					return Gtk.Ordering.EQUAL;
				}
				
				var search_lower = search_text.down();
				var name_a = (a as OLLMchat.Settings.AvailableModel).name.down();
				var name_b = (b as OLLMchat.Settings.AvailableModel).name.down();
				var a_starts_with = name_a.has_prefix(search_lower);
				var b_starts_with = name_b.has_prefix(search_lower);
				var a_contains = name_a.contains(search_lower);
				var b_contains = name_b.contains(search_lower);
				
				// Priority 1: Items that start with search term
				if (a_starts_with && b_starts_with) {
					// Both start with search term: sort by length first, then alphabetically
					var len_a = name_a.length;
					var len_b = name_b.length;
					if (len_a != len_b) {
						return len_a < len_b ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
					}
					// Same length, sort alphabetically
					if (name_a < name_b) {
						return Gtk.Ordering.SMALLER;
					} else if (name_a > name_b) {
						return Gtk.Ordering.LARGER;
					}
					return Gtk.Ordering.EQUAL;
				}
				
				// Priority 2: One starts with, one doesn't - prioritize the one that starts with
				if (a_starts_with != b_starts_with) {
					return a_starts_with ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
				}
				
				// Priority 3: Items that contain search term (but don't start with it)
				if (a_contains && b_contains) {
					// Both contain: sort alphabetically
					if (name_a < name_b) {
						return Gtk.Ordering.SMALLER;
					} else if (name_a > name_b) {
						return Gtk.Ordering.LARGER;
					}
					return Gtk.Ordering.EQUAL;
				}
				
				// Priority 4: One contains, one doesn't - prioritize the one that contains
				if (a_contains != b_contains) {
					return a_contains ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
				}
				
				// Priority 5: Neither contains - sort alphabetically
				if (name_a < name_b) {
					return Gtk.Ordering.SMALLER;
				} else if (name_a > name_b) {
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
			
			// Create factory with pango markup
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null) {
					return;
				}
				
				var label = new Gtk.Label("") {
					halign = Gtk.Align.START,
					valign = Gtk.Align.START,
					wrap = true,
					wrap_mode = Pango.WrapMode.WORD,
					justify = Gtk.Justification.LEFT,
					use_markup = true,
					selectable = false,
					margin_start = 0,
					margin_end = 0,
					xalign = 0.0f
				};
				list_item.set_data<Gtk.Label>("label", label);
				list_item.child = label;
			});
			
			factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				
				var model = list_item.item as OLLMchat.Settings.AvailableModel;
				var label = list_item.get_data<Gtk.Label>("label");
				if (model == null || label == null) {
					return;
				}
				
				model.bind_property("list_markup", label, "label", BindingFlags.SYNC_CREATE);
			});
			
			// Set model and factory on list view
			this.model_pulldown.list.model = this.selection;
			this.model_pulldown.list.factory = factory;
			
			// Connect to search_changed signal to update filter
			this.model_pulldown.search_changed.connect((search_text) => {
				// Update string filter search text (matches pattern from SearchableDropdown)
				this.model_filter.search = search_text;
				this.model_sorter.changed(Gtk.SorterChange.DIFFERENT);
				
				// Show popup if there are filtered items
				if (search_text != "" && this.sorted_models.get_n_items() > 0) {
					this.model_pulldown.set_popup_visible(true);
				} else if (search_text == "") {
					this.model_pulldown.set_popup_visible(false);
				}
			});
			
			// Connect to item_selected signal from pulldown - only fires on actual click/Enter
			// Don't use selection_changed as that fires on keyboard navigation too
			this.model_pulldown.item_selected.connect((position) => {
				// Get the selected model from the position in the sorted model
				if (position == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				
				// Get model from sorted_models at the position passed
				var model_from_sorted = this.sorted_models.get_item(position) as OLLMchat.Settings.AvailableModel;
				if (model_from_sorted == null) {
					return;
				}
				
				// Get model from selection at selection.selected
				var selection_pos = this.selection.selected;
				var model_from_selection = (selection_pos != Gtk.INVALID_LIST_POSITION) ? 
					this.selection.get_item(selection_pos) as OLLMchat.Settings.AvailableModel : null;
				
				// Debug: show the 3 model names
				GLib.debug("model_from_sorted: %s", model_from_sorted.name);
				GLib.debug("model_from_selection: %s", model_from_selection != null ? model_from_selection.name : "null");
				GLib.debug("selected_model: %s", this.selected_model != null ? this.selected_model.name : "null");
				
				// Use model_from_selection (the correct one) for placeholder
				if (model_from_selection != null) {
					this.model_pulldown.placeholder_text = model_from_selection.name;
				}
				
				// Update size dropdown
				this.update_size_dropdown();
			});
		}
		
		/**
		 * Updates the size dropdown based on the selected model.
		 */
		private void update_size_dropdown()
		{
			var selected_pos = this.selection.selected;
			if (selected_pos == Gtk.INVALID_LIST_POSITION) {
				// No model selected, hide size row
				this.selected_model = null;
				this.size_row.visible = false;
				return;
			}
			
			// Get selected model from selection model (which wraps sorted_models)
			this.selected_model = this.selection.get_item(selected_pos) as OLLMchat.Settings.AvailableModel;
			if (this.selected_model == null) {
				// No model available, hide size row
				this.size_row.visible = false;
				return;
			}
			
			// Clear existing items
			this.size_list_store.remove_all();
			
			// Sort tags by size (cloud tags last)
			var sorted_tags = new Gee.ArrayList<OLLMchat.Settings.ModelTag>();
			sorted_tags.add_all(this.selected_model.tag_objects);
			sorted_tags.sort((a, b) => {
				// Check if either is a cloud tag
				var a_is_cloud = a.name.down().contains("cloud");
				var b_is_cloud = b.name.down().contains("cloud");
				
				// Cloud tags go last
				if (a_is_cloud && !b_is_cloud) {
					return 1; // a comes after b
				}
				if (!a_is_cloud && b_is_cloud) {
					return -1; // a comes before b
				}
				if (a_is_cloud && b_is_cloud) {
					// Both cloud - sort alphabetically
					return strcmp(a.name, b.name);
				}
				
				// Neither is cloud - sort by size
				var a_size = a.parse_size_gb();
				var b_size = b.parse_size_gb();
				
				// If sizes are equal, sort by name
				if (a_size == b_size) {
					return strcmp(a.name, b.name);
				}
				
				// Sort by size (ascending)
				if (a_size < b_size) {
					return -1;
				}
				return 1;
			});
			
			// Find default tag: largest download size <= 100GB
			OLLMchat.Settings.ModelTag? default_tag = null;
			double best_size_gb = -1;
			foreach (var tag_obj in sorted_tags) {
				var size_gb = tag_obj.parse_size_gb();
				if (size_gb >= 0 && size_gb <= 100.0 && size_gb > best_size_gb) {
					best_size_gb = size_gb;
					default_tag = tag_obj;
				}
			}
			
			// Populate size list with sorted OLLMchat.Settings.ModelTag objects and find default index
			uint default_index = 0;
			uint index = 0;
			foreach (var tag_obj in sorted_tags) {
				this.size_list_store.append(tag_obj);
				// Track index of default tag if found
				if (default_tag != null && tag_obj.name == default_tag.name) {
					default_index = index;
				}
				index++;
			}
			
			
			// Select default tag (or first one if not found)
			this.size_dropdown.selected = default_index;
			
			// Show size row
			this.size_row.visible = true;
		}
	}
}

