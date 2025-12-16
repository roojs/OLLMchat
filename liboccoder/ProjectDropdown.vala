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
	 * Searchable dropdown widget for selecting projects.
	 * 
	 * Wraps Gtk.DropDown and adds search/filter functionality.
	 * Integrates with ProjectManager to populate project list.
	 */
	public class ProjectDropdown : SearchableDropdown
	{
		private ProjectManager manager;
		
		/**
		 * Currently selected project (folder with is_project = true).
		 */
		public Files.Folder? selected_project {
			get { 
				var item = this.selection.selected_item as Files.Folder;
				// Ensure it's actually a project
				return (item != null && item.is_project) ? item : null;
			}
			set { 
				if (value != null && value.is_project) {
					this.set_selected_item_internal(value);
				}
			}
		}
		
		/**
		 * Emitted when project selection changes.
		 * Note: Projects are Folders with is_project = true.
		 */
		public signal void project_selected(Files.Folder? project);
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public ProjectDropdown(ProjectManager manager)
		{
			base();
			this.manager = manager;
			this.placeholder_text = "Search projects...";
			
			// Use ProjectList directly as the ListModel (no copying)
			this.set_item_model(this.manager.projects);
		}
		
		/**
		 * Set the item model using a ListModel directly (for ProjectList).
		 */
		private void set_item_model(GLib.ListModel model)
		{
			// Update string filter to work with Folder type
			this.string_filter = new Gtk.StringFilter(
				new Gtk.PropertyExpression(typeof(Files.Folder), 
				null, this.get_filter_property())
			) {
				match_mode = Gtk.StringFilterMatchMode.SUBSTRING,
				ignore_case = true
			};
			
			// Use the model directly for filtering (no copying)
			// ProjectList only contains projects, so no need for additional filtering
			this.filtered_items = new Gtk.FilterListModel(
				model, this.string_filter);
			
			// Create custom sorter: sort by display_name
			var sorter = new Gtk.CustomSorter((a, b) => {
				var folder_a = a as Files.Folder;
				var folder_b = b as Files.Folder;
				if (folder_a == null || folder_b == null) {
					return Gtk.Ordering.EQUAL;
				}
				return folder_a.display_name < folder_b.display_name ? 
					Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
			});
			
			// Create sorted model
			var sorted_items = new Gtk.SortListModel(this.filtered_items, sorter);
			
			// Update selection model to use sorted model
			this.selection = new Gtk.SingleSelection(sorted_items) {
				autoselect = false,
				can_unselect = true,
				selected = Gtk.INVALID_LIST_POSITION
			};
			this.selection.notify["selected"].connect(() => {
				this.on_selection_changed();
			});
			
			// Update list view with new selection model
			this.list.model = this.selection;
		}
		
		/**
		 * Refresh the project list from ProjectManager.
		 * No-op since we use ProjectList directly - it updates automatically.
		 */
		public void refresh()
		{
			// ProjectList is used directly, so no refresh needed
			// The ListModel will automatically notify when items change
		}
		
		protected override string get_filter_property()
		{
			return "display_name";
		}
		
		protected override void on_selection_changed()
		{
			this.project_selected(this.selected_project);
			if (this.selected_project != null) {
				this.entry.text = this.selected_project.display_name;
				this.set_popup_visible(false);
			}
		}
	}
}
