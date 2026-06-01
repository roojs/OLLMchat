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
		private OLLMchat.Settings.SearchResults search_results;
		private Gtk.StringList connection_list;
		private GLib.ListStore size_list_store;
		private Gee.ArrayList<string> connection_urls;
		public MainDialog dialog { get; construct; }
		private OllamaWeb.Model selected_model { get; set; default = new OllamaWeb.Model(); }

		private Gtk.SortListModel sorted_models;
		private Gtk.SingleSelection selection;
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
			this.size_list_store = new GLib.ListStore(typeof(OllamaWeb.ModelVariant));
			this.size_dropdown = new Gtk.DropDown(this.size_list_store, null) {
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			
			// Create factory for rendering OllamaWeb.ModelVariant objects
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
				var tag = list_item.item as OllamaWeb.ModelVariant;
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
				
				if (this.selected_model.slug == "") {
					return;
				}
				var model_name = this.selected_model.name;

				var size_index = this.size_dropdown.selected;
				if (size_index != Gtk.INVALID_LIST_POSITION &&
				    (int)size_index < this.size_list_store.get_n_items()) {
					var tag = this.size_list_store.get_item((uint)size_index) as OllamaWeb.ModelVariant;
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
			
			this.search_results = new OLLMchat.Settings.SearchResults(this.dialog.app.data_dir);
			this.closed.connect(() => {
				this.search_results.cancel();
			});
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
		
			this.setup_model_chain();
		}

		/**
		 * Focus the model search entry (call after {@link Adw.PreferencesDialog.present}).
		 */
		public void focus_model_search()
		{
			GLib.Idle.add(() => {
				this.model_pulldown.grab_focus();
				return false;
			});
		}
		
		/**
		 * Sets up the model chain (filter, sort, selection) and factory for the model pulldown.
		 */
		private void setup_model_chain()
		{
			this.model_sorter = new Gtk.CustomSorter((a, b) => {
				var search_text = this.model_pulldown.get_search_text();
				var name_a = (a as OllamaWeb.Model).name.down();
				var name_b = (b as OllamaWeb.Model).name.down();

				if (search_text == "") {
					if (name_a < name_b) {
						return Gtk.Ordering.SMALLER;
					}
					if (name_a > name_b) {
						return Gtk.Ordering.LARGER;
					}
					return Gtk.Ordering.EQUAL;
				}

				var search_lower = search_text.down();
				var a_starts = name_a.has_prefix(search_lower);
				var b_starts = name_b.has_prefix(search_lower);
				if (a_starts && b_starts) {
					if (name_a.length != name_b.length) {
						return name_a.length < name_b.length
							? Gtk.Ordering.SMALLER
							: Gtk.Ordering.LARGER;
					}
					if (name_a < name_b) {
						return Gtk.Ordering.SMALLER;
					}
					if (name_a > name_b) {
						return Gtk.Ordering.LARGER;
					}
					return Gtk.Ordering.EQUAL;
				}
				if (a_starts != b_starts) {
					return a_starts ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
				}

				var a_contains = name_a.contains(search_lower);
				var b_contains = name_b.contains(search_lower);
				if (a_contains && b_contains) {
					if (name_a < name_b) {
						return Gtk.Ordering.SMALLER;
					}
					if (name_a > name_b) {
						return Gtk.Ordering.LARGER;
					}
					return Gtk.Ordering.EQUAL;
				}
				if (a_contains != b_contains) {
					return a_contains ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
				}

				if (name_a < name_b) {
					return Gtk.Ordering.SMALLER;
				}
				if (name_a > name_b) {
					return Gtk.Ordering.LARGER;
				}
				return Gtk.Ordering.EQUAL;
			});

			this.sorted_models = new Gtk.SortListModel(this.search_results, this.model_sorter);
			
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
				
				var model = list_item.item as OllamaWeb.Model;
				var label = list_item.get_data<Gtk.Label>("label");
				if (model == null || label == null) {
					return;
				}
				
				label.label = model.list_markup;
				list_item.set_data<ulong>(
					"markup_notify",
					model.notify["list_markup"].connect(() => {
						label.label = model.list_markup;
					})
				);
			});
			factory.unbind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				var model = list_item.item as OllamaWeb.Model;
				var notify_id = list_item.get_data<ulong>("markup_notify");
				if (model != null && notify_id != 0) {
					model.disconnect(notify_id);
				}
			});
			
			// Set model and factory on list view
			this.model_pulldown.list.model = this.selection;
			this.model_pulldown.list.factory = factory;
			this.search_results.bind_property(
				"loading",
				this.model_pulldown,
				"search-loading",
				BindingFlags.SYNC_CREATE
			);
			
			this.model_pulldown.search_changed.connect((search_text) => {
				this.search_results.queue_search(search_text);
				this.model_sorter.changed(Gtk.SorterChange.DIFFERENT);
				if (search_text == "") {
					this.model_pulldown.set_popup_visible(false);
					return;
				}
				this.model_pulldown.set_popup_visible(true, true);
			});
			this.search_results.items_changed.connect(() => {
				if (this.model_pulldown.get_search_text() == "") {
					return;
				}
				GLib.Idle.add(() => {
					if (this.model_pulldown.get_search_text() == "") {
						return false;
					}
					this.model_pulldown.set_popup_visible(true);
					if (this.model_pulldown.list.model != null
					    && this.model_pulldown.list.model.get_n_items() > 0) {
						var scroll = new Gtk.ScrollInfo();
						this.model_pulldown.list.scroll_to(0, Gtk.ListScrollFlags.NONE, scroll);
					}
					return false;
				});
			});

			this.model_pulldown.item_selected.connect((position) => {
				if (position == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				var model = this.selection.get_item(this.selection.selected) as OllamaWeb.Model;
				if (model == null || model.slug == "") {
					return;
				}
				this.model_pulldown.placeholder_text = model.name;
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
				this.selected_model.slug = "";
				this.size_row.visible = false;
				return;
			}

			this.selected_model = this.selection.get_item(selected_pos) as OllamaWeb.Model;
			if (this.selected_model.slug == "") {
				this.size_row.visible = false;
				return;
			}

			this.size_list_store.remove_all();

			var sorted_tags = new Gee.ArrayList<OllamaWeb.ModelVariant>();
			sorted_tags.add_all(this.selected_model.tags);
			sorted_tags.sort((a, b) => {
				var a_cloud = a.name.down().contains("cloud");
				var b_cloud = b.name.down().contains("cloud");
				if (a_cloud && !b_cloud) {
					return 1;
				}
				if (!a_cloud && b_cloud) {
					return -1;
				}
				if (a_cloud && b_cloud) {
					return GLib.strcmp(a.name, b.name);
				}
				var a_size = a.parse_size_gb();
				var b_size = b.parse_size_gb();
				if (a_size == b_size) {
					return GLib.strcmp(a.name, b.name);
				}
				if (a_size < b_size) {
					return -1;
				}
				return 1;
			});

			uint default_index = 0;
			double best_size_gb = -1;
			uint index = 0;
			foreach (var tag_obj in sorted_tags) {
				this.size_list_store.append(tag_obj);
				var size_gb = tag_obj.parse_size_gb();
				if (size_gb >= 0 && size_gb <= 100.0 && size_gb > best_size_gb) {
					best_size_gb = size_gb;
					default_index = index;
				}
				index++;
			}

			this.size_dropdown.selected = default_index;
			this.size_row.visible = true;
		}
	}
}

