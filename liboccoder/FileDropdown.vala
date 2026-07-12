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

namespace OLLMcoder
{
	/**
	 * Searchable dropdown widget for selecting files.
	 * 
	 * Wraps Gtk.DropDown and adds search/filter functionality.
	 * V2: paged {@link OLLMfiles.ProjectFiles} via ''Folder.fetch_files'' RPC.
	 */
	public class FileDropdown : SearchableDropdown
	{
		private OLLMfiles.ProjectFiles project_files;
		private Gtk.ScrolledWindow scrolled_window;
		private Gtk.Label loading_label;
		private uint search_debounce_id = 0;
		
		/**
		 * Switch project and load the first file page from the daemon.
		 *
		 * @param project Active project folder
		 */
		public async void update_project(OLLMfiles.Folder project)
		{
			this.project_files = new OLLMfiles.ProjectFiles(project);
			this.set_item_model(this.project_files);
			this.project_files.notify["loading"].connect(() => {
				this.loading_label.visible = this.project_files.loading;
			});
			yield this.refresh();
		}
		
		/**
		 * Emitted when file selection changes.
		 */
		public signal void file_selected(OLLMfiles.File? file);
		
		/**
		 * Constructor.
		 */
		public FileDropdown()
		{
			base();
			this.placeholder_text = "Search files...";

			var popup_wrapper = this.popup.child as Gtk.Box;
			this.scrolled_window = popup_wrapper.get_first_child() as Gtk.ScrolledWindow;
			this.scrolled_window.vexpand = true;
			this.scrolled_window.hexpand = true;
			this.loading_label = new Gtk.Label("Loading…") {
				visible = false,
				margin_top = 4,
				margin_bottom = 4,
				halign = Gtk.Align.CENTER
			};
			popup_wrapper.append(this.loading_label);

			this.scrolled_window.vadjustment.changed.connect(() => {
				if (this.project_files.loading) {
					return;
				}
				if (this.project_files.offset >= this.project_files.total) {
					return;
				}
				var adj = this.scrolled_window.vadjustment;
				if (adj.value < adj.upper - adj.page_size - 48.0) {
					return;
				}
				this.project_files.load_more.begin();
			});
		}
		
		/**
		 * Reload the first browse page from {@link ProjectFiles.refresh}.
		 */
		public async void refresh()
		{
			yield this.project_files.refresh("");
			this.entry.text = "";
		}
		
		/**
		 * Set the item model using a ListModel directly (for ProjectFiles).
		 */
		private void set_item_model(GLib.ListModel model)
		{
			// Pass-through filter — search/sort on daemon; keeps base popup logic
			this.filtered_items = new Gtk.FilterListModel(
				model,
				new Gtk.CustomFilter((item) => {
					return true;
				})
			);

			this.selection = new Gtk.SingleSelection(this.filtered_items) {
				autoselect = false,
				can_unselect = true,
				selected = Gtk.INVALID_LIST_POSITION
			};
			// Disabled: Don't monitor selection changes - only trigger actions when popup closes
			// this.selection.notify["selected"].connect(() => {
			// 	this.on_selection_changed();
			// });
			
			// Update list view with new selection model
			this.list.model = this.selection;
		}
		
		protected override string get_filter_property()
		{
			return "display_name";
		}
		
		protected override string get_label_property()
		{
			// FileDropdown uses display_with_indicators (includes status indicators like ✓)
			return "display_with_indicators";
		}
		
		protected override string get_tooltip_property()
		{
			// Not used since we override create_factory, but required by abstract method
			return "path";
		}
		
		/**
		 * Override create_factory to add icons for open status and file type.
		 */
		protected override Gtk.ListItemFactory create_factory()
		{
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null) {
					return;
				}
				
				// Create horizontal box for icon and label
				var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5) {
					margin_start = 5,
					margin_end = 5
				};
				
				// CSS classes (including oc-file-item and oc-recent) will be set via display_css binding
				
				// Icon for file type
				var file_icon = new Gtk.Image() {
					visible = true
				};
				
				// Icon for open status
				var open_icon = new Gtk.Image.from_icon_name("document-open") {
					visible = false,
					tooltip_text = "Open file"
				};
				
				// Label for file name (with pango markup support)
				var label = new Gtk.Label("") {
					halign = Gtk.Align.START,
					hexpand = true,
					use_markup = true,
					ellipsize = Pango.EllipsizeMode.END  // Truncate long filenames with "..."
				};
				
				box.append(file_icon);
				box.append(open_icon);
				box.append(label);
				
				list_item.set_data<Gtk.Image>("file_icon", file_icon);
				list_item.set_data<Gtk.Image>("open_icon", open_icon);
				list_item.set_data<Gtk.Label>("label", label);
				list_item.child = box;
			});
			
			factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				
				var project_file = list_item.item as OLLMfiles.ProjectFile;
				if (project_file == null) {
					GLib.debug(
						"list bind skipped type=%s",
						list_item.item.get_type().name()
					);
					return;
				}
				
				var file_icon = list_item.get_data<Gtk.Image>("file_icon");
				var open_icon = list_item.get_data<Gtk.Image>("open_icon");
				var label = list_item.get_data<Gtk.Label>("label");
				
				// Bind properties
				if (label != null) {
					project_file.bind_property("display_with_indicators", 
						label, "label", BindingFlags.SYNC_CREATE);
				}
				
				if (file_icon != null) {
					project_file.bind_property("icon_name", 
						file_icon, "icon-name", BindingFlags.SYNC_CREATE);
				}
				
				if (open_icon != null) {
					project_file.bind_property("is_active", 
						open_icon, "visible", BindingFlags.SYNC_CREATE);
				}
				
				// Bind CSS classes for recent files using display_css property
				var box = list_item.child as Gtk.Box;
				if (box != null) {
					project_file.bind_property("display_css",
						box, "css-classes", BindingFlags.SYNC_CREATE);
				}
			});
			
			factory.unbind.connect((item) => {
				// Property bindings are automatically cleaned up when objects are destroyed
			});
			
			return factory;
		}
		
		/**
		 * Debounced server search via {@link ProjectFiles.refresh}.
		 */
		protected override void on_entry_changed()
		{
			var search_text = this.entry.text;

			if (this.search_debounce_id != 0) {
				GLib.Source.remove(this.search_debounce_id);
				this.search_debounce_id = 0;
			}

			if (search_text == "") {
				this.entry.placeholder_text = this.placeholder_text;
				this.search_debounce_id = GLib.Timeout.add(500, () => {
					this.search_debounce_id = 0;
					this.project_files.refresh.begin("");
					return false;
				});
				if (this.popup.visible) {
					this.set_popup_visible(false);
				}
				return;
			}

			this.entry.placeholder_text = "";
			this.entry.set_position(-1);
			this.entry.select_region(-1, -1);

			this.search_debounce_id = GLib.Timeout.add(500, () => {
				this.search_debounce_id = 0;
				GLib.debug(
					"debounce fire query=%s filtered=%u popup=%s",
					search_text,
					this.filtered_items.get_n_items(),
					this.popup.visible.to_string()
				);
				this.set_popup_visible(true);
				this.project_files.refresh.begin(search_text, (obj, res) => {
					this.project_files.refresh.end(res);
					GLib.debug(
						"debounce refresh done entry=%s filtered=%u list=%u popup=%s",
						this.entry.text,
						this.filtered_items.get_n_items(),
						this.project_files.get_n_items(),
						this.popup.visible.to_string()
					);
					if (this.entry.text != search_text) {
						return;
					}
					GLib.Idle.add(() => {
						var adj = this.scrolled_window.vadjustment;
						GLib.debug(
							"popup after refresh filtered=%u popup=%s scroll_upper=%.0f page=%.0f scrolled_h=%d popup_h=%d",
							this.filtered_items.get_n_items(),
							this.popup.visible.to_string(),
							adj.upper,
							adj.page_size,
							this.scrolled_window.get_height(),
							this.popup.get_height()
						);
						return false;
					});
				});
				return false;
			});
		}
		
		/**
		 * Override set_popup_visible to reset search and reload browse page on close.
		 */
		protected new void set_popup_visible(bool visible)
		{
			if (visible) {
				GLib.debug(
					"file popup show filtered=%u list=%u entry=%s",
					this.filtered_items.get_n_items(),
					this.project_files.get_n_items(),
					this.entry.text
				);
			}
			if (!visible) {
				if (this.search_debounce_id != 0) {
					GLib.Source.remove(this.search_debounce_id);
					this.search_debounce_id = 0;
				}
				this.entry.text = "";
				this.project_files.refresh.begin("");
			}

			base.set_popup_visible(visible);
		}
		
		protected override void on_selected()
		{
			var project_file = this.selection.selected_item as OLLMfiles.ProjectFile;
			var file = project_file != null ? project_file.file : null;

			this.file_selected(file);
			this.entry.text = "";
			if (file == null) {
				this.placeholder_text = "Search files...";
				return;
			}

			this.placeholder_text = file.display_name;
		}
	}
}
