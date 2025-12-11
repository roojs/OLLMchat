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
	 * Base class for File and Folder objects.
	 * 
	 * Provides common properties and methods shared by both files and folders.
	 */
	public abstract class FileBase : Object
	{
		/**
		 * Database ID.
		 */
		public int64 id { get; set; default = 0; }
		
		/**
		 * File/folder path.
		 */
		public string path { get; set; default = ""; }
		
		/**
		 * Parent folder ID for database storage.
		 */
		public int64 parent_id { get; set; default = 0; }
		
		/**
		 * Reference to parent folder (nullable for root folders/projects).
		 */
		public Folder? parent { get; set; default = null; }
		
		/**
		 * Reference to ProjectManager.
		 * 
		 */
		public  OLLMcoder.ProjectManager manager { get; construct; }
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		protected FileBase(OLLMcoder.ProjectManager manager)
		{
			this.manager = manager;
		}
		
		/**
		 * Icon name for binding in lists.
		 */
		public string icon_name { get; set; default = ""; }
		
		/**
		 * Display name for binding in lists.
		 */
		public string display_name { get; set; default = ""; }
		
		/**
		 * Tooltip text for binding in lists.
		 */
		public string tooltip { get; set; default = ""; }
		
		/**
		 * Get modification time on disk (Unix timestamp).
		 * 
		 * @return Modification time as Unix timestamp, or 0 if unavailable
		 */
		public int64 mtime_on_disk()
		{
			var file = GLib.File.new_for_path(this.path);
			if (!file.query_exists()) {
				return 0;
			}
			
			try {
				var info = file.query_info(
					GLib.FileAttribute.TIME_MODIFIED,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
				return info.get_modification_time().tv_sec;
			} catch (GLib.Error e) {
				return 0;
			}
		}
	}
}
