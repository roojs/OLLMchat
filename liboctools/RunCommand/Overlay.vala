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
		 * Scan instance for post-completion overlay scanning.
		 * Created in constructor, run() should be called after command completion.
		 */
		public Scan scan { get; private set; }



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
			
			// Create Scan instance (will be run in copy_files())
			this.scan = new Scan(
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
		 * Clean up overlay directory.
		 * 
		 * Recursively deletes the upper directory and removes the remaining overlay
		 * directory structure. This should be called after scan.run() is complete.
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
				this.scan.recursive_delete(GLib.Path.build_filename(this.overlay_dir, "upper"));
			} catch (GLib.Error e) {
				GLib.warning("Failed to delete upper directory: %s", e.message);
			}
			
			// Recursively delete work directory
			try {
				this.scan.recursive_delete(GLib.Path.build_filename(this.overlay_dir, "work"));
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



	}
}

