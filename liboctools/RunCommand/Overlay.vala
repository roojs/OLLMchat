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

namespace OLLMtools.RunCommand
{
	/**
	 * Manages overlay filesystem creation, mounting, and cleanup for isolating writes during command execution.
	 * 
	 * FIXME: This overlay does not handle the following edge cases:
	 * File aliases (symlinks) Symlinks are copied as regular files (not as symlinks)
	 */
	public class Overlay : GLib.Object
	{
		/**
		 * Project folder object (is_project = true) - the main project directory.
		 */
		public OLLMfiles.Folder project { get; set; }

		/**
		 * Map of path -> Folder objects for project roots that need write access.
		 * 
		 * Contains all directories that need write access, as determined by project.build_roots().
		 * Same structure as Bubble.roots: HashMap mapping paths to Folder objects.
		 * Key: Project root path (e.g., "/home/alan/project")
		 * Value: Folder object (typically the project Folder reference)
		 */
		private Gee.HashMap<string, OLLMfiles.Folder> roots { get; private set; default = new Gee.HashMap<string, OLLMfiles.Folder>(); }

		/**
		 * Base directory for overlay filesystem.
		 * Path: ~/.cache/ollmchat/{overlay-datetime}/
		 * Example: /home/alan/.cache/ollmchat/overlay-20250115-143022/
		 * 
		 * Callers can build derived paths using GLib.Path.build_filename():
		 * - Upper directory: GLib.Path.build_filename(overlay_dir, "upper")
		 * - Work directory: GLib.Path.build_filename(overlay_dir, "work")
		 * - Mount point: GLib.Path.build_filename(overlay_dir, "merged")
		 */
		public string overlay_dir { get; private set; default = ""; }

		/**
		 * HashMap mapping overlay subdirectory names to real project root paths.
		 * Key: Subdirectory name (e.g., "overlay1", "overlay2")
		 * Value: Real project root path (e.g., "/home/alan/project")
		 * Example:
		 * "overlay1" -> "/home/alan/project"
		 * "overlay2" -> "/home/alan/other-project"
		 * 
		 * Derived from roots HashMap during create().
		 */
		public Gee.HashMap<string, string> overlay_map { get; private set; default = new Gee.HashMap<string, string>(); }

		/**
		 * Monitor instance for tracking filesystem changes in overlay.
		 * Created in constructor, started in start_monitor(), stopped before copying files.
		 */
		private Monitor monitor { get; private set; }



		/**
		 * Constructor.
		 * 
		 * Initializes an Overlay instance with the specified project folder.
		 * The overlay structure will be created in ~/.cache/ollmchat/{overlay-datetime}/
		 * 
		 * @param project Project folder object (is_project = true) - the main project directory
		 * @throws Error if project is invalid, build_roots() fails, or paths are not absolute
		 */
		public Overlay(OLLMfiles.Folder project) throws Error
		{
			this.project = project;
			
			// Build roots HashMap from project.build_roots()
			foreach (var folder in this.project.build_roots()) {
				this.roots.set(folder.path, this.project);
			}
			
			// Generate unique timestamp-based directory name: overlay-{YYYYMMDD}-{HHMMSS}
			var now = new GLib.DateTime.now_local();
			var timestamp = "%04d%02d%02d-%02d%02d%02d".printf(
				now.get_year(), now.get_month(), now.get_day_of_month(),
				now.get_hour(), now.get_minute(), now.get_second()
			);
			
			// Set overlay_dir to ~/.cache/ollmchat/{overlay-datetime}/
			var cache_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".cache", "ollmchat"
			);
			this.overlay_dir = GLib.Path.build_filename(cache_dir, "overlay-" + timestamp);
			
			// Create Monitor instance (will be started in start_monitor())
			this.monitor = new Monitor(
				this.project,
				GLib.Path.build_filename(this.overlay_dir, "upper"),
				this.overlay_map
			);
		}

		/**
		 * Create overlay directory structure with subdirectories for each project root.
		 * 
		 * Creates the following directory structure:
		 * - {overlay_dir}/upper/overlay1/ (for first project root - RWSRC for bubblewrap)
		 * - {overlay_dir}/upper/overlay2/ (for second project root - RWSRC for bubblewrap)
		 * - {overlay_dir}/upper/overlay3/ (for third project root - RWSRC for bubblewrap)
		 * - etc.
		 * - {overlay_dir}/work/work1/ (work directory for first overlay)
		 * - {overlay_dir}/work/work2/ (work directory for second overlay)
		 * - etc.
		 * 
		 * Also builds overlay_map HashMap mapping subdirectory names to real project paths.
		 * 
		 * The upper directory is created as a regular directory. Cleanup is performed
		 * by recursively deleting the upper directory contents during cleanup().
		 * 
		 * Note: Overlay mounting is handled by bubblewrap's --overlay option, not manually.
		 * 
		 * @throws GLib.IOError if directory creation fails
		 */
		public void create() throws Error
		{
			try {
				// Create overlay_dir directory (with parents if needed)
				GLib.File.new_for_path(this.overlay_dir).make_directory_with_parents(null);
				
				// Create upper directory (regular directory)
				GLib.File.new_for_path(
					GLib.Path.build_filename(this.overlay_dir, "upper")
				).make_directory_with_parents(null);
				
				// Create work directory (parent for individual work dirs)
				GLib.File.new_for_path(
					GLib.Path.build_filename(this.overlay_dir, "work")
				).make_directory_with_parents(null);
				
				// Iterate over roots to create subdirectories and build overlay_map
				var entries_array = this.roots.entries.to_array();
				for (int i = 0; i < entries_array.length; i++) {
					var entry = entries_array[i];
					var subdirectory_name = "overlay" + (i + 1).to_string();
					var work_name = "work" + (i + 1).to_string();
					
					// Create subdirectory in upper directory (RWSRC for bubblewrap --overlay)
					GLib.File.new_for_path(
						GLib.Path.build_filename(this.overlay_dir, "upper", subdirectory_name)
					).make_directory_with_parents(null);
					
					// Create work subdirectory (WORKDIR for bubblewrap --overlay)
					GLib.File.new_for_path(
						GLib.Path.build_filename(this.overlay_dir, "work", work_name)
					).make_directory_with_parents(null);
					
					// Add to overlay_map
					this.overlay_map.set(subdirectory_name, entry.key);
				}
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Cannot create overlay directory structure: " + e.message);
			}
		}

		/**
		 * Start monitoring the overlay upper directory.
		 * 
		 * Starts the Monitor to track changes in the overlay upper directory.
		 * This should be called before executing commands in bubblewrap.
		 * 
		 * @throws GLib.IOError if monitor start fails
		 */
		public void start_monitor() throws Error
		{
			// Start Monitor: this.monitor.start() (monitor was created in constructor)
			this.monitor.start();
		}

		/**
		 * Copy files from overlay to live system based on Monitor change lists.
		 * 
		 * Stops monitoring, then processes Monitor change lists to copy files from overlay
		 * upper directory to project directories. Also copies file permissions (rwx only).
		 * Creates backups for modified and deleted files, updates ProjectManager file data,
		 * and handles file metadata.
		 * 
		 * This should be called after command execution is complete.
		 * 
		 * Errors are logged via GLib.warning() but do not throw - operation continues for remaining files.
		 */
		public async void copy_files()
		{
			// Stop Monitor (existing)
			yield this.monitor.stop();
			
			// Process deleted files FIRST (this.monitor.removed)
			// Sort entries in reverse order (folders deleted after children)
			var removed_entries = new Gee.ArrayList<string>.wrap(this.monitor.removed.keys.to_array());
			removed_entries.sort((a, b) => {
				return strcmp(b, a); // Reverse sort
			});
			
			foreach (var key in removed_entries) {
				var filebase = this.monitor.removed.get(key);
				
				// Set is_deleted flag
				filebase.is_deleted = true;
				
				if (filebase is OLLMfiles.File) {
					yield this.file_removed(filebase as OLLMfiles.File);
					continue;
				}
				
				if (filebase is OLLMfiles.Folder) {
					yield this.folder_removed(filebase as OLLMfiles.Folder);
					continue;
				}
			}
			
			// Process Monitor change lists
			// For modified files (this.monitor.updated)
			foreach (var entry in this.monitor.updated.entries) {
				var file = entry.value as OLLMfiles.File;
				if (file == null) {
					continue;
				}
				yield this.file_updated(entry.key, file);
			}
			
			// Process new files (this.monitor.added)
			// Sort entries by path (to ensure parent directories are created naturally)
			var added_entries = new Gee.ArrayList<string>.wrap(this.monitor.added.keys.to_array());
			added_entries.sort((a, b) => {
				return strcmp(a, b);
			});
			
			foreach (var key in added_entries) {
				var filebase = this.monitor.added.get(key);
				
				if (filebase is OLLMfiles.File) {
					yield this.file_added(key, filebase as OLLMfiles.File);
					continue;
				}
				
				if (filebase is OLLMfiles.Folder) {
					yield this.folder_added(key, filebase as OLLMfiles.Folder);
					continue;
				}
			}
		}

		/**
		 * Handle an updated file from overlay.
		 * 
		 * Creates a backup, copies the file from overlay to real path, copies permissions,
		 * reloads the buffer if it exists, and updates metadata.
		 * 
		 * @param overlay_path Path to file in overlay
		 * @param file File object representing the updated file
		 */
		private async void file_updated(string overlay_path, OLLMfiles.File file)
		{
			// Create backup (all modified files are in database, id > 0)
			// Skip backup for ignored files
			if (!file.is_ignored) {
				try {
					yield file.create_backup();
				} catch (GLib.Error e) {
					GLib.warning("Cannot create backup for file (%s): %s", file.path, e.message);
				}
			}
			
			// Copy modified file from overlay to real path
			try {
				GLib.File.new_for_path(overlay_path).copy(
					GLib.File.new_for_path(file.path),
					GLib.FileCopyFlags.OVERWRITE,
					null,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("Cannot copy file from overlay to real path (%s -> %s): %s", 
					overlay_path, file.path, e.message);
				return;
			}
			
			// Copy file permissions (existing)
			this.copy_permissions(overlay_path, file.path);
			
			// Reload buffer with new content (only if buffer already exists)
			if (file.buffer != null) {
				try {
					yield file.buffer.read_async();
				} catch (GLib.Error e) {
					GLib.warning("Cannot reload buffer for file (%s): %s", file.path, e.message);
				}
			}
			
			// Update metadata (existing method)
			this.project.manager.on_file_contents_change(file);
		}

		/**
		 * Handle a new file added to overlay.
		 * 
		 * Copies the file from overlay to real path, copies permissions, and converts
		 * fake file to real file in ProjectManager.
		 * 
		 * @param overlay_path Path to file in overlay
		 * @param file File object representing the added file
		 */
		private async void file_added(string overlay_path, OLLMfiles.File file)
		{
			// Copy file from overlay to real path first
			// convert_fake_file_to_real() handles parent directory creation via make_children()
			try {
				GLib.File.new_for_path(overlay_path).copy(
					GLib.File.new_for_path(file.path),
					GLib.FileCopyFlags.OVERWRITE,
					null,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("Cannot copy file from overlay to real path (%s -> %s): %s", 
					overlay_path, file.path, e.message);
				return;
			}
			
			// Copy file permissions (existing)
			this.copy_permissions(overlay_path, file.path);
			
			// Create fake file and convert to real (existing method handles parent directory creation)
			// Ignored files still need to be saved to DB
			try {
				var fake_file = new OLLMfiles.File.new_fake(this.project.manager, file.path);
				yield this.project.manager.convert_fake_file_to_real(fake_file, file.path);
			} catch (GLib.Error e) {
				GLib.warning("Cannot convert fake file to real (%s): %s", file.path, e.message);
			}
		}

		/**
		 * Handle a new folder added to overlay.
		 * 
		 * Creates the directory on disk, copies permissions, and adds the folder
		 * to the project tree in ProjectManager.
		 * 
		 * @param overlay_path Path to folder in overlay
		 * @param folder Folder object representing the added folder
		 */
		private async void folder_added(string overlay_path, OLLMfiles.Folder folder)
		{
			// Create directory on disk (parent directories already exist due to sorting)
			try {
				GLib.File.new_for_path(folder.path).make_directory(null);
			} catch (GLib.Error e) {
				GLib.warning("Cannot create directory (%s): %s", folder.path, e.message);
				return;
			}
			
			// Copy directory permissions (existing)
			this.copy_permissions(overlay_path, folder.path);
			
			// Add folder to project tree (use existing folder object from Monitor)
			// Ignored folders still need to be saved to DB
			var parent_dir_path = GLib.Path.get_dirname(folder.path);
			var found_base_folder = this.project.project_files.find_container_of(parent_dir_path);
			
			// Ensure parent folder chain exists (creates missing parents)
			// Pass a dummy file path in the parent to ensure parent exists without creating our folder
			var dummy_file_in_parent = GLib.Path.build_filename(parent_dir_path, ".dummy");
			var parent_folder = yield found_base_folder.make_children(dummy_file_in_parent);
			
			// Use existing folder object from Monitor - set parent and add to project tree
			folder.parent = parent_folder;
			folder.parent_id = parent_folder.id;
			parent_folder.children.append(folder);
			
			// Add to project's folder_map
			this.project.project_files.folder_map.set(folder.path, folder);
			
			// Save to database
			folder.saveToDB(this.project.manager.db, null, false);
		}

		/**
		 * Handle a file removed from overlay.
		 * 
		 * Creates a backup, deletes the file from disk, clears the buffer if it exists,
		 * and saves to database.
		 * 
		 * @param file File object representing the removed file
		 */
		private async void file_removed(OLLMfiles.File file)
		{
			// Create backup (all deleted files are in database, id > 0)
			// Skip backup for ignored files
			if (!file.is_ignored) {
				try {
					yield file.create_backup();
				} catch (GLib.Error e) {
					GLib.warning("Cannot create backup for deleted file (%s): %s", file.path, e.message);
				}
			}
			
			// Delete file from disk
			try {
				GLib.FileUtils.unlink(file.path);
			} catch (GLib.Error e) {
				GLib.warning("Cannot delete file from real path (%s): %s", file.path, e.message);
				return;
			}
			
			// Clear buffer contents to empty (only if buffer already exists)
			if (file.buffer != null) {
				try {
					yield file.buffer.clear();
				} catch (GLib.Error e) {
					GLib.warning("Cannot clear buffer for deleted file (%s): %s", file.path, e.message);
				}
			}
			
			// Remove from parent's children list
			file.parent.children.remove(file);
			
			// Remove from ProjectFiles
			if (this.project.project_files.child_map.has_key(file.path)) {
				this.project.project_files.remove(this.project.project_files.child_map.get(file.path));
			}
			
			// Save to database
			file.saveToDB(this.project.manager.db, null, false);
		}

		/**
		 * Handle a folder removed from overlay.
		 * 
		 * Recursively deletes the directory from disk and saves to database.
		 * 
		 * @param folder Folder object representing the removed folder
		 */
		private async void folder_removed(OLLMfiles.Folder folder)
		{
			// Delete directory from disk
			try {
				this.recursive_delete(folder.path);
			} catch (GLib.Error e) {
				GLib.warning("Cannot delete directory from real path (%s): %s", folder.path, e.message);
				return;
			}
			
			// Remove from parent's children list
			folder.parent.children.remove(folder);
			
			// Remove from ProjectFiles
			if (this.project.project_files.folder_map.has_key(folder.path)) {
				this.project.project_files.folder_map.unset(folder.path);
			}
			
			// Save to database
			folder.saveToDB(this.project.manager.db, null, false);
		}

		/**
		 * Recursively delete a directory and all its contents.
		 * 
		 * @param dir_path Path to directory to delete
		 * @throws Error if deletion fails
		 */
		private void recursive_delete(string dir_path) throws Error
		{
			GLib.debug("recursive_delete: attempting to delete %s", dir_path);
			var dir = GLib.File.new_for_path(dir_path);
			
			// Change directory permissions to make it accessible (directories only)
			try {
				dir.set_attribute_uint32(
					GLib.FileAttribute.UNIX_MODE,
					0755,  // rwxr-xr-x - make directory accessible
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				// If we can't change permissions, try to continue anyway
				GLib.debug("recursive_delete: cannot change permissions on %s: %s", dir_path, e.message);
			}
			
			// Recursively delete directory contents
			var enumerator = dir.enumerate_children(
				GLib.FileAttribute.STANDARD_NAME + "," + GLib.FileAttribute.STANDARD_TYPE,
				GLib.FileQueryInfoFlags.NONE,
				null
			);
			
			GLib.FileInfo? file_info;
			while ((file_info = enumerator.next_file(null)) != null) {
				var child_path = GLib.Path.build_filename(dir_path, file_info.get_name());
				
				// Recurse for subdirectories, delete files directly
				if (file_info.get_file_type() == GLib.FileType.DIRECTORY) {
					this.recursive_delete(child_path);
					continue;
				}
				GLib.FileUtils.unlink(child_path);
			}
			
			// Delete the directory itself
			dir.delete(null);
		}

		/**
		 * Clean up overlay directory.
		 * 
		 * Recursively deletes the upper directory and removes the remaining overlay
		 * directory structure. This should be called after copy_files() is complete.
		 * 
		 * Note: Overlay mounting/unmounting is handled by bubblewrap, so we only
		 * need to clean up the directory structure.
		 * 
		 * @throws GLib.IOError if directory removal fails
		 */
		public void cleanup() throws Error
		{
			// Recursively delete upper directory (contains all overlay changes)
			try {
				this.recursive_delete(GLib.Path.build_filename(this.overlay_dir, "upper"));
			} catch (GLib.Error e) {
				GLib.warning("Failed to delete upper directory: %s", e.message);
			}
			
			// Recursively delete work directory
			try {
				this.recursive_delete(GLib.Path.build_filename(this.overlay_dir, "work"));
			} catch (GLib.Error e) {
				GLib.warning("Failed to delete work directory: %s", e.message);
			}
			
			// Try to remove overlay directory (should succeed after work and upper are deleted)
			try {
				GLib.FileUtils.unlink(this.overlay_dir);
			} catch (GLib.Error e) {
				GLib.warning("Failed to remove overlay directory: %s", e.message);
			}
		}


		/**
		 * Copy file permissions (rwx only) from overlay file to real file.
		 * 
		 * @param overlay_path Overlay file path
		 * @param real_path Real file path
		 */
		private void copy_permissions(string overlay_path, string real_path)
		{
			// Get overlay file permissions: Query GLib.FileAttribute.UNIX_MODE from overlay file
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
			
			// Get real file permissions: Query GLib.FileAttribute.UNIX_MODE from real file
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
			
			// If permissions differ: Set real file permissions to match overlay file permissions
			var overlay_mode = overlay_info.get_attribute_uint32(GLib.FileAttribute.UNIX_MODE);
			var real_mode = real_info.get_attribute_uint32(GLib.FileAttribute.UNIX_MODE);
			
			// Only compare rwx bits (mask with 0777)
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
				return;
			}
		}
	}
}

