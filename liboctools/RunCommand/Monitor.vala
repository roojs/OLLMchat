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
	 * - File aliases (symlinks): Symlinks are not tracked or resolved
	 * - File/directory type changes: Deleting a file and replacing it with a directory
	 * (or vice versa) is not properly handled
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
			
			
			this.is_monitoring = false;
			
			Idle.add(() => {
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
			if (this.project_folder.project_files.folder_map.has_key(real_path)) {
				return;
			}
			
			GLib.FileInfo folder_info;
			try {
				folder_info = GLib.File.new_for_path(overlay_path).query_info(
					GLib.FileAttribute.TIME_MODIFIED,
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
			
			this.added.set(overlay_path, new_folder);
			
			try {
				var monitor = GLib.File.new_for_path(overlay_path).monitor_directory(GLib.FileMonitorFlags.NONE, null);
				this.monitors.set(monitor, new_folder);
				this.signal_handlers.set(monitor, monitor.changed.connect(this.on_file_changed));
			} catch (GLib.Error e) {
				GLib.warning("Monitor.handle_directory_created: Could not create monitor for subdirectory %s: %s", overlay_path, e.message);
			}
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
			if (this.project_folder.project_files.child_map.has_key(real_path)) {
				this.updated.set(overlay_path, this.project_folder.project_files.child_map.get(real_path).file);
				return;
			}
			
			try {
				this.added.set(overlay_path, 
					this.create_filebase_from_path(overlay_path, real_path));
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
			if (this.added.has_key(overlay_path)) {
				return;
			}
			
			if (this.updated.has_key(overlay_path)) {
				return;
			}
			
			if (this.removed.has_key(overlay_path)) {
				var filebase = this.removed.get(overlay_path);
				this.removed.unset(overlay_path);
				this.updated.set(overlay_path, filebase);
				return;
			}
			
			if (this.project_folder.project_files.child_map.has_key(real_path)) {
				this.updated.set(overlay_path, 
					this.project_folder.project_files.child_map.get(real_path).file);
				return;
			}
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
			if (this.added.has_key(overlay_path)) {
				this.added.unset(overlay_path);
				return;
			}
			
			if (this.updated.has_key(overlay_path)) {
				var filebase = this.updated.get(overlay_path);
				this.updated.unset(overlay_path);
				this.removed.set(overlay_path, filebase);
				return;
			}
			
			if (this.project_folder.project_files.child_map.has_key(real_path)) {
				this.removed.set(overlay_path,
					this.project_folder.project_files.child_map.get(real_path).file);
				return;
			}
			
			if (!this.project_folder.project_files.folder_map.has_key(real_path)) {
				return;
			}
			
			this.removed.set(overlay_path, 
				this.project_folder.project_files.folder_map.get(real_path));
			return;
		}
			
		/**
		* Create a File object from a filesystem path.
		* Used for tracking files that don't exist in ProjectFiles. The file is known to exist from the inotify event, so no existence checks are needed.
		* 
		* @param overlay_path Overlay path to the file (used to query file info)
		* @param real_path Real project path to the file (used as the FileBase.path property)
		* @return File object
		* @throws GLib.Error if file info cannot be queried
		*/
		private OLLMfiles.File create_filebase_from_path(string overlay_path, string real_path) throws GLib.Error
		{
			return new OLLMfiles.File.new_from_info(
				this.project_folder.manager,
				this.project_folder,
				GLib.File.new_for_path(overlay_path).query_info(
					GLib.FileAttribute.STANDARD_CONTENT_TYPE + "," + GLib.FileAttribute.TIME_MODIFIED,
					GLib.FileQueryInfoFlags.NONE,
					null
				),
				real_path
			);
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

