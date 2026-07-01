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

namespace OLLMtools
{
	/**
	 * Applies overlay scan results via {@link OLLMfiles} V2 RPC after
	 * {@link OLLMbwrap.Bubble} execution.
	 *
	 * Shared by any in-app caller that runs under bubblewrap and needs
	 * overlay writes merged to disk and the project index (e.g.
	 * {@link RunCommand.Request}, MCP stdio).
	 */
	public class FileVerification : GLib.Object, OLLMbwrap.FileVerification
	{
		private OLLMfiles.ProjectManager manager;
		private OLLMfiles.Folder? project;

		/**
		 * @param project Active project, or null when no project is open
		 * @param manager Project manager for RPC and {@link ProjectManager.file_cache}
		 */
		public FileVerification(
			OLLMfiles.Folder? project,
			OLLMfiles.ProjectManager manager)
		{
			this.project = project;
			this.manager = manager;
		}

		public override async GLib.FileType has_file(string real_path)
		{
			if (this.project == null) {
				return GLib.FileType.UNKNOWN;
			}
			if (!this.manager.file_cache.has_key(real_path)) {
				yield this.project.fetch_file(real_path);
			}
			if (!this.manager.file_cache.has_key(real_path)) {
				return GLib.FileType.UNKNOWN;
			}
			var item = this.manager.file_cache.get(real_path);
			if (item.base_type == "d") {
				return GLib.FileType.DIRECTORY;
			}
			if (item.base_type == "fa") {
				return GLib.FileType.SYMBOLIC_LINK;
			}
			return GLib.FileType.REGULAR;
		}

		public async void created(
			GLib.FileType file_type,
			string real_path,
			string overlay_path)
		{
			if (this.project == null) {
				return;
			}
			var base_type = "f";
			var content = "";
			var target = "";
			switch (file_type) {
				case GLib.FileType.DIRECTORY:
					base_type = "d";
					break;
				case GLib.FileType.SYMBOLIC_LINK:
					base_type = "fa";
					try {
						var link = GLib.FileUtils.read_link(overlay_path);
						if (link == null) {
							GLib.warning(
								"Cannot read symlink target (%s)",
								overlay_path
							);
							return;
						}
						target = link;
					} catch (GLib.Error e) {
						GLib.warning(
							"Cannot read symlink target (%s): %s",
							overlay_path,
							e.message
						);
						return;
					}
					break;
				case GLib.FileType.REGULAR:
					try {
						var bytes = GLib.File.new_for_path(
							overlay_path
						).load_bytes(null);
						content = (string) bytes.get_data();
					} catch (GLib.Error e) {
						GLib.warning(
							"Cannot read overlay file (%s): %s",
							overlay_path,
							e.message
						);
						return;
					}
					break;
				default:
					break;
			}
			var unix_mode = 0U;
			try {
				var info = GLib.File.new_for_path(overlay_path).query_info(
					GLib.FileAttribute.UNIX_MODE,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
				unix_mode = info.get_attribute_uint32(
					GLib.FileAttribute.UNIX_MODE
				) & 0777;
			} catch (GLib.Error e) {
				GLib.warning(
					"Cannot query overlay mode (%s): %s",
					overlay_path,
					e.message
				);
			}
			if (!(yield new OLLMfiles.File.new_fake(
				this.manager,
				real_path
			).write(
				content,
				base_type,
				target,
				unix_mode
			))) {
				GLib.warning(
					"Cannot apply overlay write via RPC (%s)",
					real_path
				);
			}
		}

		public async void modified(
			GLib.FileType file_type,
			string real_path,
			string overlay_path)
		{
			if (this.project == null) {
				return;
			}
			var base_type = "f";
			var content = "";
			var target = "";
			switch (file_type) {
				case GLib.FileType.DIRECTORY:
					base_type = "d";
					break;
				case GLib.FileType.SYMBOLIC_LINK:
					base_type = "fa";
					try {
						var link = GLib.FileUtils.read_link(overlay_path);
						if (link == null) {
							GLib.warning(
								"Cannot read symlink target (%s)",
								overlay_path
							);
							return;
						}
						target = link;
					} catch (GLib.Error e) {
						GLib.warning(
							"Cannot read symlink target (%s): %s",
							overlay_path,
							e.message
						);
						return;
					}
					break;
				case GLib.FileType.REGULAR:
					try {
						var bytes = GLib.File.new_for_path(
							overlay_path
						).load_bytes(null);
						content = (string) bytes.get_data();
					} catch (GLib.Error e) {
						GLib.warning(
							"Cannot read overlay file (%s): %s",
							overlay_path,
							e.message
						);
						return;
					}
					break;
				default:
					break;
			}
			var unix_mode = 0U;
			try {
				var info = GLib.File.new_for_path(overlay_path).query_info(
					GLib.FileAttribute.UNIX_MODE,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
				unix_mode = info.get_attribute_uint32(
					GLib.FileAttribute.UNIX_MODE
				) & 0777;
			} catch (GLib.Error e) {
				GLib.warning(
					"Cannot query overlay mode (%s): %s",
					overlay_path,
					e.message
				);
			}
			if (!(yield new OLLMfiles.File.new_fake(
				this.manager,
				real_path
			).write(
				content,
				base_type,
				target,
				unix_mode
			))) {
				GLib.warning(
					"Cannot apply overlay write via RPC (%s)",
					real_path
				);
			}
		}

		public async void removed(
			GLib.FileType file_type,
			string real_path,
			string overlay_path)
		{
			if (this.project == null) {
				return;
			}
			OLLMfiles.FileBase? filebase = null;
			if (this.manager.file_cache.has_key(real_path)) {
				filebase = this.manager.file_cache.get(real_path);
			}
			if (filebase == null) {
				var file = yield this.project.fetch_file(real_path);
				if (file != null) {
					filebase = file;
				}
			}
			if (filebase == null) {
				return;
			}
			try {
				yield this.manager.delete_manager.remove(
					filebase,
					GLib.DateTime.now()
				);
			} catch (GLib.Error e) {
				GLib.warning(
					"Cannot delete %s: %s",
					real_path,
					e.message
				);
			}
		}

		public async void finish()
		{
			if (this.project == null) {
				return;
			}
			yield this.manager.delete_manager.cleanup();
			yield new OLLMfiles.ReviewFiles(this.project).refresh();
		}
	}
}
