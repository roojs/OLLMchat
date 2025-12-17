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
	 * Wrapper class for File objects that are aliases/symlinks.
	 * 
	 * Note: Alias files are not used in the editor. Properties return null/empty/default values
	 * and methods throw errors. The alias maintains its own path and parent (where the alias exists)
	 * for filesystem tracking purposes only.
	 */
	public class FileAlias : File
	{
		// Static field for home directory (initialized once)
		private static string home_dir = "/dev/null"; // no access if we cant get home dir.
		
		// Static constructor to initialize home directory
		static construct
		{
			home_dir = GLib.Environment.get_home_dir();
			if (home_dir == null || home_dir == "") {
				GLib.warning("FileAlias: Cannot determine home directory, aliases will be restricted");
			}
		}
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 * Note: points_to and points_to_id must be set after construction (by database loader or when target is known)
		 */
		public FileAlias(OLLMcoder.ProjectManager manager)
		{
			base(manager);
			this.base_type = "fa";
			// is_alias is now computed (returns true for FileAlias)
			// points_to and points_to_id must be set after construction
		}
		
		/**
		 * Named constructor: Create a FileAlias from FileInfo.
		 * 
		 * @param parent The parent Folder (required)
		 * @param info The FileInfo object from directory enumeration
		 * @param path The full path to the alias (where the symlink exists)
		 */
		public FileAlias.new_from_info(
			Folder parent,
			GLib.FileInfo info,
			string path)
		{
			base(parent.manager);
			this.base_type = "fa";
			this.path = path; // Alias path
			this.parent = parent;
			this.parent_id = parent.id;
			
			// Use realpath directly on this.path to completely resolve all symlinks in the chain
			// PATH_MAX is typically 4096 on Linux systems
			var resolved_ptr = Posix.realpath(path);
			if (resolved_ptr == null) {
				this.points_to_id = -1;
				return;
			}
			
			// Restrict aliases to user's home directory
			 
			// Check if resolved path is within home directory
			if (!resolved_ptr.has_prefix(home_dir)) {
				GLib.warning("FileAlias.new_from_info: Alias target '%s' is outside home directory '%s', rejecting", 
					(string)resolved_ptr, home_dir);
				this.points_to_id = -1;
				return;
			}
			
			this.target_path = resolved_ptr;
			
			var target_info = this.get_target_info(resolved_ptr);
			if (target_info == null) {
				this.points_to_id = -1;
				this.target_path = "";
				return;
			}
			
			if (target_info.get_file_type() == GLib.FileType.DIRECTORY) {
				this.points_to = new Folder.new_from_info(
					parent.manager, null, target_info, resolved_ptr);
			} else {
				this.points_to = new File.new_from_info(
					parent.manager, null, target_info, resolved_ptr);
			}
		}
		
		/**
		 * Programming language - delegates to target file for tree display.
		 */
		public new string? language {
			get { 
				if (this.points_to is File) {
					return ((File)this.points_to).language;
				}
				return "";
			}
			set { /* Aliases are not edited */ }
		}
		
		/**
		 * Text buffer - delegates to target file for tree display.
		 */
		public new GtkSource.Buffer? text_buffer {
			get { 
				if (this.points_to is File) {
					return ((File)this.points_to).text_buffer;
				}
				return null;
			}
			set { /* Aliases are not edited */ }
		}
		
		 
		
		/**
		 * Last viewed - delegates to target file for tree display.
		 */
		public new int64 last_viewed {
			get { 
				if (this.points_to != null) {
					return this.points_to.last_viewed;
				}
				return 0;
			}
			set { /* Aliases are not edited */ }
		}
		
		/**
		 * Needs approval - delegates to target file for tree display.
		 */
		public new bool needs_approval {
			get { 
				if (this.points_to is File) {
					return ((File)this.points_to).needs_approval;
				}
				return true;
			}
			set { /* Aliases are not edited */ }
		}
		
		/**
		 * Is unsaved - delegates to target file for tree display.
		 */
		public new bool is_unsaved {
			get { 
				if (this.points_to is File) {
					return ((File)this.points_to).is_unsaved;
				}
				return false;
			}
			set { /* Aliases are not edited */ }
		}
		
		/**
		 * Last approved copy path - delegates to target file for tree display.
		 */
		public new string last_approved_copy_path {
			get { 
				if (this.points_to is File) {
					return ((File)this.points_to).last_approved_copy_path;
				}
				return "";
			}
			set { /* Aliases are not edited */ }
		}
		
		/**
		 * Write file contents - aliases are not edited.
		 */
		public new void write(string contents) throws Error
		{
			throw new GLib.IOError.NOT_SUPPORTED("FileAlias.write() should not be called - alias files are not used in editor");
		}
		
		/**
		 * Read file contents asynchronously - aliases are not edited.
		 */
		public new async string read_async() throws Error
		{
			throw new GLib.IOError.NOT_SUPPORTED("FileAlias.read_async() should not be called - alias files are not used in editor");
		}
	}
}
