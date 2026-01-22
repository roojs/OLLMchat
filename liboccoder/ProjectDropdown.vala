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
	 * Searchable dropdown widget for selecting projects.
	 * 
	 * Wraps Gtk.DropDown and adds search/filter functionality.
	 * Integrates with ProjectManager to populate project list.
	 */
	public class ProjectDropdown : SearchableDropdown
	{
		private OLLMfiles.ProjectManager manager;
		
		/**
		 * Currently selected project (folder with is_project = true).
		 * This is set when the popup closes and user has made a selection.
		 */
		public OLLMfiles.Folder? selected_project { get; private set; }
		
		/**
		 * Emitted when project selection changes.
		 * Note: Projects are Folders with is_project = true.
		 */
		public signal void project_selected(OLLMfiles.Folder? project);
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public ProjectDropdown(OLLMfiles.ProjectManager manager)
		{
			base();
			this.manager = manager;
			this.placeholder_text = "Select project";
			
			// Debug: Log project list state
			GLib.debug("ProjectDropdown: manager.projects.get_n_items() = %u", this.manager.projects.get_n_items());
			
			// Use ProjectList directly as the ListModel (no copying)
			this.set_item_model(this.manager.projects);
			
			// Debug: Log after setting model
			GLib.debug("ProjectDropdown: After set_item_model, filtered_items.get_n_items() = %u", this.filtered_items.get_n_items());
		}
		
		/**
		 * Set the item model using a ListModel directly (for ProjectList).
		 */
		private void set_item_model(GLib.ListModel model)
		{
			// Debug: Log model state
			GLib.debug("ProjectDropdown.set_item_model: model.get_n_items() = %u, model type = %s", 
				model.get_n_items(), model.get_type().name());
			
			// Update string filter to work with Folder type
			this.string_filter = new Gtk.StringFilter(
				new Gtk.PropertyExpression(typeof(OLLMfiles.Folder), 
				null, this.get_filter_property())
			) {
				match_mode = Gtk.StringFilterMatchMode.SUBSTRING,
				ignore_case = true
			};
			
			// Use the model directly for filtering (no copying)
			// ProjectList only contains projects, so no need for additional filtering
			this.filtered_items = new Gtk.FilterListModel(
				model, this.string_filter);
			
			// Debug: Log filtered items
			GLib.debug("ProjectDropdown.set_item_model: filtered_items.get_n_items() = %u", 
				this.filtered_items.get_n_items());
			
			// Create custom sorter: sort by path_basename (derived from path)
			var sorter = new Gtk.CustomSorter((a, b) => {
				var folder_a = a as OLLMfiles.Folder;
				var folder_b = b as OLLMfiles.Folder;
				if (folder_a == null || folder_b == null || 
					folder_a.path_basename.down() == folder_b.path_basename.down()) {
					return Gtk.Ordering.EQUAL;
				}
				return folder_a.path_basename.down() < folder_b.path_basename.down() ? 
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
			// Disabled: Don't monitor selection changes - only trigger actions when popup closes
			// this.selection.notify["selected"].connect(() => {
			// 	this.on_selection_changed();
			// });
			
			// Update list view with new selection model
			this.list.model = this.selection;
			
			// Debug: Log final state
			GLib.debug("ProjectDropdown.set_item_model: sorted_items.get_n_items() = %u, selection.model.get_n_items() = %u", 
				sorted_items.get_n_items(), this.selection.model.get_n_items());
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
			return "path_basename";
		}
		
		protected override string get_label_property()
		{
			// For projects: use path_basename (derived from path)
			return "path_basename";
		}
		
		protected override string get_tooltip_property()
		{
			// For projects: use path (full path)
			return "path";
		}
		
		protected override void on_selected()
		{
			// Get the selected item from the selection model
			var project = this.selection.selected_item as OLLMfiles.Folder;
			// Ensure it's actually a project
			
			// If no valid project selected, something went wrong - don't change anything
			if (project == null || !project.is_project) {
				GLib.warning("ProjectDropdown.on_selected: No valid project selected");
				return;
			}
			
			// Update the stored selected project
			this.selected_project = project;
			
			//GLib.debug("ProjectDropdown.on_selected: selected_project=%s", project.path);
			
			// Emit signal with the selected project
			this.project_selected(this.selected_project);
			
			// Clear entry text so placeholder shows
			this.entry.text = "";
			// Set placeholder to show selected project
			this.placeholder_text = this.selected_project.path_basename;
		}
	}
}
