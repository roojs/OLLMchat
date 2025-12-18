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

namespace OLLMcoder
{
	/**
	 * Searchable dropdown widget for selecting files.
	 * 
	 * Wraps Gtk.DropDown and adds search/filter functionality.
	 * Integrates with Project to populate file list from project's project_files.
	 */
	public class FileDropdown : SearchableDropdown
	{
		private Files.Folder? current_project;
		private Gtk.SortListModel sorted_items;
		private Gtk.CustomFilter? wildcard_filter;
		
		/**
		 * Currently selected file.
		 * This is set when the popup closes and user has made a selection.
		 */
		private Files.File? _selected_file = null;
		public Files.File? selected_file {
			get { 
				return this._selected_file;
			}
		}
		
		/**
		 * Currently selected project (used to populate file list).
		 * Note: Projects are Folders with is_project = true.
		 */
		public Files.Folder? project {
			get { return this.current_project; }
			set {
				if (value != null && !value.is_project) {
					GLib.warning("FileDropdown.project set to non-project folder: %s", value.path);
					return;
				}
				this.current_project = value;
				this.refresh();
			}
		}
		
		/**
		 * Emitted when file selection changes.
		 */
		public signal void file_selected(Files.File? file);
		
		/**
		 * Constructor.
		 */
		public FileDropdown()
		{
			base();
			this.placeholder_text = "Search files...";
		}
		
		/**
		 * Refresh the file list from the current project's project_files.
		 */
		public void refresh()
		{
			if (this.current_project == null || !this.current_project.is_project) {
				// Clear by using empty store
				this.set_item_store(new GLib.ListStore(typeof(Files.ProjectFile)));
				return;
			}
			
			// Use project_files directly as the ListModel (no copying)
			this.set_item_model(this.current_project.project_files);
		}
		
		/**
		 * Set the item model using a ListModel directly (for ProjectFiles).
		 */
		private void set_item_model(GLib.ListModel model)
		{
			// Use the model directly for filtering (no copying)
			this.filtered_items = new Gtk.FilterListModel(
				model, this.string_filter);
			
			// Create custom sorter: open files first, then sort by display_name
			var sorter = new Gtk.CustomSorter((a, b) => {
				var pf_a = a as Files.ProjectFile;
				var pf_b = b as Files.ProjectFile;
				if (pf_a == null || pf_b == null) {
					return Gtk.Ordering.EQUAL;
				}
				// Sort by is_open first (open files come first)
				if (pf_a.is_open != pf_b.is_open) {
					return pf_a.is_open ? 
						Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
				}
				
				// Then sort by path
				return pf_a.file.path < pf_b.file.path ? 
					Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
			});
			
			// Create sorted model
			this.sorted_items = new Gtk.SortListModel(this.filtered_items, sorter);
			
			// Update selection model to use sorted model
			this.selection = new Gtk.SingleSelection(this.sorted_items) {
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
		
		/**
		 * Override set_item_store to add sorting (open files first, then by name).
		 */
		protected override void set_item_store(GLib.ListStore store)
		{
			base.set_item_store(store);
			
			// Create custom sorter: open files first, then sort by display_name
			var sorter = new Gtk.CustomSorter((a, b) => {
				// Sort by is_open first (open files come first)
				if (((Files.File)a).is_open != ((Files.File)b).is_open) {
					return ((Files.File)a).is_open ? 
						Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
				}
				
				// Then sort by path
				return ((Files.File)a).path < ((Files.File)b).path ? 
					Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
			});
			
			// Create sorted model
			this.sorted_items = new Gtk.SortListModel(this.filtered_items, sorter);
			
			// Update selection model to use sorted model
			this.selection = new Gtk.SingleSelection(this.sorted_items) {
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
				
				// Icon for file type
				var file_icon = new Gtk.Image() {
					visible = true
				};
				
				// Icon for open status
				var open_icon = new Gtk.Image.from_icon_name("document-open") {
					visible = false,
					tooltip_text = "Open file"
				};
				
				// Label for file name
				var label = new Gtk.Label("") {
					halign = Gtk.Align.START,
					hexpand = true
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
				
				var project_file = list_item.item as Files.ProjectFile;
				if (project_file == null) {
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
					project_file.bind_property("is_open", 
						open_icon, "visible", BindingFlags.SYNC_CREATE);
				}
			});
			
			factory.unbind.connect((item) => {
				// Property bindings are automatically cleaned up when objects are destroyed
			});
			
			return factory;
		}
		
		/**
		 * Override on_entry_changed to support wildcard filtering.
		 */
		protected override void on_entry_changed()
		{
			var search_text = this.entry.text;
			
			// Check if search text contains wildcards
			if (search_text.contains("*") || search_text.contains("?")) {
				// Use wildcard filter
				if (this.wildcard_filter == null) {
					this.wildcard_filter = new Gtk.CustomFilter((item) => {
						var project_file = item as Files.ProjectFile;
						if (project_file == null) {
							return false;
						}
						return this.match_wildcard(project_file.display_name, search_text);
					});
					
					// Combine string filter and wildcard filter
					// For now, just use wildcard filter when wildcards are present
					// TODO: Combine filters properly
				}
				// Update wildcard filter search text
				// Note: CustomFilter doesn't have a way to update, so we need to recreate
				this.wildcard_filter = new Gtk.CustomFilter((item) => {
					var project_file = item as Files.ProjectFile;
					if (project_file == null) {
						return false;
					}
					return this.match_wildcard(project_file.display_name, search_text);
				});
				
				// Replace filtered_items with wildcard filter
				this.filtered_items = new Gtk.FilterListModel(
					this.item_store, this.wildcard_filter);
			} else {
				// Use normal string filter
				this.string_filter.search = search_text;
				this.filtered_items = new Gtk.FilterListModel(
					this.item_store, this.string_filter);
			}
			
			// Recreate sorted model with new filtered model
			if (this.sorted_items != null) {
				var sorter = this.sorted_items.sorter;
				this.sorted_items = new Gtk.SortListModel(this.filtered_items, sorter);
				this.selection.model = this.sorted_items;
			}
			
			// Don't automatically show popover - only update filter
			// Popup should only be shown when explicitly requested (e.g., clicking arrow)
		}
		
		/**
		 * Match a string against a wildcard pattern.
		 */
		private bool match_wildcard(string text, string pattern)
		{
			// Escape special regex characters first (except * and ? which are wildcards)
			var escaped = pattern
				.replace("\\", "\\\\")
				.replace("^", "\\^")
				.replace("$", "\\$")
				.replace(".", "\\.")
				.replace("[", "\\[")
				.replace("]", "\\]")
				.replace("|", "\\|")
				.replace("(", "\\(")
				.replace(")", "\\)")
				.replace("{", "\\{")
				.replace("}", "\\}")
				.replace("+", "\\+");
			
			// Then replace wildcards with regex equivalents
			var regex_pattern = "^" + escaped
				.replace("?", ".")
				.replace("*", ".*") + "$";
			
			try {
				var regex = new GLib.Regex(regex_pattern, 
					GLib.RegexCompileFlags.CASELESS);
				return regex.match(text);
			} catch (GLib.RegexError e) {
				return false;
			}
		}
		
		protected override void on_selected()
		{
			// Get the selected item from the selection model
			var project_file = this.selection.selected_item as Files.ProjectFile;
			var file = project_file != null ? project_file.file : null;
			
			// Update the stored selected file
			this._selected_file = file;
			
			// Emit signal with the selected file
			this.file_selected(this._selected_file);
			
			if (this._selected_file != null) {
				// Clear entry text so placeholder shows (like the example's accept_current_selection)
				this.entry.text = "";
				// Set placeholder to show selected file (doesn't trigger filter)
				this.placeholder_text = this._selected_file.display_name;
			} else {
				// Clear entry text
				this.entry.text = "";
				// Reset placeholder
				this.placeholder_text = "Search files...";
			}
		}
	}
}
