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
	 * Filesystem monitor using inotify (via GLib.FileMonitor) to track file changes
	 * during command execution. Tracks files/folders that were written/added/modified/deleted
	 * and maintains simple HashMaps of changes (overlay path => FileBase).
	 * 
	 * FIXME: This monitor does not handle the following edge cases:
	 * - File/directory type changes: Deleting a file and replacing it with a directory
	 * (or vice versa) is not properly handled
	 * - CRITICAL / URGENT Folder renames: Renaming folders may break add/remove tracking - if a folder is renamed,
	 * files within it may appear as added/removed rather than moved, causing incorrect backup
	 * behavior and database state
	 */
	public class Monitor : Object
	{
		/**
		 * HashMap of files/folders that were created during monitoring.
		 * Key: Overlay path (e.g., "/home/alan/.cache/ollmchat/overlay-12345/upper/overlay1/src/main.c")
		 * Value: File or Folder object (id = 0, not in database)
		 * Contains only files/folders NOT in ProjectFiles (new files).
		 */
	public Gee.HashMap<string, OLLMfiles.FileBase> added { get; private set; 
			default = new Gee.HashMap<string, OLLMfiles.FileBase>(); }
		
		/**
		 * HashMap of files/folders that were deleted during monitoring.
		 * Key: Overlay path (e.g., "/home/alan/.cache/ollmchat/overlay-12345/upper/overlay1/src/main.c")
		 * Value: File or Folder object from ProjectFiles
		 * Contains only files/folders FROM ProjectFiles (existing files that were deleted).
		 */
		public Gee.HashMap<string, OLLMfiles.FileBase> removed { get; private set;
			default = new Gee.HashMap<string, OLLMfiles.FileBase>(); }
		
		/**
		 * HashMap of files that were modified during monitoring.
		 * Key: Overlay path (e.g., "/home/alan/.cache/ollmchat/overlay-12345/upper/overlay1/src/main.c")
		 * Value: File object from ProjectFiles
		 * Contains only files FROM ProjectFiles (existing files that were modified).
		 */
		public Gee.HashMap<string, OLLMfiles.FileBase> updated { get; private set;
			default = new Gee.HashMap<string, OLLMfiles.FileBase>(); }
		
		// Private fields
		private OLLMfiles.Folder project_folder;
		private string base_path;
		private Gee.HashMap<string, string> overlay_map;
		private Gee.HashMap<GLib.FileMonitor, OLLMfiles.Folder> monitors { get; set; 
			default = new Gee.HashMap<GLib.FileMonitor, OLLMfiles.Folder>(); }
		private Gee.HashMap<GLib.FileMonitor, ulong> signal_handlers { get; set; 
			default = new Gee.HashMap<GLib.FileMonitor, ulong>(); }
		private bool is_monitoring = false;
		
		/**
		 * Constructor.
		 * 
		 * @param project_folder Project folder (provides access to project_files property)
		 * @param base_path Base path of the overlay (e.g., "/home/alan/.cache/ollmchat/overlay-12345/upper")
		 * @param overlay_map Maps overlay path segments to real project paths (e.g., "overlay1" -> "/home/alan/project")
		 */
		public Monitor(OLLMfiles.Folder project_folder, string base_path, Gee.HashMap<string, string> overlay_map) throws Error
		{
			this.project_folder = project_folder;
			this.base_path = base_path;
			this.overlay_map = overlay_map;
		}
		
		/**
		 * Begin monitoring the overlay subdirectories for filesystem changes.
		 * 
		 * @throws GLib.IOError if monitoring cannot be started
		 */
		public void start() throws Error
		{
			
			foreach (var entry in this.overlay_map.entries) {
				var overlay_subdir_path = GLib.Path.build_filename(this.base_path, entry.key);
				var file = GLib.File.new_for_path(overlay_subdir_path);
				
				if (!file.query_exists()) {
					try {
						file.make_directory_with_parents(null);
					} catch (GLib.Error e) {
						throw new GLib.IOError.FAILED("Cannot create overlay subdirectory %s: %s".printf(overlay_subdir_path, e.message));
					}
				}
				
				GLib.FileMonitor monitor;
				try {
					monitor = file.monitor_directory(GLib.FileMonitorFlags.WATCH_MOVES, null);
				} catch (GLib.Error e) {
					throw new GLib.IOError.FAILED("Cannot create monitor for %s: %s".printf(overlay_subdir_path, e.message));
				}
				
				this.signal_handlers.set(monitor, 
						monitor.changed.connect(this.on_file_changed));
				
				var folder = this.project_folder.project_files.folder_map.get(entry.value);
				
				if (folder == null) {
					folder = new OLLMfiles.Folder(this.project_folder.manager);
					folder.path = entry.value;
				}
				this.monitors.set(monitor, folder);
			}
			
			this.is_monitoring = true;
		}
		
		/**
		 * Stop all monitoring and finalize change lists.
		 * Uses async/await with idle callback to ensure all pending inotify events are processed.
		 */
		public async void stop()
		{
			
			
			
			
			Idle.add(() => {
				this.is_monitoring = false;
				foreach (var monitor in this.monitors.keys) {
					if (this.signal_handlers.has_key(monitor)) {
						monitor.disconnect(this.signal_handlers.get(monitor));
					}
					monitor.cancel();
				}
				
				this.monitors.clear();
				this.signal_handlers.clear();
				
				stop.callback();
				return false;
			});
			
			yield;
		}
		
		/**
		* Event handler for filesystem change events from GLib.FileMonitor.
		*/
		private void on_file_changed(GLib.File file, GLib.File? other_file, GLib.FileMonitorEvent event)
		{
			var overlay_path = file.get_path();
			if (overlay_path == null) {
				return;
			}
			
			var real_path = this.to_real_path(overlay_path);
			GLib.debug("Monitor.on_file_changed: event=%s, overlay_path=%s, real_path=%s", 
				event.to_string(), overlay_path, real_path);
			
			switch (event) {
				case GLib.FileMonitorEvent.CREATED:
					if (GLib.FileUtils.test(overlay_path, GLib.FileTest.IS_DIR)) {
						this.handle_directory_created(overlay_path, real_path);
						break;
					}
					this.handle_file_created(overlay_path, real_path);
					break;
					
				case GLib.FileMonitorEvent.CHANGED:
					if (GLib.FileUtils.test(overlay_path, GLib.FileTest.IS_REGULAR)) {
						this.handle_file_modified(overlay_path, real_path);
					}
					break;
					
				case GLib.FileMonitorEvent.ATTRIBUTE_CHANGED:
					if (GLib.FileUtils.test(overlay_path, GLib.FileTest.IS_REGULAR)) {
						this.handle_file_modified(overlay_path, real_path);
					}
					break;
					
				case GLib.FileMonitorEvent.DELETED:
					this.handle_file_deleted(overlay_path, real_path);
					break;
					
				case GLib.FileMonitorEvent.MOVED:
				case GLib.FileMonitorEvent.RENAMED:
					// MOVED: File moved between directories (deprecated, requires SEND_MOVED flag)
					// RENAMED: File renamed within the same directory (requires WATCH_MOVES flag)
					// Both events: treat source as deleted and destination as created
					var overlay_source_path = file.get_path();
					if (overlay_source_path != null) {
						this.handle_file_deleted(overlay_source_path, this.to_real_path(overlay_source_path));
					}
					
					if (other_file == null) {
						break;
					}
					
					var overlay_dest_path = other_file.get_path();
					if (overlay_dest_path == null) {
						break;
					}
					
					var real_dest_path = this.to_real_path(overlay_dest_path);
					if (GLib.FileUtils.test(overlay_dest_path, GLib.FileTest.IS_DIR)) {
						this.handle_directory_created(overlay_dest_path, real_dest_path);
						break;
					}
					this.handle_file_created(overlay_dest_path, real_dest_path);
					break;
					
				case GLib.FileMonitorEvent.MOVED_IN:
					// Always treat MOVED_IN as an addition first, then handle deletion if needed
					// In overlayfs, file deletions can appear as MOVED_IN events when whiteout files are created
					// Check if file was already deleted (in removed) - if so, deletion already handled
					bool was_in_removed = this.removed.has_key(overlay_path);
					
					if (GLib.FileUtils.test(overlay_path, GLib.FileTest.IS_DIR)) {
						this.handle_directory_created(overlay_path, real_path);
					} else {
						this.handle_file_created(overlay_path, real_path);
					}
					
					// If file was in removed, deletion already handled - return early
					if (was_in_removed) {
						break;
					}
					
					// Only check for whiteout/EXISTS if file wasn't already deleted
					// Check if this is a whiteout file (character device with 0/0 device number)
					if (this.is_whiteout(overlay_path)) {
						this.handle_file_deleted(overlay_path, real_path);
						break;
					}
					if (!GLib.FileUtils.test(overlay_path, GLib.FileTest.EXISTS)) {
						this.handle_file_deleted(overlay_path, real_path);
						break;
					}
					break;
					
				case GLib.FileMonitorEvent.MOVED_OUT:
					// File moved out of monitored directory - treat as deletion
					this.handle_file_deleted(overlay_path, real_path);
					break;
					
				default:
					break;
			}
		}
			
		/**
		* Handle creation of a new directory.
		* Track it in `added` if it doesn't exist in ProjectFiles.
		* Create a new FileMonitor for the directory since GLib.FileMonitor doesn't monitor recursively.
		* 
		* @param overlay_path Overlay path to the newly created directory
		* @param real_path Real project path to the newly created directory
		*/
		private void handle_directory_created(string overlay_path, string real_path)
		{
			GLib.debug("Monitor.handle_directory_created: overlay_path=%s, real_path=%s", overlay_path, real_path);
			
			// If directory already exists in project, add it to 'updated' (not 'added')
			// Note: In overlayfs, modifying an existing directory (e.g., MOVED_IN event) causes it to be tracked,
			// but it's a modification, not a new directory creation
			if (this.project_folder.project_files.folder_map.has_key(real_path)) {
				var existing_folder = this.project_folder.project_files.folder_map.get(real_path);
				// Directory exists and was modified - treat as modification
				this.updated.set(overlay_path, existing_folder);
				
				// Ensure monitor is set up for this directory so we can detect files moving into it
		
				try {
					var monitor = GLib.File.new_for_path(overlay_path).monitor_directory(GLib.FileMonitorFlags.NONE, null);
					this.monitors.set(monitor, existing_folder);
					this.signal_handlers.set(monitor, monitor.changed.connect(this.on_file_changed));
				} catch (GLib.Error e) {
					GLib.warning("Monitor.handle_directory_created: Could not create monitor for existing directory %s: %s", overlay_path, e.message);
				}
			
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
				GLib.warning("Monitor.handle_directory_created: Could not query folder info for %s: %s", overlay_path, e.message);
				return;
			}
			
			var new_folder = new OLLMfiles.Folder.new_from_info(
				this.project_folder.manager,
				this.project_folder,
				folder_info,
				real_path
			);
			
			// Set up monitor first
			try {
				var monitor = GLib.File.new_for_path(overlay_path).monitor_directory(GLib.FileMonitorFlags.NONE, null);
				this.monitors.set(monitor, new_folder);
				this.signal_handlers.set(monitor, monitor.changed.connect(this.on_file_changed));
			} catch (GLib.Error e) {
				GLib.warning("Monitor.handle_directory_created: Could not create monitor for subdirectory %s: %s", overlay_path, e.message);
			}
			
			// Set is_ignored based on parent folder
			new_folder.is_ignored = false;
			var parent_folder = this.project_folder.project_files.folder_map.get(GLib.Path.get_dirname(real_path));
			if (parent_folder == null) {
				parent_folder = (this.added.get(GLib.Path.get_dirname(overlay_path)) as OLLMfiles.Folder);
			}
			
			if (parent_folder.is_ignored) {
				new_folder.is_ignored = true;
				this.added.set(overlay_path, new_folder);
				return;
			}
			
			if (!this.project_folder.manager.git_provider.repository_exists(parent_folder)) {
				this.added.set(overlay_path, new_folder);
				return;
			}
			
			var workdir_path = this.project_folder.manager.git_provider.get_workdir_path(parent_folder);
			if (workdir_path == null || !real_path.has_prefix(workdir_path)) {
				this.added.set(overlay_path, new_folder);
				return;
			}
			
			var relative_path = real_path.substring(workdir_path.length);
			if (relative_path.has_prefix("/")) {
				relative_path = relative_path.substring(1);
			}
			if (this.project_folder.manager.git_provider.path_is_ignored(parent_folder, relative_path)) {
				new_folder.is_ignored = true;
			}
			
			this.added.set(overlay_path, new_folder);
		}
			
		/**
		* Handle creation of a new file.
		* Track it in `added` if it doesn't exist in ProjectFiles, otherwise add to `updated`.
		* 
		* @param overlay_path Overlay path to the newly created file
		* @param real_path Real project path to the newly created file
		*/
		private void handle_file_created(string overlay_path, string real_path)
		{
			GLib.debug("Monitor.handle_file_created: overlay_path=%s, real_path=%s", overlay_path, real_path);
			
			// Check if this is a whiteout file (character device with 0/0 device number).
			// In overlayfs, file deletions can appear as CREATED events when whiteout files are created.
			if (this.is_whiteout(overlay_path)) {
				this.handle_file_deleted(overlay_path, real_path);
				return;
			}
			
			// Check if there's a deleted file of the same type at this path
			if (this.removed.has_key(overlay_path)) {
				var removed_filebase = this.removed.get(overlay_path);
				
				// Check if types match (both File or both FileAlias, and both Folder or both not Folder)
				bool overlay_is_symlink = GLib.FileUtils.test(overlay_path, GLib.FileTest.IS_SYMLINK);
				bool removed_is_symlink = (removed_filebase is OLLMfiles.FileAlias);
				bool overlay_is_folder = GLib.FileUtils.test(overlay_path, GLib.FileTest.IS_DIR);
				bool removed_is_folder = (removed_filebase is OLLMfiles.Folder);
				
				if (overlay_is_symlink == removed_is_symlink && overlay_is_folder == removed_is_folder) {
					// Same type: remove from removed, add to updated
					this.removed.unset(overlay_path);
					this.updated.set(overlay_path, removed_filebase);
					return;
				}
				// Different type: keep in removed, new file will be added below
			} else {
				// only check these if not in removed ...
				if (this.project_folder.project_files.folder_map.has_key(real_path)) {
					this.handle_directory_created(overlay_path, real_path);
					return;
				}
			
				// Check if a file already exists at this path in ProjectFiles
				// Note: In overlayfs, modifying an existing file causes it to be copied up to the upper layer,
				// which appears as a CREATED event. When copied from base, the type doesn't change, so this is a modification.
				if (this.project_folder.project_files.child_map.has_key(real_path)) {
					var existing_filebase = this.project_folder.project_files.child_map.get(real_path).file;
					// File exists and was copied up by overlayfs - treat as modification
					this.updated.set(overlay_path, existing_filebase);
					return;
				}
			}
			// If we get here, this is a new file being created.
			
			try {
				var new_file = this.create_filebase_from_path(overlay_path, real_path);
				
				// Set is_ignored based on parent folder
				new_file.is_ignored = false;
				var parent_folder = this.project_folder.project_files.folder_map.get(GLib.Path.get_dirname(real_path));
				if (parent_folder == null) {
					parent_folder = (this.added.get(GLib.Path.get_dirname(overlay_path)) as OLLMfiles.Folder);
				}
				
				if (parent_folder.is_ignored) {
					new_file.is_ignored = true;
					this.added.set(overlay_path, new_file);
					return;
				}
				
				if (!this.project_folder.manager.git_provider.repository_exists(parent_folder)) {
					this.added.set(overlay_path, new_file);
					return;
				}
				
				var workdir_path = this.project_folder.manager.git_provider.get_workdir_path(parent_folder);
				if (workdir_path == null || !real_path.has_prefix(workdir_path)) {
					this.added.set(overlay_path, new_file);
					return;
				}
				
				var relative_path = real_path.substring(workdir_path.length);
				if (relative_path.has_prefix("/")) {
					relative_path = relative_path.substring(1);
				}
				if (this.project_folder.manager.git_provider.path_is_ignored(parent_folder, relative_path)) {
					new_file.is_ignored = true;
				}
				
				this.added.set(overlay_path, new_file);
			} catch (GLib.Error e) {
				GLib.warning("Monitor.handle_file_created: Could not create filebase for %s: %s", overlay_path, e.message);
			}
		}
			
		/**
		* Handle modification of an existing file.
		* If already in `added` or `updated`, do nothing (NOOP).
		* If in `removed`, move to `updated`.
		* 
		* @param overlay_path Overlay path to the modified file
		* @param real_path Real project path to the modified file
		*/
		private void handle_file_modified(string overlay_path, string real_path)
		{
			GLib.debug("Monitor.handle_file_modified: overlay_path=%s, real_path=%s", overlay_path, real_path);
			
			if (this.added.has_key(overlay_path)) {
				return;
			}
			
			if (this.updated.has_key(overlay_path)) {
				return;
			}
			
			if (this.removed.has_key(overlay_path)) {
				var filebase = this.removed.get(overlay_path);
				// Only move to updated if type matches (File→File or FileAlias→FileAlias, and Folder→Folder or not Folder→not Folder)
				// If type doesn't match, keep in removed and handle_file_created will add new file to added
				bool overlay_is_symlink = GLib.FileUtils.test(overlay_path, GLib.FileTest.IS_SYMLINK);
				bool existing_is_symlink = (filebase is OLLMfiles.FileAlias);
				bool overlay_is_folder = GLib.FileUtils.test(overlay_path, GLib.FileTest.IS_DIR);
				bool existing_is_folder = (filebase is OLLMfiles.Folder);
				
				if (overlay_is_symlink == existing_is_symlink && overlay_is_folder == existing_is_folder) {
					// Type matches: move to updated
					this.removed.unset(overlay_path);
					this.updated.set(overlay_path, filebase);
				}
				// If type doesn't match, keep in removed (will be handled by handle_file_created)
				return;
			}
			
			// If we get here, the file is not in added/updated/removed
			// Files can't be modified unless they've been created first, so this must be a new file
			this.handle_file_created(overlay_path, real_path);
		}
			
		/**
		* Handle deletion of a file or directory.
		* Remove from `added` or `updated` and add to `removed` if from ProjectFiles.
		* 
		* @param overlay_path Overlay path to the deleted file
		* @param real_path Real project path to the deleted file
		*/
		private void handle_file_deleted(string overlay_path, string real_path)
		{
			GLib.debug("Monitor.handle_file_deleted: overlay_path=%s, real_path=%s", overlay_path, real_path);
			
			if (this.added.has_key(overlay_path)) {
				var filebase = this.added.get(overlay_path);
				this.added.unset(overlay_path);
				
				// If file was added and deleted, and id < 1, it never existed in the database
				// So just remove it from tracking (don't add to removed)
				if (filebase.id < 1) {
					GLib.debug("no file id");
					return;
				}
				
				// File existed in database, so track its deletion
				this.removed.set(overlay_path, filebase);
				GLib.debug("added to deleted");
				return;
			}
			
			if (this.updated.has_key(overlay_path)) {
				// File was updated (modified in overlay), then deleted - move to removed
				var filebase = this.updated.get(overlay_path);
				this.updated.unset(overlay_path);
				this.removed.set(overlay_path, filebase);
				return;
			}
			
			// Check if file/directory exists in project_files (was there before monitoring started)
			// Check folder_map first (directories)
			if (this.project_folder.project_files.folder_map.has_key(real_path)) {
				var folder = this.project_folder.project_files.folder_map.get(real_path);
				this.removed.set(overlay_path, folder);
				return;
			}
			
			// Check child_map (files)
			if (this.project_folder.project_files.child_map.has_key(real_path)) {
				var project_file = this.project_folder.project_files.child_map.get(real_path);
				this.removed.set(overlay_path, project_file.file);
				return;
			}
			
			// File not in added/updated/project_files, so it was never tracked - nothing to do
		}
			
		/**
		* Create a FileBase object (File or FileAlias) from a filesystem path.
		* Used for tracking files that don't exist in ProjectFiles. The file is known to exist from the inotify event, so no existence checks are needed.
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
			
			// Check if it's a symlink and create FileAlias if so
			if (file_info.get_is_symlink()) {
				// Find parent folder for FileAlias
				var parent_dir = GLib.Path.get_dirname(real_path);
				var parent_folder = this.project_folder.project_files.folder_map.get(parent_dir);
				if (parent_folder == null) {
					// Parent might be in added list (newly created folder)
					var parent_overlay_dir = GLib.Path.get_dirname(overlay_path);
					parent_folder = (this.added.get(parent_overlay_dir) as OLLMfiles.Folder);
				}
				// If still no parent, use project_folder as fallback
				if (parent_folder == null) {
					parent_folder = this.project_folder;
				}
				
				return new OLLMfiles.FileAlias.new_from_info(
					parent_folder,
					file_info,
					real_path
				);
			}
			
			// Not a symlink, create regular File
			return new OLLMfiles.File.new_from_info(
				this.project_folder.manager,
				this.project_folder,
				file_info,
				real_path
			);
		}
			
		/**
		 * Check if a path is a whiteout file (character device with 0/0 device number).
		 * In overlayfs, whiteout files represent deleted files from the lower layer.
		 * 
		 * @param overlay_path Path to check
		 * @return true if the path is a whiteout file
		 */
		public bool is_whiteout(string overlay_path)
		{
			try {
				var file = GLib.File.new_for_path(overlay_path);
				if (!file.query_exists(null)) {
					return false;
				}
				
				var info = file.query_info(
					GLib.FileAttribute.UNIX_RDEV + "," + GLib.FileAttribute.STANDARD_TYPE,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
				
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
		 */
		public string to_real_path(string overlay_path)
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
	}
}

