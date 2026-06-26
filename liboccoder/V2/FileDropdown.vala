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
	 * Integrates with Project to populate file list from project's project_files.
	 */
	public class FileDropdown : SearchableDropdown
	{
		private OLLMfiles.Folder? current_project;
		private Gtk.SortListModel sorted_items;
		private Gtk.CustomFilter? search_filter;
		private Gtk.CustomSorter? sorter;
		private string current_search_text = "";
		private GLib.ListModel? current_model = null;
		
		/**
		 * Currently selected file.
		 * This is set when the popup closes and user has made a selection.
		 */
		private OLLMfiles.File? _selected_file = null;
		public OLLMfiles.File? selected_file {
			get { 
				return this._selected_file;
			}
		}
		
		/**
		 * Currently selected project (used to populate file list).
		 * Note: Projects are Folders with is_project = true.
		 */
		public OLLMfiles.Folder? project {
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
		public signal void file_selected(OLLMfiles.File? file);
		
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
				this.set_item_store(new GLib.ListStore(typeof(OLLMfiles.ProjectFile)));
				// Reset filter when clearing
				this.current_search_text = "";
				return;
			}
			
			// Use project_files directly as the ListModel (no copying)
			this.set_item_model(this.current_project.project_files);
			
			// Reset filter when refreshing (e.g., when window opens)
			this.current_search_text = "";
			if (this.entry != null) {
				this.entry.text = "";
			}
			this.update_filter_and_sort();
		}
		
		/**
		 * Update filter and sorted models based on current search text.
		 * This is called when search text changes or when filter needs to be reset.
		 */
		private void update_filter_and_sort()
		{
			// Use current_model if set (from set_item_model), otherwise fall back to item_store
			var model_to_filter = this.current_model != null ? this.current_model : this.item_store as GLib.ListModel;
			
			// Ensure filter exists
			this.create_search_filter();
			
			// Recreate filtered_items to apply current search filter
			this.filtered_items = new Gtk.FilterListModel(
				model_to_filter, this.search_filter);
			
			// Update sorted model with new filtered model
			if (this.sorted_items != null) {
				this.sorted_items = new Gtk.SortListModel(this.filtered_items, this.sorter);
				this.selection.model = this.sorted_items;
			}
		}
		
		/**
		 * Trigger re-sort of the list (useful when last_viewed changes).
		 */
		private void trigger_resort()
		{
			if (this.sorted_items == null || this.sorter == null) {
				return;
			}
			
			// Use set_sorter to trigger re-sort without recreating the model
			this.sorted_items.set_sorter(this.sorter);
		}
		
		/**
		 * Create the unified search filter (handles both wildcard and regular search).
		 * Filter closure references this.current_search_text directly, so it reads current value.
		 */
		private void create_search_filter()
		{
			if (this.search_filter != null) {
				return;
			}
			
			this.search_filter = new Gtk.CustomFilter((item) => {
				var search_text = this.current_search_text;
				if (search_text == "") {
					return true;
				}
				var project_file = item as OLLMfiles.ProjectFile;
				if (project_file == null) {
					return false;
				}
				
				var basename = project_file.display_basename;
				var path = project_file.file.path;
				
				// Check if search contains wildcards
				if (search_text.contains("*") || search_text.contains("?")) {
					// Use wildcard matching
					return this.match_wildcard(basename, search_text) ||
						this.match_wildcard(path, search_text);
				} else {
					// Use regular substring matching (case-insensitive)
					var search_lower = search_text.down();
					var basename_lower = basename.down();
					var path_lower = path.down();
					return basename_lower.contains(search_lower) || path_lower.contains(search_lower);
				}
			});
		}
		
		/**
		 * Create the custom sorter (prioritizes basename matches when searching, recent files when not).
		 * Sorter closure references this.current_search_text directly, so it reads current value.
		 */
		private void create_sorter()
		{
			if (this.sorter != null) {
				return;
			}
			
			this.sorter = new Gtk.CustomSorter((a, b) => {
				var pf_a = a as OLLMfiles.ProjectFile;
				var pf_b = b as OLLMfiles.ProjectFile;
				if (pf_a == null || pf_b == null) {
					return Gtk.Ordering.EQUAL;
				}
				
				// If searching, prioritize starts_with matches, then contains matches
				if (this.current_search_text != "") {
					var search_lower = this.current_search_text.down();
					var a_basename_lower = pf_a.display_basename.down();
					var b_basename_lower = pf_b.display_basename.down();
					
					var a_starts_with = a_basename_lower.has_prefix(search_lower);
					var b_starts_with = b_basename_lower.has_prefix(search_lower);
					var a_contains = a_basename_lower.contains(search_lower);
					var b_contains = b_basename_lower.contains(search_lower);
					
					// Prioritize: starts_with > contains > no match
					// If one starts with and the other doesn't, starts_with comes first
					if (a_starts_with != b_starts_with) {
						return a_starts_with ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
					}
					
					// Both start with or both don't start with
					// If both start with, sort alphabetically
					if (a_starts_with && b_starts_with) {
						if (a_basename_lower != b_basename_lower) {
							return a_basename_lower < b_basename_lower ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
						}
						return Gtk.Ordering.EQUAL;
					}
					
					// Neither starts with - check contains
					if (a_contains != b_contains) {
						return a_contains ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
					}
					
					// Both contain or both don't - sort alphabetically
					if (a_basename_lower != b_basename_lower) {
						return a_basename_lower < b_basename_lower ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
					}
					return Gtk.Ordering.EQUAL;
				}
				
				// No search: recent files first (sorted by last_viewed desc), then by name
				if (pf_a.is_recent != pf_b.is_recent) {
					return pf_a.is_recent ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
				}
				
				// Both recent or both not recent - if recent, sort by last_viewed desc
				if (pf_a.is_recent && pf_b.is_recent) {
					if (pf_a.file.last_viewed != pf_b.file.last_viewed) {
						return pf_a.file.last_viewed > pf_b.file.last_viewed ? 
							Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
					}
				}
				
				// Sort by basename
				var a_basename = pf_a.display_basename.down();
				var b_basename = pf_b.display_basename.down();
				return a_basename < b_basename ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
			});
		}
		
		/**
		 * Set the item model using a ListModel directly (for ProjectFiles).
		 */
		private void set_item_model(GLib.ListModel model)
		{
			this.current_model = model;
			
			// Create unified search filter once
			this.create_search_filter();
			
			// Use the model directly for filtering (no copying)
			this.filtered_items = new Gtk.FilterListModel(
				model, this.search_filter);
			
			// Create custom sorter once
			this.create_sorter();
			
			// Create sorted model
			this.sorted_items = new Gtk.SortListModel(this.filtered_items, this.sorter);
			
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
			
			// Create custom sorter: active files first, then sort by display_name
			var sorter = new Gtk.CustomSorter((a, b) => {
				var file_a = a as OLLMfiles.FileBase;
				var file_b = b as OLLMfiles.FileBase;
				if (file_a == null || file_b == null) {
					return Gtk.Ordering.EQUAL;
				}
				
				// Sort by is_active first (active files come first)
				if (file_a.is_active != file_b.is_active) {
					return file_a.is_active ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
				}
				
				// Then sort by path
				return file_a.path < file_b.path ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
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
		 * Override on_entry_changed to support custom search (basename first, then path).
		 */
		protected override void on_entry_changed()
		{
			var search_text = this.entry.text;
			this.current_search_text = search_text;
			
			// Handle empty search text
			if (search_text == "") {
				// Restore placeholder when text is cleared
				this.entry.placeholder_text = this.placeholder_text;
				// Hide popup if visible
				if (this.popup.visible) {
					this.set_popup_visible(false);
				}
				return;
			}
			
			// Update filter and sorted models
			this.update_filter_and_sort();
			
			// Clear placeholder when user starts typing
			this.entry.placeholder_text = "";
			
			// Ensure cursor is at end and no text is selected before showing popup
			this.entry.set_position(-1);
			this.entry.select_region(-1, -1);
			
			// Show popup when user types (if there are filtered items)
			if (this.filtered_items.get_n_items() > 0) {
				this.set_popup_visible(true);
			}
		}
		
		/**
		 * Override set_popup_visible to reset filter and trigger re-sort when showing popup with no search.
		 */
		protected new void set_popup_visible(bool visible)
		{
			if (!visible) {
				// Reset search when popup hides - ensures clean state when reopening
				this.entry.text = "";
				this.current_search_text = "";
				this.update_filter_and_sort();
			} 
			if (visible && this.entry.text != this.current_search_text) {
				// Sync current_search_text with entry text when opening popup while typing
				this.current_search_text = this.entry.text;
				this.update_filter_and_sort();
			}
			
			base.set_popup_visible(visible);
			
			// If showing popup with no search, trigger re-sort to ensure last_viewed order is current
			if (visible && this.current_search_text == "" && this.sorted_items != null) {
				this.trigger_resort();
			}
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
			var project_file = this.selection.selected_item as OLLMfiles.ProjectFile;
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
