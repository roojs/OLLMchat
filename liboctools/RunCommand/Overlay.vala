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
		 * Timestamp when copy_files() started processing changes.
		 * Used for all FileHistory records created during this processing session.
		 */
		private int64 command_timestamp { get; private set; default = 0; }



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
			
			// Set timestamp when processing starts (used for all FileHistory records in this session)
			this.command_timestamp = (new GLib.DateTime.now_local()).to_unix();
			
			// Process deleted files FIRST (this.monitor.removed)
			// Sort entries in reverse order (folders deleted after children)
			var removed_entries = new Gee.ArrayList<string>.wrap(this.monitor.removed.keys.to_array());
			removed_entries.sort((a, b) => {
				return strcmp(b, a); // Reverse sort
			});
			
			foreach (var key in removed_entries) {
				var filebase = this.monitor.removed.get(key);
				
				if (filebase is OLLMfiles.FileAlias) {
					GLib.debug("delete alias");
					yield this.file_removed(filebase as OLLMfiles.File);
					continue;
				}
				
				if (filebase is OLLMfiles.File) {
					GLib.debug("delete file");
					yield this.file_removed(filebase as OLLMfiles.File);
					continue;
				}
				
				if (filebase is OLLMfiles.Folder) {
					GLib.debug("delete folder");
					yield this.folder_removed(filebase as OLLMfiles.Folder);
					continue;
				}
			}
			
			// Process Monitor change lists
			// For modified files (this.monitor.updated)
			foreach (var entry in this.monitor.updated.entries) {
				if (entry.value is OLLMfiles.File || entry.value is OLLMfiles.FileAlias) {
					yield this.file_updated(entry.key, entry.value);
					continue;
				}
			}
			
			// Before processing new files, scan created folders recursively
			// to catch any files that were created before the monitor could detect them
			// Make a copy of entries to avoid modifying added while iterating
			var check = new Gee.HashMap<string, OLLMfiles.FileBase>();
			foreach (var key in this.monitor.added.keys) {
				check.set(key, this.monitor.added.get(key));
			}
			foreach (var key in check.keys) {
				this.scan_folder(key, check.get(key));
			}
			
			// Process new files (this.monitor.added)
			// Sort entries by path (to ensure parent directories are created naturally)
			var added_entries = new Gee.ArrayList<string>.wrap(this.monitor.added.keys.to_array());
			added_entries.sort((a, b) => {
				return strcmp(a, b);
			});
			
			foreach (var key in added_entries) {
				var filebase = this.monitor.added.get(key);
				
				if (filebase is OLLMfiles.File || filebase is OLLMfiles.FileAlias) {
					yield this.file_added(key, filebase);
					continue;
				}
				
				if (filebase is OLLMfiles.Folder) {
					yield this.folder_added(key, filebase as OLLMfiles.Folder);
					continue;
				}
			}
		}

		/**
		 * Scan a folder recursively to find files that were created before
		 * the monitor could detect them.
		 * 
		 * @param overlay_path Overlay path to the folder/file
		 * @param filebase FileBase object (Folder or File) from monitor.added
		 */
		private void scan_folder(string overlay_path, OLLMfiles.FileBase filebase)
		{
			if (!(filebase is OLLMfiles.Folder)) {
				return;
			}
			
			var folder = filebase as OLLMfiles.Folder;
			var overlay_folder = new OLLMfiles.Folder(this.project.manager) {
				path = overlay_path
			};
			
			var overlay_dir = GLib.File.new_for_path(overlay_path);
			if (!overlay_dir.query_exists()) {
				return;
			}
			
			var overlay_items = new Gee.ArrayList<OLLMfiles.FileBase>();
			try {
				overlay_folder.enumerate_directory_contents(overlay_dir, overlay_items);
			} catch (GLib.Error e) {
				GLib.warning("Cannot enumerate overlay folder %s: %s", overlay_path, e.message);
				return;
			}
			
			foreach (var add_item in overlay_items) {
				var overlay_item_path = add_item.path;
				
				if (this.monitor.added.has_key(overlay_item_path)) {
					continue;
				}
				
				add_item.path = this.monitor.to_real_path(overlay_item_path);
				add_item.parent = folder;
				add_item.parent_id = folder.id;
				add_item.is_ignored = folder.is_ignored;
				
				if (add_item.is_ignored || !this.project.manager.git_provider.repository_exists(folder) || add_item is OLLMfiles.Folder) {
					this.monitor.added.set(overlay_item_path, add_item);
					if (add_item is OLLMfiles.Folder) {
						this.scan_folder(overlay_item_path, add_item);
					}
					continue;
				}
				
				var workdir_path = this.project.manager.git_provider.get_workdir_path(folder);
				if (workdir_path != null && add_item.path.has_prefix(workdir_path)) {
					var relative_path = add_item.path.substring(workdir_path.length);
					if (relative_path.has_prefix("/")) {
						relative_path = relative_path.substring(1);
					}
					add_item.is_ignored = this.project.manager.git_provider.path_is_ignored(folder, relative_path);
				}
				
				this.monitor.added.set(overlay_item_path, add_item);
				
				if (add_item is OLLMfiles.Folder) {
					this.scan_folder(overlay_item_path, add_item);
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
		 * @param filebase FileBase object (File or FileAlias) representing the updated file
		 */
		private async void file_updated(string overlay_path, OLLMfiles.FileBase filebase)
		{
			var file = filebase as OLLMfiles.File;
			
			// Create FileHistory object for this change
			try {
				var file_history = new OLLMfiles.FileHistory(
					this.project.manager.db,
					filebase,
					"modified",
					this.command_timestamp
				);
				yield file_history.commit();
			} catch (GLib.Error e) {
				GLib.warning("Cannot create FileHistory for modified file (%s): %s", filebase.path, e.message);
			}
			
			// Check if filebase is a symlink (FileAlias)
			// Monitor ensures type matches, so if filebase is FileAlias, overlay is also a symlink
			if (filebase is OLLMfiles.FileAlias) {
				// Handle symlink: read target and create symlink
				try {
					string? symlink_target = GLib.FileUtils.read_link(overlay_path);
					if (symlink_target == null) {
						GLib.warning("Cannot read symlink target from overlay (%s)", overlay_path);
						return;
					}
					
					// Rationalize symlink target: if it's an absolute path pointing to overlay,
					// convert it to the corresponding real path
					if (GLib.Path.is_absolute(symlink_target)) {
						symlink_target = this.monitor.to_real_path(symlink_target);
					}
					
					// Remove existing file/symlink if it exists
					if (GLib.FileUtils.test(filebase.path, GLib.FileTest.EXISTS)) {
						GLib.FileUtils.unlink(filebase.path);
					}
					
					// Create symlink in real filesystem
					GLib.debug("Overlay.file_updated: creating symlink '%s' -> '%s'", filebase.path, symlink_target);
					Posix.symlink(symlink_target, filebase.path);
					
					// Copy file permissions (existing)
					this.copy_permissions(overlay_path, filebase.path);
					
					// Symlinks don't have buffers, so we're done
					return;
				} catch (GLib.Error e) {
					GLib.warning("Cannot create symlink from overlay to real path (%s -> %s): %s", 
						overlay_path, filebase.path, e.message);
					return;
				}
			} 
			// Handle regular file: copy from overlay to real path
			try {
				GLib.File.new_for_path(overlay_path).copy(
					GLib.File.new_for_path(filebase.path),
					GLib.FileCopyFlags.OVERWRITE,
					null,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("Cannot copy file from overlay to real path (%s -> %s): %s", 
					overlay_path, filebase.path, e.message);
				return;
			}
			
			// Copy file permissions (existing)
			this.copy_permissions(overlay_path, filebase.path);
			
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
		 * @param filebase FileBase object (File or FileAlias) representing the added file
		 */
		private async void file_added(string overlay_path, OLLMfiles.FileBase filebase)
		{
			// Create FileHistory object for this change
			// For new files, filebase_id will be 0 (file doesn't have id yet)
			// Note: FileHistory.commit() only creates backups for "modified" or "deleted" files,
			// not for "added" files, so symlinks won't trigger backup creation
			try {
				var file_history = new OLLMfiles.FileHistory(
					this.project.manager.db,
					filebase,
					"added",
					this.command_timestamp
				);
				yield file_history.commit();
			} catch (GLib.Error e) {
				GLib.warning("Cannot create FileHistory for added file (%s): %s", filebase.path, e.message);
			}
			
			// Check if filebase is a symlink (FileAlias)
			// Monitor creates FileAlias objects for symlinks, so if filebase is FileAlias, overlay is also a symlink
			if (filebase is OLLMfiles.FileAlias) {
				// Handle symlink: read target and create symlink
				try {
					string? symlink_target = GLib.FileUtils.read_link(overlay_path);
					if (symlink_target == null) {
						GLib.warning("Cannot read symlink target from overlay (%s)", overlay_path);
						return;
					}
					
					// Rationalize symlink target: if it's an absolute path pointing to overlay,
					// convert it to the corresponding real path
					if (GLib.Path.is_absolute(symlink_target)) {
						symlink_target = this.monitor.to_real_path(symlink_target);
					}
					
					// Ensure parent directory exists - not neeed by design.
					
					// Remove existing file/symlink if it exists
					if (GLib.FileUtils.test(filebase.path, GLib.FileTest.EXISTS)) {
						GLib.FileUtils.unlink(filebase.path);
					}
					
					// Create symlink in real filesystem
					GLib.debug("Overlay.file_added: creating symlink '%s' -> '%s'", filebase.path, symlink_target);
					Posix.symlink(symlink_target, filebase.path);
					
					// Copy file permissions (existing)
					this.copy_permissions(overlay_path, filebase.path);
				} catch (GLib.Error e) {
					GLib.warning("Cannot create symlink from overlay to real path (%s -> %s): %s", 
						overlay_path, filebase.path, e.message);
					return;
				}
				return;
			}
			
			// Handle regular file: copy from overlay to real path
			// convert_fake_file_to_real() handles parent directory creation via make_children()
			try {
				GLib.File.new_for_path(overlay_path).copy(
					GLib.File.new_for_path(filebase.path),
					GLib.FileCopyFlags.OVERWRITE,
					null,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("Cannot copy file from overlay to real path (%s -> %s): %s", 
					overlay_path, filebase.path, e.message);
				return;
			}
			
			// Copy file permissions (existing)
			this.copy_permissions(overlay_path, filebase.path);
			
			
			// Create fake file and convert to real (existing method handles parent directory creation)
			// Ignored files still need to be saved to DB
			// Only do this for File objects, not FileAlias (FileAlias is already a real object)
			var file = filebase as OLLMfiles.File;
			
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
			// Create FileHistory object for this change
			// For new folders, filebase_id will be 0 (folder doesn't have id yet)
			try {
				var file_history = new OLLMfiles.FileHistory(
					this.project.manager.db,
					folder,
					"added",
					this.command_timestamp
				);
				yield file_history.commit();
			} catch (GLib.Error e) {
				GLib.warning("Cannot create FileHistory for added folder (%s): %s", folder.path, e.message);
			}
			
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
			// Create FileHistory object for this change
			try {
				var file_history = new OLLMfiles.FileHistory(
					this.project.manager.db,
					file,
					"deleted",
					this.command_timestamp
				);
				yield file_history.commit();
			} catch (GLib.Error e) {
				GLib.warning("Cannot create FileHistory for deleted file (%s): %s", file.path, e.message);
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
			GLib.debug("remove %s", folder.path);
			// Create FileHistory object for this change
			try {
				var file_history = new OLLMfiles.FileHistory(
					this.project.manager.db,
					folder,
					"deleted",
					this.command_timestamp
				);
				yield file_history.commit();
			} catch (GLib.Error e) {
				GLib.warning("Cannot create FileHistory for deleted folder (%s): %s", folder.path, e.message);
			}
			
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
			GLib.debug("cleanup");
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
				GLib.FileUtils.remove(this.overlay_dir);
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

