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
		 * Currently selected project.
		 */
		public Files.Project? selected_project {
			get { return this.selection.selected_item as Files.Project; }
			set { this.set_selected_item_internal(value); }
		}
		
		/**
		 * Emitted when project selection changes.
		 */
		public signal void project_selected(Files.Project? project);
		
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
			
			// Populate projects from manager
			this.refresh();
		}
		
		/**
		 * Refresh the project list from ProjectManager.
		 */
		public void refresh()
		{
			this.item_store.remove_all();
			
			foreach (var project in this.manager.projects) {
				this.item_store.append(project);
			}
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
