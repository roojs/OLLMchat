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

namespace OLLMfiles
{
	/**
	 * Represents a symlink/alias to a file or folder.
	 *
	 * Many properties delegate to the target file ({@link language},
	 * {@link last_viewed}, {@link is_need_approval}, {@link is_unsaved}).
	 * The {@link points_to} property references the target file/folder, while
	 * {@link points_to_id} and {@link target_path} store the database ID and
	 * resolved path respectively.
	 *
	 * == Client vs daemon ==
	 *
	 * This file is the **client** {@link FileAlias} (UI process). Rows arrive
	 * via RPC deserialize ({@link rpc_register}); {@link points_to} and
	 * {@link target_path} are filled by the daemon index. Scan-time creation
	 * ({@code new_from_info}, home-directory checks, {@code realpath}) lives on
	 * {@code ollmfilesd/FileAlias.vala} — not compiled here.
	 *
	 * == Restrictions ==
	 *
	 * Security: On the daemon, aliases outside the user's home directory are
	 * rejected at scan/index time. The client displays whatever the daemon
	 * indexed.
	 *
	 * Editor restrictions: {@link read} and {@link write} are not supported.
	 * Aliases are not used in the editor (for display only).
	 *
	 * == Notes ==
	 *
	 * Aliases maintain their own {@link path} (where the symlink exists on
	 * disk) for filesystem tracking. {@code base_type} is {@code fa} for file
	 * aliases and {@code da} for folder aliases on the wire.
	 */
	public class FileAlias : File
	{
		/**
		 * Register this type for RPC wire decode.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("FileAlias", typeof(FileAlias));
		}

		/**
		 * Constructor.
		 *
		 * @param manager The ProjectManager instance (required)
		 *
		 * Note: {@link points_to} and {@link points_to_id} are set after
		 * construction (RPC hydrate or daemon row merge).
		 */
		public FileAlias(ProjectManager manager)
		{
			base(manager);
			this.base_type = "fa";
			// is_alias is computed (returns true for FileAlias)
			// points_to and points_to_id must be set after construction
		}

		/**
		 * Vector / agent summary line.
		 *
		 * When {@link points_to} is set, delegates to the target's
		 * {@link FileBase.to_summary}; otherwise one {@code (alias)} line.
		 *
		 * @param keymap Vector metadata map (passed through to target)
		 * @param indent Current indent prefix
		 * @return Summary text for this alias row
		 */
		public override string to_summary(
			Gee.HashMap<int, OLLMfiles.SQT.VectorMetadata> keymap,
			string indent
		)
		{
			if (this.points_to != null) {
				return this.points_to.to_summary(keymap, indent);
			}
			return indent + "- (alias) " + GLib.Path.get_basename(this.path);
		}

		/**
		 * Programming language - delegates to target file for tree display.
		 */
		public new string language {
			get {
				if (this.points_to is File) {
					return ((File) this.points_to).language;
				}
				return "";
			}
			set { /* Aliases are not edited */ }
		}

		/**
		 * Text buffer - delegates to target file for tree display.
		 *
		 * Note: Buffer is stored via provider using set_data/get_data, so this
		 * property is not directly accessible. Use
		 * {@code manager.buffer_provider.has_buffer()} to check if the target
		 * file has a buffer.
		 */

		/**
		 * Last viewed - delegates to target file for tree display.
		 */
		public new int64 last_viewed {
			get {
				if (this.points_to != null) {
					return this.points_to.last_viewed;
				}
				return 0;
			}
			set { /* Aliases are not edited */ }
		}

		/**
		 * Needs approval - delegates to target file for tree display.
		 */
		public new bool is_need_approval {
			get {
				if (this.points_to is File) {
					return ((File) this.points_to).is_need_approval;
				}
				return false;
			}
			set { /* Aliases are not edited */ }
		}

		/**
		 * Is unsaved - delegates to target file for tree display.
		 */
		public new bool is_unsaved {
			get {
				if (this.points_to is File) {
					return ((File) this.points_to).is_unsaved;
				}
				return false;
			}
			set { /* Aliases are not edited */ }
		}

		/**
		 * Read file contents — aliases are not edited.
		 *
		 * @return false always; logs a warning if called
		 */
		public new async bool read()
		{
			GLib.warning(
				"FileAlias.read() should not be called - alias files are not used in editor"
			);
			return false;
		}

		/**
		 * Write file contents — aliases are not edited.
		 *
		 * @return false always; logs a warning if called
		 */
		public new async bool write(
			string content = "",
			string base_type = "fa",
			string target = "",
			int unix_mode = -1
		)
		{
			GLib.warning(
				"FileAlias.write() should not be called - alias files are not used in editor"
			);
			return false;
		}
	}
}
