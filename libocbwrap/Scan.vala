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
	 * Post-completion overlay scanner: walk the upper layer and delegate apply
	 * to {@link FileVerification}.
	 *
	 * Detects additions, modifications, and deletions (whiteouts). The walk loop
	 * and created/modified/removed decisions stay here; implementations apply
	 * each change.
	 */
	public class Scan : Object
	{
		/**
		 * Overlay upper directory base path.
		 *
		 * Set before {@link run} (from {@link Overlay.create}).
		 */
		public string base_path { get; set; default = ""; }

		/**
		 * Overlay subdirectory name to real project root path.
		 */
		public Gee.HashMap<string, string> overlay_map {
			get; set; default = new Gee.HashMap<string, string> ();
		}

		/**
		 * Project root; empty skips {@link run}.
		 */
		public string project_path { get; set; default = ""; }

		public FileVerification verification { get; construct; }

		/**
		 * @param verification Apply hook for overlay changes
		 */
		public Scan (FileVerification verification)
		{
			Object (verification: verification);
		}

		/**
		 * Walk overlay upper directories and apply changes via {@link FileVerification}.
		 */
		public async void run()
		{
			if (this.project_path == "") {
				return;
			}

			foreach (var entry in this.overlay_map.entries) {
				yield this.scan_dir(
					GLib.Path.build_filename(this.base_path, entry.key),
					entry.value
				);
			}

			yield this.verification.finish();
		}

		private async void scan_dir(string overlay_path, string real_path)
		{
			var overlay_dir = GLib.File.new_for_path(overlay_path);
			if (!GLib.FileUtils.test(overlay_dir.get_path(), GLib.FileTest.EXISTS)) {
				return;
			}

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
				GLib.warning(
					"Cannot enumerate overlay directory %s: %s",
					overlay_path,
					e.message
				);
				return;
			}

			var folders_list = new Gee.ArrayList<string>();
			GLib.FileInfo? file_info;
			while ((file_info = enumerator.next_file(null)) != null) {
				var item_overlay_path = GLib.Path.build_filename(
					overlay_path,
					file_info.get_name()
				);
				var actual_real_path = this.to_real_path(item_overlay_path);
				var indexed = yield this.verification.has_file(
					actual_real_path
				);

				if (file_info.get_file_type() == GLib.FileType.DIRECTORY) {
					folders_list.add(item_overlay_path);
					yield this.handle_folder(
						item_overlay_path,
						actual_real_path,
						indexed
					);
					continue;
				}

				if (file_info.get_is_symlink()) {
					yield this.handle_filealias(
						item_overlay_path,
						actual_real_path,
						indexed
					);
					continue;
				}

				yield this.handle_file(
					item_overlay_path,
					actual_real_path,
					indexed
				);
			}

			foreach (var folder_overlay_path in folders_list) {
				yield this.scan_dir(
					folder_overlay_path,
					this.to_real_path(folder_overlay_path)
				);
			}
		}

		private async void handle_file(
			string overlay_path,
			string real_path,
			GLib.FileType indexed)
		{
			if (this.is_whiteout(overlay_path)) {
				if (indexed != GLib.FileType.UNKNOWN) {
					yield this.verification.removed(
						indexed,
						real_path,
						overlay_path
					);
					return;
				}
				GLib.warning(
					"Whiteout detected but path not indexed: overlay=%s real=%s",
					overlay_path,
					real_path
				);
				return;
			}

			if (
				indexed != GLib.FileType.UNKNOWN
				&& indexed != GLib.FileType.REGULAR
			) {
				yield this.verification.removed(
					indexed,
					real_path,
					overlay_path
				);
				indexed = GLib.FileType.UNKNOWN;
			}

			if (indexed == GLib.FileType.UNKNOWN) {
				yield this.verification.created(
					GLib.FileType.REGULAR,
					real_path,
					overlay_path
				);
				return;
			}

			yield this.verification.modified(
				GLib.FileType.REGULAR,
				real_path,
				overlay_path
			);
		}

		private async void handle_folder(
			string overlay_path,
			string real_path,
			GLib.FileType indexed)
		{
			if (
				indexed != GLib.FileType.UNKNOWN
				&& indexed != GLib.FileType.DIRECTORY
			) {
				yield this.verification.removed(
					indexed,
					real_path,
					overlay_path
				);
				indexed = GLib.FileType.UNKNOWN;
			}

			if (indexed == GLib.FileType.DIRECTORY) {
				return;
			}

			yield this.verification.created(
				GLib.FileType.DIRECTORY,
				real_path,
				overlay_path
			);
		}

		private async void handle_filealias(
			string overlay_path,
			string real_path,
			GLib.FileType indexed)
		{
			if (
				indexed != GLib.FileType.UNKNOWN
				&& indexed != GLib.FileType.SYMBOLIC_LINK
			) {
				yield this.verification.removed(
					indexed,
					real_path,
					overlay_path
				);
				indexed = GLib.FileType.UNKNOWN;
			}

			if (indexed == GLib.FileType.UNKNOWN) {
				yield this.verification.created(
					GLib.FileType.SYMBOLIC_LINK,
					real_path,
					overlay_path
				);
				return;
			}

			yield this.verification.modified(
				GLib.FileType.SYMBOLIC_LINK,
				real_path,
				overlay_path
			);
		}

		private bool is_whiteout(string overlay_path)
		{
			try {
				var file = GLib.File.new_for_path(overlay_path);
				if (!GLib.FileUtils.test(file.get_path(), GLib.FileTest.EXISTS)) {
					return false;
				}

				var info = file.query_info(
					GLib.FileAttribute.UNIX_RDEV + ","
						+ GLib.FileAttribute.STANDARD_TYPE,
					GLib.FileQueryInfoFlags.NONE,
					null
				);

				if (info.get_file_type() != GLib.FileType.SPECIAL) {
					return false;
				}

				return info.get_attribute_uint32(
					GLib.FileAttribute.UNIX_RDEV
				) == 0;
			} catch (GLib.Error e) {
				return false;
			}
		}

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
					this.overlay_map.get(components[0]),
					components[1]
				);
			}
			return this.overlay_map.get(components[0]);
		}

		/**
		 * Recursively delete a directory and all its contents.
		 *
		 * @param dir_path Path to directory to delete
		 * @throws Error if deletion fails
		 */
		public void recursive_delete(string dir_path) throws Error
		{
			var dir = GLib.File.new_for_path(dir_path);

			try {
				dir.set_attribute_uint32(
					GLib.FileAttribute.UNIX_MODE,
					0755,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.debug(
					"Cannot change permissions on %s: %s",
					dir_path,
					e.message
				);
			}

			var enumerator = dir.enumerate_children(
				GLib.FileAttribute.STANDARD_NAME + ","
					+ GLib.FileAttribute.STANDARD_TYPE,
				GLib.FileQueryInfoFlags.NONE,
				null
			);

			GLib.FileInfo? file_info;
			while ((file_info = enumerator.next_file(null)) != null) {
				var child = GLib.Path.build_filename(
					dir_path,
					file_info.get_name()
				);
				if (file_info.get_file_type() == GLib.FileType.DIRECTORY) {
					this.recursive_delete(child);
					continue;
				}
				GLib.FileUtils.unlink(child);
			}

			dir.delete(null);
		}
	}
}
