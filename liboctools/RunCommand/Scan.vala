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

namespace OLLMtools.RunCommand
{
	/**
	 * Post-completion overlay scanner that detects all changes (additions, modifications, deletions)
	 * and synchronizes them with the live filesystem and ProjectFiles database.
	 * 
	 * Uses a post-completion scanning approach. After command execution completes, scans the overlay
	 * directory structure recursively to detect all changes and applies them to the live filesystem and database.
	 * 
	 * The scanning follows a two-loop pattern:
	 * 1. First loop: Process all items in current directory (files, folders, symlinks)
	 * 2. Second loop: Recurse into folders
	 * 
	 * This ensures files/aliases are processed before folders when scanning for removals.
	 */
	public class Scan : Object
	{
		/**
		 * Project folder object (is_project = true) - provides access to project_files.
		 */
		private OLLMfiles.Folder project_folder;
		
		/**
		 * Base path of overlay upper directory.
		 * Example: "/home/alan/.cache/ollmchat/overlay-20250115-143022/upper"
		 */
		private string base_path;
		
		/**
		 * Maps overlay subdirectory names to real project paths.
		 * Key: Subdirectory name (e.g., "overlay1", "overlay2")
		 * Value: Real project root path (e.g., "/home/alan/project")
		 */
		private Gee.HashMap<string, string> overlay_map;
		
		/**
		* Timestamp when scanning started processing changes.
		* Used for all FileHistory records created during this scanning session.
		* Initialized to current time, updated in run() when scanning actually starts.
		*/
		private GLib.DateTime timestamp { get; private set; default = new GLib.DateTime.now_local(); }
		
		/**
		 * Constructor.
		 * 
		 * @param project_folder Project folder (provides access to project_files property)
		 * @param base_path Base path of overlay upper directory
		 * @param overlay_map Maps overlay subdirectory names to real project paths
		 */
		public Scan(
				OLLMfiles.Folder project_folder, 
				string base_path, Gee.HashMap<string, string> overlay_map)
		{
			this.project_folder = project_folder;
			this.base_path = base_path;
			this.overlay_map = overlay_map;
		}
		
		/**
		* Execute the scan after command completion.
		* 
		* Iterates over overlay_map entries and calls scan_dir() for each overlay subdirectory.
		* Calls cleanup() after all scanning is complete to remove deleted files from in-memory lists.
		*/
		public async void run()
		{
			// Debug: Dump in-memory data structures before scanning
			GLib.debug("Scan.run: Dumping in-memory data structures before scanning");
			GLib.debug("Scan.run: all_files has %d entries", this.project_folder.project_files.all_files.size);
			foreach (var entry in this.project_folder.project_files.all_files.entries) {
				GLib.debug("Scan.run: all_files['%s'] = %s(id=%lld)", 
					entry.key, entry.value.get_type().name(), entry.value.id);
			}
			
			// Iterate over overlay_map entries
			foreach (var entry in this.overlay_map.entries) {
				yield this.scan_dir(
					GLib.Path.build_filename(this.base_path, entry.key),
					entry.value
				);
			}
			
			// Cleanup deleted files from in-memory lists after all scanning is complete
			// This is more efficient than calling cleanup after each individual deletion
			yield this.project_folder.manager.delete_manager.cleanup();
			
			// Refresh review_files after scanning completes
			this.project_folder.project_files.review_files.refresh();
		}
		
		/**
		 * Recursively scan a directory in the overlay.
		 * 
		 * Follows a two-loop pattern:
		 * 1. First loop: Process all items in current directory (files, folders, symlinks)
		 * 2. Second loop: Recurse into folders
		 * 
		 * This ensures files/aliases are processed before folders when scanning for removals.
		 * 
		 * @param overlay_path Overlay path to the directory to scan
		 * @param real_path Real project path corresponding to the overlay path
		 */
		private async void scan_dir(string overlay_path, string real_path)
		{
			var overlay_dir = GLib.File.new_for_path(overlay_path);
			if (!overlay_dir.query_exists()) {
				return;
			}
			
			// Enumerate directory contents in overlay
			GLib.FileEnumerator enumerator;
			try {
				enumerator = overlay_dir.enumerate_children(
					GLib.FileAttribute.STANDARD_NAME + ","
						 + GLib.FileAttribute.STANDARD_TYPE + ","  
						 + GLib.FileAttribute.STANDARD_IS_SYMLINK,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("Cannot enumerate overlay directory %s: %s", overlay_path, e.message);
				return;
			}
			
			// First loop: Process all items in current directory
			var folders_list = new Gee.ArrayList<string>();
			GLib.FileInfo? file_info;
			while ((file_info = enumerator.next_file(null)) != null) {
				var item_overlay_path = GLib.Path.build_filename(overlay_path,
					 file_info.get_name());
				var actual_real_path = this.to_real_path(item_overlay_path);
				
				// Check ProjectFiles for existing filebase using real_path (may be null)
				// Use all_files which includes files, folders, and FileAlias symlinks
				OLLMfiles.FileBase? filebase = this.project_folder.project_files.all_files.get(actual_real_path);
				
				GLib.debug("scan_dir: item=%s, real_path=%s, filebase=%s", 
					file_info.get_name(), actual_real_path, 
					filebase == null ? "null" : filebase.get_type().name());
				
				// Call appropriate handler based on type
				if (file_info.get_file_type() == GLib.FileType.DIRECTORY) {
					folders_list.add(item_overlay_path);
					yield this.handle_folder(item_overlay_path, actual_real_path, filebase);
					continue;
				}
				
				if (file_info.get_is_symlink()) {
					yield this.handle_filealias(item_overlay_path, actual_real_path, filebase);
					continue;
				}
				
				yield this.handle_file(item_overlay_path, actual_real_path, filebase);
			}
			
			// Second loop: Recurse into folders
			foreach (var folder_overlay_path in folders_list) {
				yield this.scan_dir(folder_overlay_path, this.to_real_path(folder_overlay_path));
			}
		}
		
		/**
		 * Handle a file in the overlay.
		 * 
		 * Checks for whiteout first (deletion marker). If whiteout, calls handle_remove().
		 * Otherwise, determines if file should be created or modified based on ProjectFiles state.
		 * 
		 * @param overlay_path Overlay path to the file
		 * @param real_path Real project path to the file
		 * @param filebase Existing FileBase object from ProjectFiles (null if not found)
		 */
		private async void handle_file(string overlay_path, string real_path, OLLMfiles.FileBase? filebase)
		{
			GLib.debug("handle_file: %s -> %s, filebase: %s", 
				overlay_path, real_path, filebase == null ? "NEW" : filebase.get_type().name());
			
			var is_whiteout_result = this.is_whiteout(overlay_path);
			
			if (is_whiteout_result) {
				if (filebase != null) {
				
					yield this.handle_remove(overlay_path, filebase);
				} else {
					GLib.warning("handle_file: whiteout detected but filebase is null for path=%s (real_path=%s)", 
						overlay_path, real_path);
				}
				return;
			}
			
			if (filebase != null && !(filebase is OLLMfiles.File)) {
				yield this.handle_remove(overlay_path, filebase);
				filebase = null;
			}
			
			var file = filebase as OLLMfiles.File?;
			var change_type = "modified";
			
			if (file == null) {
				OLLMfiles.FileBase new_filebase;
				try {
					new_filebase = this.create_filebase_from_path(overlay_path, real_path);
				} catch (GLib.Error e) {
					GLib.warning("Cannot create filebase for %s: %s", overlay_path, e.message);
					return;
				}
				
				file = new_filebase as OLLMfiles.File;
				this.set_is_ignored(file);
				change_type = "added";
				
				var parent_folder = this.project_folder.project_files.folder_map.get(GLib.Path.get_dirname(real_path));
				if (parent_folder == null) {
					parent_folder = this.project_folder;
				}
				
				file.parent = parent_folder;
				file.parent_id = parent_folder.id;
				parent_folder.children.append(file);
			}
			
			try {
				var file_history = new OLLMfiles.FileHistory(
					this.project_folder.manager.db,
					file,
					change_type,
					this.timestamp
				);
				yield file_history.commit();
			} catch (GLib.Error e) {
				GLib.warning("Cannot create FileHistory for %s file (%s): %s", change_type, real_path, e.message);
			}
			
			try {
				GLib.File.new_for_path(overlay_path).copy(
					GLib.File.new_for_path(real_path),
					GLib.FileCopyFlags.OVERWRITE,
					null,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("Cannot copy file from overlay to real path (%s -> %s): %s", 
					overlay_path, real_path, e.message);
				return;
			}
			
			this.copy_permissions(overlay_path, real_path);
			
			if (change_type == "added") {
				// Set is_need_approval for new files created by our app (RunCommand)
				file.is_need_approval = true;
				file.last_change_type = change_type;
				// Update last_modified timestamp from filesystem
				file.last_modified = file.mtime_on_disk();
				
				try {
					var fake_file = new OLLMfiles.File.new_fake(this.project_folder.manager, file.path);
					yield this.project_folder.manager.convert_fake_file_to_real(fake_file, file.path);
					// After conversion, file should have a valid id, save the flag to database
					if (file.id > 0) {
						file.saveToDB(this.project_folder.manager.db, null, false);
					}
				} catch (GLib.Error e) {
					GLib.warning("Cannot convert fake file to real (%s): %s", file.path, e.message);
				}
				return;
			}
			
			// Set is_need_approval for modified files (our app modified the file via RunCommand)
			file.is_need_approval = true;
			file.last_change_type = change_type;
			// Update last_modified timestamp from filesystem
			file.last_modified = file.mtime_on_disk();
			// Save to database with updated flag
			if (file.id > 0) {
				file.saveToDB(this.project_folder.manager.db, null, false);
			}
			
			if (file.buffer != null) {
				try {
					yield file.buffer.read_async();
				} catch (GLib.Error e) {
					GLib.warning("Cannot reload buffer for file (%s): %s", file.path, e.message);
				}
			}
			
			this.project_folder.manager.on_file_contents_change(file);
		}
		
		/**
		 * Handle a folder in the overlay.
		 * 
		 * Folders are containers - they don't get "modified" directly.
		 * If folder exists in ProjectFiles and overlay, do nothing.
		 * If folder exists in overlay but not ProjectFiles, create it.
		 * 
		 * @param overlay_path Overlay path to the folder
		 * @param real_path Real project path to the folder
		 * @param filebase Existing FileBase object from ProjectFiles (null if not found)
		 */
		private async void handle_folder(string overlay_path, string real_path, OLLMfiles.FileBase? filebase)
		{
			GLib.debug("handle_folder: %s -> %s, filebase: %s", 
				overlay_path, real_path, filebase == null ? "NEW" : filebase.get_type().name());
			
			if (filebase != null && !(filebase is OLLMfiles.Folder)) {
				yield this.handle_remove(overlay_path, filebase);
				filebase = null;
			}
			
			if (filebase is OLLMfiles.Folder) {
				return;
			}
			
			GLib.FileInfo folder_info;
			try {
				folder_info = GLib.File.new_for_path(overlay_path).query_info(
					GLib.FileAttribute.STANDARD_CONTENT_TYPE + "," + GLib.FileAttribute.TIME_MODIFIED,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("Cannot query folder info for %s: %s", overlay_path, e.message);
				return;
			}
			
			var folder = new OLLMfiles.Folder.new_from_info(
				this.project_folder.manager,
				this.project_folder,
				folder_info,
				real_path
			);
			
			this.set_is_ignored(folder);
			
			try {
				var file_history = new OLLMfiles.FileHistory(
					this.project_folder.manager.db,
					folder,
					"added",
					this.timestamp
				);
				yield file_history.commit();
			} catch (GLib.Error e) {
				GLib.warning("Cannot create FileHistory for added folder (%s): %s", real_path, e.message);
			}
			
			try {
				GLib.File.new_for_path(real_path).make_directory(null);
			} catch (GLib.Error e) {
				GLib.warning("Cannot create directory (%s): %s", real_path, e.message);
				return;
			}
			
			this.copy_permissions(overlay_path, real_path);
			
			var parent_folder = this.project_folder.project_files.folder_map.get(GLib.Path.get_dirname(real_path));
			if (parent_folder == null) {
				parent_folder = this.project_folder;
			}
			
			folder.parent = parent_folder;
			folder.parent_id = parent_folder.id;
			parent_folder.children.append(folder);
			this.project_folder.project_files.folder_map.set(folder.path, folder);
			folder.saveToDB(this.project_folder.manager.db, null, false);
		}
		
		/**
		 * Handle a symlink (FileAlias) in the overlay.
		 * 
		 * @param overlay_path Overlay path to the symlink
		 * @param real_path Real project path to the symlink
		 * @param filebase Existing FileBase object from ProjectFiles (null if not found)
		 */
		private async void handle_filealias(string overlay_path, string real_path, OLLMfiles.FileBase? filebase)
		{
			GLib.debug("handle_filealias: %s -> %s, filebase: %s", 
				overlay_path, real_path, filebase == null ? "NEW" : filebase.get_type().name());
			
			if (filebase != null && !(filebase is OLLMfiles.FileAlias)) {
				yield this.handle_remove(overlay_path, filebase);
				filebase = null;
			}
			
			var filealias = filebase as OLLMfiles.FileAlias?;
			var change_type = "modified";
			
			if (filealias == null) {
				OLLMfiles.FileBase new_filebase;
				try {
					new_filebase = this.create_filebase_from_path(overlay_path, real_path);
				} catch (GLib.Error e) {
					GLib.warning("Cannot create filebase for %s: %s", overlay_path, e.message);
					return;
				}
				
				if (!(new_filebase is OLLMfiles.FileAlias)) {
					GLib.warning("Expected FileAlias but got %s for %s", new_filebase.get_type().name(), overlay_path);
					return;
				}
				
				filealias = new_filebase as OLLMfiles.FileAlias;
				this.set_is_ignored(filealias);
				change_type = "added";
			}
			
			try {
				var file_history = new OLLMfiles.FileHistory(
					this.project_folder.manager.db,
					filealias,
					change_type,
					this.timestamp
				);
				yield file_history.commit();
			} catch (GLib.Error e) {
				GLib.warning("Cannot create FileHistory for %s filealias (%s): %s", change_type, real_path, e.message);
			}
			
			try {
				string? symlink_target = GLib.FileUtils.read_link(overlay_path);
				if (symlink_target == null) {
					GLib.warning("Cannot read symlink target from overlay (%s)", overlay_path);
					return;
				}
				
				if (GLib.Path.is_absolute(symlink_target)) {
					symlink_target = this.to_real_path(symlink_target);
				}
				
				if (GLib.FileUtils.test(real_path, GLib.FileTest.EXISTS)) {
					GLib.FileUtils.unlink(real_path);
				}
				
				GLib.debug("creating symlink '%s' -> '%s'", real_path, symlink_target);
				Posix.symlink(symlink_target, real_path);
				this.copy_permissions(overlay_path, real_path);
			} catch (GLib.Error e) {
				GLib.warning("Cannot create symlink from overlay to real path (%s -> %s): %s", 
					overlay_path, real_path, e.message);
			}
		}
		
		/**
		* Handle removal of a file, folder, or symlink.
		* 
		* Single method handles all types. Uses DeleteManager to handle deletion
		* (filesystem + FileHistory + database), then calls cleanup() to remove
		* from in-memory lists.
		* 
		* @param overlay_path Overlay path (for reference, not used for deletion)
		* @param filebase FileBase object to remove (File, Folder, or FileAlias)
		*/
		private async void handle_remove(string overlay_path, OLLMfiles.FileBase filebase)
		{
			GLib.debug("handle_remove: %s (%s), filebase: %s", 
				overlay_path, filebase.path, filebase.get_type().name());
			
			// Delete file/folder (filesystem + FileHistory + database)
			// DeleteManager handles: filesystem deletion, FileHistory backup creation, database update (delete_id)
			// Use timestamp so all deletions from same command have same timestamp
			// If deletion fails (FileHistory or database update), throw error - caller needs to know
			// Note: Cleanup from in-memory lists is done after scan completes (in run()), not here
			// Note: Buffer clearing is handled by editor via notify::delete_id signal (Phase 4)
			try {
				yield this.project_folder.manager.delete_manager.remove(filebase, this.timestamp);
			} catch (GLib.Error e) {
				GLib.warning("Scan.handle_remove: Failed to delete %s: %s", filebase.path, e.message);
				throw e;  // Re-throw - caller needs to know deletion failed
			}
		}
		
		/**
		 * Set is_ignored flag on a FileBase object based on parent folder.
		 * 
		 * @param filebase FileBase object to set is_ignored on
		 */
		private void set_is_ignored(OLLMfiles.FileBase filebase)
		{
			filebase.is_ignored = false;
			var parent_folder = this.project_folder.project_files.folder_map.get(GLib.Path.get_dirname(filebase.path));
			
			if (parent_folder == null) {
				return;
			}
			
			if (parent_folder.is_ignored) {
				filebase.is_ignored = true;
				return;
			}
			
			if (!this.project_folder.manager.git_provider.repository_exists(parent_folder)) {
				return;
			}
			
			var workdir_path = this.project_folder.manager.git_provider.get_workdir_path(parent_folder);
			if (workdir_path == null || !filebase.path.has_prefix(workdir_path)) {
				return;
			}
			
			var relative_path = filebase.path.substring(workdir_path.length);
			if (relative_path.has_prefix("/")) {
				relative_path = relative_path.substring(1);
			}
			if (this.project_folder.manager.git_provider.path_is_ignored(parent_folder, relative_path)) {
				filebase.is_ignored = true;
			}
		}
		
		/**
		 * Create a FileBase object (File or FileAlias) from a filesystem path.
		 * 
		 * Used for tracking files that don't exist in ProjectFiles.
		 * 
		 * @param overlay_path Overlay path to the file (used to query file info)
		 * @param real_path Real project path to the file (used as the FileBase.path property)
		 * @return FileBase object (File or FileAlias)
		 * @throws GLib.Error if file info cannot be queried
		 */
		private OLLMfiles.FileBase create_filebase_from_path(string overlay_path, string real_path) throws GLib.Error
		{
			var file_info = GLib.File.new_for_path(overlay_path).query_info(
				GLib.FileAttribute.STANDARD_CONTENT_TYPE + "," + 
				GLib.FileAttribute.TIME_MODIFIED + "," +
				GLib.FileAttribute.STANDARD_IS_SYMLINK + "," +
				GLib.FileAttribute.STANDARD_SYMLINK_TARGET,
				GLib.FileQueryInfoFlags.NONE,
				null
			);
			
			if (file_info.get_is_symlink()) {
				var parent_folder = this.project_folder.project_files.folder_map.get(GLib.Path.get_dirname(real_path));
				if (parent_folder == null) {
					parent_folder = this.project_folder;
				}
				
				return new OLLMfiles.FileAlias.new_from_info(
					parent_folder,
					file_info,
					real_path
				);
			}
			
			return new OLLMfiles.File.new_from_info(
				this.project_folder.manager,
				this.project_folder,
				file_info,
				real_path
			);
		}
		
		/**
		 * Check if a path is a whiteout file (character device with 0/0 device number).
		 * 
		 * In overlayfs, whiteout files represent deleted files from the lower layer.
		 * 
		 * @param overlay_path Path to check
		 * @return true if the path is a whiteout file
		 */
		private bool is_whiteout(string overlay_path)
		{
			try {
				var file = GLib.File.new_for_path(overlay_path);
				if (!file.query_exists(null)) {
					GLib.debug("is_whiteout: file does not exist: %s", overlay_path);
					return false;
				}
				
				var info = file.query_info(
					GLib.FileAttribute.UNIX_RDEV + "," + GLib.FileAttribute.STANDARD_TYPE,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
				
				var file_type = info.get_file_type();
				GLib.debug("is_whiteout: file_type=%s for %s", file_type.to_string(), overlay_path);
				
				// Check if it's a character device (SPECIAL file type)
				if (info.get_file_type() != GLib.FileType.SPECIAL) {
					return false;
				}
				
				// Check if device number is 0/0 (whiteout)
				// Use UNIX_RDEV (st_rdev) for special files, not UNIX_DEVICE (st_dev)
				// Device number is 0 when both major and minor are 0 (whiteout)
				return info.get_attribute_uint32(GLib.FileAttribute.UNIX_RDEV) == 0;
			} catch (GLib.Error e) {
				return false;
			}
		}
		
		/**
		 * Convert an overlay filesystem path to the corresponding real project path.
		 * 
		 * @param overlay_path Overlay path to convert
		 * @return Real project path
		 */
		private string to_real_path(string overlay_path)
		{
			if (!overlay_path.has_prefix(this.base_path)) {
				return overlay_path;
			}
			
			var relative_path = overlay_path.substring(this.base_path.length);
			
			if (relative_path.has_prefix("/")) {
				relative_path = relative_path.substring(1);
			}
			
			if (relative_path == "") {
				return overlay_path;
			}
			
			var components = relative_path.split("/", 2);
			
			if (!this.overlay_map.has_key(components[0])) {
				return overlay_path;
			}
			
			if (components.length > 1) {
				return GLib.Path.build_filename(
					this.overlay_map.get(components[0]), components[1]);
			}
			return this.overlay_map.get(components[0]);
		}
		
		/**
		 * Copy file permissions (rwx only) from overlay file to real file.
		 * 
		 * @param overlay_path Overlay file path
		 * @param real_path Real file path
		 */
		private void copy_permissions(string overlay_path, string real_path)
		{
			GLib.FileInfo overlay_info;
			try {
				overlay_info = GLib.File.new_for_path(overlay_path).query_info(
					GLib.FileAttribute.UNIX_MODE,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("Cannot query overlay file permissions (%s): %s", overlay_path, e.message);
				return;
			}
			
			GLib.FileInfo real_info;
			try {
				real_info = GLib.File.new_for_path(real_path).query_info(
					GLib.FileAttribute.UNIX_MODE,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("Cannot query real file permissions (%s): %s", real_path, e.message);
				return;
			}
			
			var overlay_mode = overlay_info.get_attribute_uint32(GLib.FileAttribute.UNIX_MODE);
			var real_mode = real_info.get_attribute_uint32(GLib.FileAttribute.UNIX_MODE);
			var overlay_rwx = overlay_mode & 0777;
			var real_rwx = real_mode & 0777;
			
			if (overlay_rwx == real_rwx) {
				return;
			}
			
			try {
				GLib.File.new_for_path(real_path).set_attribute_uint32(
					GLib.FileAttribute.UNIX_MODE,
					(real_mode & ~0777) | overlay_rwx,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("Cannot set real file permissions (%s): %s", real_path, e.message);
			}
		}
		
		/**
		 * Recursively delete a directory and all its contents.
		 * 
		 * @param dir_path Path to directory to delete
		 * @throws Error if deletion fails
		 */
		public void recursive_delete(string dir_path) throws Error
		{
			GLib.debug("recursive_delete: attempting to delete %s", dir_path);
			var dir = GLib.File.new_for_path(dir_path);
			
			try {
				dir.set_attribute_uint32(
					GLib.FileAttribute.UNIX_MODE,
					0755,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.debug("recursive_delete: cannot change permissions on %s: %s", dir_path, e.message);
			}
			
			var enumerator = dir.enumerate_children(
				GLib.FileAttribute.STANDARD_NAME + "," + GLib.FileAttribute.STANDARD_TYPE,
				GLib.FileQueryInfoFlags.NONE,
				null
			);
			
			GLib.FileInfo? file_info;
			while ((file_info = enumerator.next_file(null)) != null) {
				if (file_info.get_file_type() == GLib.FileType.DIRECTORY) {
					this.recursive_delete(GLib.Path.build_filename(dir_path, file_info.get_name()));
					continue;
				}
				
				GLib.FileUtils.unlink(GLib.Path.build_filename(dir_path, file_info.get_name()));
			}
			
			dir.delete(null);
		}
	}
}
