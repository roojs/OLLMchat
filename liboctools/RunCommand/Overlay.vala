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
		 * Created in constructor, started in mount(), stopped before copying files.
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
			
			// Create Monitor instance (will be started in mount())
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
		 * - {overlay_dir}/upper/overlay1/ (for first project root)
		 * - {overlay_dir}/upper/overlay2/ (for second project root)
		 * - {overlay_dir}/upper/overlay3/ (for third project root)
		 * - etc.
		 * - {overlay_dir}/work/ (work directory for overlayfs)
		 * - {overlay_dir}/merged/ (mount point for overlayfs)
		 * 
		 * Also builds overlay_map HashMap mapping subdirectory names to real project paths.
		 * 
		 * @throws GLib.IOError if directory creation fails
		 */
		public void create() throws Error
		{
			try {
				// Create overlay_dir directory (with parents if needed)
				GLib.File.new_for_path(this.overlay_dir).make_directory_with_parents(null);
				
				// Create upper directory
				GLib.File.new_for_path(
					GLib.Path.build_filename(this.overlay_dir, "upper")
				).make_directory_with_parents(null);
				
				// Create work directory
				GLib.File.new_for_path(
					GLib.Path.build_filename(this.overlay_dir, "work")
				).make_directory_with_parents(null);
				
				// Create merged directory (mount point)
				GLib.File.new_for_path(
					GLib.Path.build_filename(this.overlay_dir, "merged")
				).make_directory_with_parents(null);
				
				// Iterate over roots to create subdirectories and build overlay_map
				var entries_array = this.roots.entries.to_array();
				for (int i = 0; i < entries_array.length; i++) {
					var entry = entries_array[i];
					var subdirectory_name = "overlay" + (i + 1).to_string();
					
					// Create subdirectory
					GLib.File.new_for_path(
						GLib.Path.build_filename(this.overlay_dir, "upper", subdirectory_name)
					).make_directory_with_parents(null);
					
					// Add to overlay_map
					this.overlay_map.set(subdirectory_name, entry.key);
				}
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Cannot create overlay directory structure: " + e.message);
			}
		}

		/**
		 * Mount overlay filesystem and start monitoring.
		 * 
		 * Mounts the overlay filesystem and starts the Monitor to track changes.
		 * 
		 * The mount command format:
		 * mount -t overlay overlay -o lowerdir={project.path},upperdir={overlay_dir}/upper,workdir={overlay_dir}/work {overlay_dir}/merged
		 * 
		 * @throws GLib.IOError if mount fails or monitor start fails
		 */
		public void mount() throws Error
		{
			// Find full path to mount executable
			var mount_path = GLib.Environment.find_program_in_path("mount");
			if (mount_path == null) {
				throw new GLib.IOError.NOT_FOUND("mount command not found in PATH");
			}
			
			// Build mount command string
			var command = mount_path + " -t overlay overlay -o lowerdir=" + this.project.path +
				",upperdir=" + GLib.Path.build_filename(this.overlay_dir, "upper") +
				",workdir=" + GLib.Path.build_filename(this.overlay_dir, "work") + " " +
				GLib.Path.build_filename(this.overlay_dir, "merged");
			
			// Execute mount command using Process.spawn_command_line_sync()
			string stdout;
			string stderr;
			int exit_status;
			try {
				GLib.Process.spawn_command_line_sync(command, out stdout, out stderr, out exit_status);
			} catch (GLib.SpawnError e) {
				throw new GLib.IOError.FAILED("Cannot execute mount command: " + e.message);
			}
			
			// Check exit status: If non-zero, throw GLib.IOError.FAILED with stderr message
			if (exit_status != 0) {
				throw new GLib.IOError.FAILED("Mount command failed: " + stderr);
			}
			
			// Start Monitor: this.monitor.start() (monitor was created in constructor)
			this.monitor.start();
		}

		/**
		 * Unmount overlay filesystem using umount.
		 * 
		 * Unmounts the overlay filesystem.
		 * 
		 * The unmount command format:
		 * umount {overlay_dir}/merged
		 * 
		 * @throws GLib.IOError if unmount fails (e.g., busy, not mounted)
		 */
		public void unmount() throws Error
		{
			// Find full path to umount executable
			var umount_path = GLib.Environment.find_program_in_path("umount");
			if (umount_path == null) {
				throw new GLib.IOError.NOT_FOUND("umount command not found in PATH");
			}
			
			// Build unmount command string
			var command = umount_path + " "
				 + GLib.Path.build_filename(this.overlay_dir, "merged");
			
			// Execute umount command using Process.spawn_command_line_sync()
			string stdout;
			string stderr;
			int exit_status;
			try {
				GLib.Process.spawn_command_line_sync(command, out stdout, out stderr, out exit_status);
			} catch (GLib.SpawnError e) {
				throw new GLib.IOError.FAILED("Cannot execute umount command: " + e.message);
			}
			
			// Check exit status: If non-zero, throw GLib.IOError.FAILED with stderr message
			if (exit_status != 0) {
				throw new GLib.IOError.FAILED("Unmount command failed: " + stderr);
			}
		}

		/**
		 * Copy files from overlay to live system based on Monitor change lists.
		 * 
		 * Stops monitoring, then processes Monitor change lists to copy files from overlay
		 * upper directory to project directories. Also copies file permissions (rwx only).
		 * 
		 * This should be called after command execution is complete.
		 * 
		 * Errors are logged via GLib.warning() but do not throw - operation continues for remaining files.
		 */
		public async void copy_files()
		{
			// Stop Monitor: yield this.monitor.stop() (async, ensures all inotify events are processed)
			yield this.monitor.stop();
			
			// Process Monitor change lists
			// For modified files (this.monitor.updated)
			foreach (var entry in this.monitor.updated.entries) {
				// Copy file from overlay to real path
				try {
					GLib.File.new_for_path(entry.key).copy(
						GLib.File.new_for_path(entry.value.path),
						GLib.FileCopyFlags.OVERWRITE,
						null,
						null
					);
				} catch (GLib.Error e) {
					GLib.warning("Cannot copy file from overlay to real path (%s -> %s): %s", entry.key, entry.value.path, e.message);
					continue;
				}
				
				// Copy file permissions (rwx only - user cannot change ownership)
				this.copy_permissions(entry.key, entry.value.path);
			}
			
			// For new files (this.monitor.added)
			// Sort entries by path (to ensure parent directories are created naturally)
			var added_entries = new Gee.ArrayList<string>.wrap(this.monitor.added.keys.to_array());
			added_entries.sort((a, b) => {
				return strcmp(a, b);
			});
			
			foreach (var key in added_entries) {
				// Copy file from overlay to real path
				try {
					GLib.File.new_for_path(key).copy(
						GLib.File.new_for_path(this.monitor.added.get(key).path),
						GLib.FileCopyFlags.OVERWRITE,
						null,
						null
					);
				} catch (GLib.Error e) {
					GLib.warning("Cannot copy file from overlay to real path (%s -> %s): %s", 
						key, this.monitor.added.get(key).path, e.message);
					continue;
				}
				
				// Copy file permissions (rwx only - user cannot change ownership)
				this.copy_permissions(key, this.monitor.added.get(key).path);
			}
			
			// For deleted files (this.monitor.removed)
			foreach (var entry in this.monitor.removed.entries) {
				// Delete file from real path
				try {
					GLib.File.new_for_path(entry.value.path).delete();
				} catch (GLib.Error e) {
					GLib.warning("Cannot delete file from real path (%s): %s", entry.value.path, e.message);
					continue;
				}
			}
		}

		/**
		 * Clean up overlay directory.
		 * 
		 * Unmounts the overlay filesystem and removes the overlay directory structure.
		 * This should be called after copy_files() is complete.
		 * 
		 * @throws GLib.IOError if unmount or directory removal fails
		 */
		public void cleanup() throws Error
		{
			// Call this.unmount() (may throw Error, but continue cleanup even if it fails)
			try {
				this.unmount();
			} catch (GLib.Error e) {
				GLib.warning("Unmount failed during cleanup: %s", e.message);
			}
			
			// Remove overlay directory structure
			try {
				GLib.File.new_for_path(this.overlay_dir).delete();
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Cannot remove overlay directory: " + e.message);
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
			
			if (overlay_rwx != real_rwx) {
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
}

