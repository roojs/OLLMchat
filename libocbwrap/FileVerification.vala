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
	 * Applies overlay scan results to the live filesystem and project index.
	 *
	 * {@link Scan} decides created vs modified vs removed during the overlay
	 * walk; implementations only apply each change. Paths only — no SQLite or
	 * project-manager types in this interface.
	 */
	public interface FileVerification : Object
	{
		/**
		 * Type recorded in the project index for @real_path.
		 *
		 * {@link Scan} uses this for created vs modified vs removed decisions.
		 * Default returns {@link GLib.FileType.UNKNOWN} (not indexed).
		 *
		 * @param real_path Live project path
		 * @return Indexed {@link GLib.FileType}, or {@link GLib.FileType.UNKNOWN}
		 */
		public virtual async GLib.FileType has_file(string real_path)
		{
			return GLib.FileType.UNKNOWN;
		}

		/**
		 * A new file, folder, or alias appeared in the overlay upper layer.
		 *
		 * @param file_type {@link GLib.FileType} from overlay {@link GLib.FileInfo}
		 * @param real_path Live project path
		 * @param overlay_path Path under the overlay upper directory
		 */
		public abstract async void created(
			GLib.FileType file_type,
			string real_path,
			string overlay_path);

		/**
		 * An existing indexed item changed in the overlay upper layer.
		 *
		 * @param file_type {@link GLib.FileType} from overlay {@link GLib.FileInfo}
		 * @param real_path Live project path
		 * @param overlay_path Path under the overlay upper directory
		 */
		public abstract async void modified(
			GLib.FileType file_type,
			string real_path,
			string overlay_path);

		/**
		 * A whiteout or delete marker removed an indexed item.
		 *
		 * @param file_type {@link GLib.FileType} from overlay {@link GLib.FileInfo}
		 * @param real_path Live project path
		 * @param overlay_path Path under the overlay upper directory when needed
		 */
		public abstract async void removed(
			GLib.FileType file_type,
			string real_path,
			string overlay_path);

		/**
		 * Scan walk complete — refresh review lists and release session state.
		 */
		public abstract async void finish();
	}
}
