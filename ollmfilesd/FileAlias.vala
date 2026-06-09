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

namespace OLLMfilesd
{
	/**
	 * Represents a symlink/alias to a file or folder.
	 * 
	 * Many properties delegate to the target file (language, last_viewed, is_need_approval,
	 * is_unsaved). The points_to property references the target
	 * file/folder, while points_to_id and target_path store the database ID and resolved
	 * path respectively.
	 * 
	 * == Restrictions ==
	 * 
	 * Security: Aliases are restricted to user's home directory. Aliases outside home
	 * directory are rejected.
	 * 
	 * Editor Restrictions: write() and read_async() throw IOError.NOT_SUPPORTED. Aliases
	 * are not used in the editor (for display only).
	 * 
	 * == Notes ==
	 * 
	 * On Linux, aliases resolve symlinks completely using realpath(). On Windows,
	 * GLib.Filename.canonicalize() is used (symlinks are not followed). Target must
	 * exist and be within home directory. Aliases maintain their own path (where the
	 * symlink exists) for filesystem tracking.
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
		public FileAlias(ProjectManager manager)
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

			// Resolve the alias target before the home-dir check. Linux uses realpath() so
			// symlinks pointing outside $HOME are rejected (canonicalize does not follow links).
			// Windows has no realpath(); canonicalize() is the best available fallback there.
#if !G_OS_WIN32
			var resolved_path = Posix.realpath(path);
			if (resolved_path == null) {
				this.points_to_id = -1;
				return;
			}
#else
			var resolved_path = GLib.Filename.canonicalize(path);
			if (resolved_path == null || resolved_path == "") {
				this.points_to_id = -1;
				return;
			}
#endif
			
			// Restrict aliases to user's home directory
			 
			// Check if resolved path is within home directory
			if (!resolved_path.has_prefix(home_dir)) {
				GLib.warning("FileAlias.new_from_info: Alias target '%s' is outside home directory '%s', rejecting", 
					resolved_path, home_dir);
				this.points_to_id = -1;
				return;
			}
			
			this.target_path = resolved_path;
			
			var target_info = this.get_target_info(resolved_path);
			if (target_info == null) {
				this.points_to_id = -1;
				this.target_path = "";
				return;
			}
			
			if (target_info.get_file_type() == GLib.FileType.DIRECTORY) {
				this.points_to = new Folder.new_from_info(
					parent.manager, null, target_info, resolved_path);
			} else {
				this.points_to = new File.new_from_info(
					parent.manager, null, target_info, resolved_path);
			}
		}
		
		public override string to_summary(Gee.HashMap<int, SQT.VectorMetadata> keymap, string indent)
		{
			if (this.points_to != null) {
				return this.points_to.to_summary(keymap, indent);
			}
			return indent + "- (alias) " + GLib.Path.get_basename(this.path);
		}
		
		/**
		 * Programming language - delegates to target file for tree display.
		 */
		public new string language {
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
		 * Note: Buffer is stored via provider using set_data/get_data, so this
		 * property is not directly accessible. Use manager.buffer_provider.has_buffer()
		 * to check if target file has a buffer.
		 */
		
		 
		
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
		public new bool is_need_approval {
			get { 
				if (this.points_to is File) {
					return ((File)this.points_to).is_need_approval;
				}
				return false;
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
