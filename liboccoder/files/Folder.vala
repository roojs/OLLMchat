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

namespace OLLMcoder.Files
{
	/**
	 * Represents a folder/directory in the project.
	 * 
	 * Folders maintain a list of their children and a hashmap for quick lookup by filename.
	 * Emits signals when children are added/removed.
	 */
	public class Folder : FileBase
	{
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public Folder(OLLMcoder.ProjectManager manager)
		{
			base(manager);
			this.base_type = "d";
		}
		
		/**
		 * Whether this folder represents a project (stored in database, default: false).
		 */
		public bool is_project { get; set; default = false; }
		
		/**
		 * ProjectFiles manager for this project (only set when is_project = true, nullable).
		 * Handles async scanning, loading, and synchronization.
		 */
		public ProjectFiles? project_files { get; set; default = null; }
		
		/**
		 * ListStore of all files in project (used by dropdowns).
		 * @deprecated Use project_files.get_flat_file_list() instead.
		 */
		public GLib.ListStore all_files { get; set; 
			default = new GLib.ListStore(typeof(FileBase)); }
		
		/**
		 * Unix timestamp of last view (stored in database, default: 0, used for projects).
		 */
		public int64 last_viewed { get; set; default = 0; }
		
		/**
		 * List of children (files and subfolders) - used for tree view hierarchy.
		 */
		public Gee.ArrayList<FileBase> children { get; set; 
			default = new Gee.ArrayList<FileBase>((a, b) => {
				return a.path == b.path;
			}); }
		
		/**
		 * Hashmap of [name in dir] => file object.
		 */
		public Gee.HashMap<string, FileBase> child_map { get; set; 
				default = new Gee.HashMap<string, FileBase>(); }
		
		/**
		 * Last check time for this folder (prevents re-checking during recursive scans).
		 */
		public int64 last_check_time { get; set; default = 0; }
		
		/**
		 * Emitted when a child is added.
		 */
		public signal void child_added(FileBase child);
		
		/**
		 * Emitted when a child is removed.
		 */
		public signal void child_removed(FileBase child);
		
		
	}
}
