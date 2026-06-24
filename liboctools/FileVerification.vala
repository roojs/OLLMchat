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

		public override GLib.FileType indexed_file_type(string real_path)
		{
			if (!this.manager.file_cache.has_key(real_path)) {
				return GLib.FileType.UNKNOWN;
			}
			var item = this.manager.file_cache.get(real_path);
			if (item is OLLMfiles.Folder) {
				return GLib.FileType.DIRECTORY;
			}
			if (item.is_alias) {
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
			switch (file_type) {
				case GLib.FileType.DIRECTORY:
					try {
						GLib.File.new_for_path(real_path).make_directory(null);
					} catch (GLib.Error e) {
						GLib.warning(
							"Cannot create directory (%s): %s",
							real_path,
							e.message
						);
						return;
					}
					this.copy_permissions(overlay_path, real_path);
					return;
				case GLib.FileType.SYMBOLIC_LINK:
					try {
						var symlink_target = GLib.FileUtils.read_link(
							overlay_path
						);
						if (symlink_target == null) {
							GLib.warning(
								"Cannot read symlink target from overlay (%s)",
								overlay_path
							);
							return;
						}
						if (GLib.FileUtils.test(real_path, GLib.FileTest.EXISTS)) {
							GLib.FileUtils.unlink(real_path);
						}
						GLib.File.new_for_path(real_path).make_symbolic_link(
							symlink_target,
							null
						);
						this.copy_permissions(overlay_path, real_path);
					} catch (GLib.Error e) {
						GLib.warning(
							"Cannot create symlink from overlay to real path (%s -> %s): %s",
							overlay_path,
							real_path,
							e.message
						);
					}
					return;
				default:
					var content = "";
					try {
						var bytes = GLib.File.new_for_path(overlay_path).load_bytes(
							null
						);
						content = (string) bytes.get_data();
					} catch (GLib.Error e) {
						GLib.warning(
							"Cannot read overlay file (%s): %s",
							overlay_path,
							e.message
						);
						return;
					}
					var fake = new OLLMfiles.File.new_fake(this.manager, real_path);
					try {
						yield this.project.insert_file(fake, real_path);
					} catch (GLib.Error e) {
						GLib.warning(
							"Cannot register new file (%s): %s",
							real_path,
							e.message
						);
						return;
					}
					if (!(yield fake.write(content))) {
						GLib.warning(
							"Cannot write new file via RPC (%s)",
							real_path
						);
					}
					this.copy_permissions(overlay_path, real_path);
					return;
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
			switch (file_type) {
				case GLib.FileType.DIRECTORY:
					return;
				case GLib.FileType.SYMBOLIC_LINK:
					try {
						var symlink_target = GLib.FileUtils.read_link(
							overlay_path
						);
						if (symlink_target == null) {
							GLib.warning(
								"Cannot read symlink target from overlay (%s)",
								overlay_path
							);
							return;
						}
						if (GLib.FileUtils.test(real_path, GLib.FileTest.EXISTS)) {
							GLib.FileUtils.unlink(real_path);
						}
						GLib.File.new_for_path(real_path).make_symbolic_link(
							symlink_target,
							null
						);
						this.copy_permissions(overlay_path, real_path);
					} catch (GLib.Error e) {
						GLib.warning(
							"Cannot create symlink from overlay to real path (%s -> %s): %s",
							overlay_path,
							real_path,
							e.message
						);
					}
					return;
				default:
					var file = yield this.project.fetch_file(real_path);
					if (file == null) {
						return;
					}
					var content = "";
					try {
						var bytes = GLib.File.new_for_path(overlay_path).load_bytes(
							null
						);
						content = (string) bytes.get_data();
					} catch (GLib.Error e) {
						GLib.warning(
							"Cannot read overlay file (%s): %s",
							overlay_path,
							e.message
						);
						return;
					}
					if (!(yield file.write(content))) {
						GLib.warning(
							"Cannot write modified file via RPC (%s)",
							real_path
						);
					}
					this.copy_permissions(overlay_path, real_path);
					return;
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

		/**
		 * Copy file permissions (rwx only) from overlay file to real file.
		 *
		 * @param overlay_path Overlay file path
		 * @param real_path Real file path
		 */
		private void copy_permissions(string overlay_path, string real_path)
		{
			GLib.FileInfo overlay_info;
			try {
				overlay_info = GLib.File.new_for_path(overlay_path).query_info(
					GLib.FileAttribute.UNIX_MODE,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning(
					"Cannot query overlay file permissions (%s): %s",
					overlay_path,
					e.message
				);
				return;
			}

			GLib.FileInfo real_info;
			try {
				real_info = GLib.File.new_for_path(real_path).query_info(
					GLib.FileAttribute.UNIX_MODE,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning(
					"Cannot query real file permissions (%s): %s",
					real_path,
					e.message
				);
				return;
			}

			var overlay_mode = overlay_info.get_attribute_uint32(
				GLib.FileAttribute.UNIX_MODE
			);
			var real_mode = real_info.get_attribute_uint32(
				GLib.FileAttribute.UNIX_MODE
			);
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
				GLib.warning(
					"Cannot set real file permissions (%s): %s",
					real_path,
					e.message
				);
			}
		}
	}
}
