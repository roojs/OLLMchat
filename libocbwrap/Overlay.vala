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

namespace OLLMbwrap
{
	/**
	 * Overlay filesystem creation, directory layout, and cleanup for sandbox runs.
	 */
	public class Overlay : GLib.Object
	{
		/**
		 * Project root path; empty means no overlay (create/cleanup no-op).
		 *
		 * Set before {@link create} (typically copied from {@link Bubble.project_path}).
		 */
		public string project_path { get; set; default = ""; }

		/**
		 * Writable project root paths (keys) for overlay subdirectories.
		 *
		 * Caller fills from {@code Folder.build_roots()} or daemon policy.
		 */
		public Gee.HashMap<string, string> write_roots {
			get; set; default = new Gee.HashMap<string, string> ();
		}

		public FileVerification verification { get; construct; }

		/**
		 * Base directory for this overlay session under the user cache
		 * ({@code ollmchat/overlay-*} under {@link GLib.Environment.get_user_cache_dir}).
		 */
		public string overlay_dir { get; private set; default = ""; }

		/**
		 * Overlay subdirectory name to real project root path.
		 */
		public Gee.HashMap<string, string> overlay_map {
			get; private set; default = new Gee.HashMap<string, string> ();
		}

		/**
		 * Post-completion scanner; created in {@link create}, run after command exit.
		 */
		public Scan scan { get; private set; }

		public Overlay (FileVerification verification)
		{
			Object (verification: verification);

			var now = new GLib.DateTime.now_local();
			var timestamp = "%04d%02d%02d-%02d%02d%02d".printf(
				now.get_year(),
				now.get_month(),
				now.get_day_of_month(),
				now.get_hour(),
				now.get_minute(),
				now.get_second()
			);
			this.overlay_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_cache_dir(),
				"ollmchat",
				"overlay-" + timestamp
			);
		}

		/**
		 * Create overlay upper/work directory tree and populate {@link overlay_map}.
		 *
		 * @throws GLib.IOError if directory creation fails
		 */
		public void create() throws Error
		{
			if (this.project_path == "" || this.write_roots.size == 0) {
				return;
			}

			try {
				GLib.File.new_for_path(this.overlay_dir)
					.make_directory_with_parents(null);

				GLib.File.new_for_path(
					GLib.Path.build_filename(this.overlay_dir, "upper")
				).make_directory_with_parents(null);

				GLib.File.new_for_path(
					GLib.Path.build_filename(this.overlay_dir, "work")
				).make_directory_with_parents(null);

				var entries_array = this.write_roots.entries.to_array();
				for (var i = 0; i < entries_array.length; i++) {
					var root_path = entries_array[i].key;
					var subdirectory_name = "overlay" + (i + 1).to_string();
					var work_name = "work" + (i + 1).to_string();

					GLib.File.new_for_path(
						GLib.Path.build_filename(
							this.overlay_dir,
							"upper",
							subdirectory_name
						)
					).make_directory_with_parents(null);

					GLib.File.new_for_path(
						GLib.Path.build_filename(
							this.overlay_dir,
							"work",
							work_name
						)
					).make_directory_with_parents(null);

					this.overlay_map.set(subdirectory_name, root_path);
				}

				this.scan = new Scan (this.verification);
				this.scan.base_path = GLib.Path.build_filename(
					this.overlay_dir,
					"upper"
				);
				this.scan.overlay_map = this.overlay_map;
				this.scan.project_path = this.project_path;
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED(
					"Cannot create overlay directory structure: " + e.message
				);
			}
		}

		/**
		 * Remove overlay directory tree after {@link Scan.run} completes.
		 *
		 * Failures are logged; this method does not throw.
		 */
		public void cleanup()
		{
			if (this.project_path == "" || this.overlay_map.size == 0) {
				return;
			}
			if (this.scan == null) {
				return;
			}

			try {
				this.scan.recursive_delete(
					GLib.Path.build_filename(this.overlay_dir, "upper")
				);
			} catch (GLib.Error e) {
				GLib.warning(
					"Failed to delete upper directory: %s",
					e.message
				);
			}

			try {
				this.scan.recursive_delete(
					GLib.Path.build_filename(this.overlay_dir, "work")
				);
			} catch (GLib.Error e) {
				GLib.warning(
					"Failed to delete work directory: %s",
					e.message
				);
			}

			try {
				GLib.FileUtils.remove(this.overlay_dir);
			} catch (GLib.Error e) {
				GLib.warning(
					"Failed to remove overlay directory: %s",
					e.message
				);
			}
		}
	}
}
