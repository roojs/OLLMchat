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

namespace OLLMfilesd
{
	/**
	 * Applies overlay scan results to the daemon filesystem and index.
	 *
	 * {@link OLLMbwrap.Scan} walks the overlay upper layer after
	 * {@link OLLMbwrap.Bubble.exec} and calls one method per change.
	 * Each change is realized through {@link Folder}, {@link FileAlias},
	 * and {@link File}, and removals retire through
	 * {@link DeleteManager} — the same work ''File.rpc_write'' and
	 * ''File.rpc_delete'' do for a remote client. In-app callers use
	 * {@link OLLMtools.FileVerification}, which sends those two calls over
	 * RPC; nothing here leaves the daemon.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var bubble = new OLLMbwrap.Bubble(
	 *     new OLLMfilesd.FileVerification(project, manager));
	 * bubble.project_path = project.path;
	 * var output = yield bubble.exec("make test", "");
	 * }}}
	 */
	public class FileVerification : GLib.Object, OLLMbwrap.FileVerification
	{
		private ProjectManager manager;
		private Folder? project;

		/**
		 * @param project Active project, or null when no project is open
		 * @param manager Project manager for the index and file_cache
		 */
		public FileVerification(Folder? project, ProjectManager manager)
		{
			this.project = project;
			this.manager = manager;
		}

		public override async GLib.FileType has_file(string real_path) throws GLib.Error
		{
			if (this.project == null) {
				return GLib.FileType.UNKNOWN;
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
			var unix_mode = 0U;
			try {
				var info = GLib.File.new_for_path(overlay_path).query_info(
					GLib.FileAttribute.UNIX_MODE, GLib.FileQueryInfoFlags.NONE, null);
				unix_mode = info.get_attribute_uint32(GLib.FileAttribute.UNIX_MODE) & 0777;
			} catch (GLib.Error e) {
				GLib.warning("Cannot query overlay mode (%s): %s", overlay_path, e.message);
			}
			switch (file_type) {
				case GLib.FileType.DIRECTORY:
					var folder = this.manager.get_folder_at_path(real_path);
					if (folder == null) {
						folder = new Folder(this.manager) {
							path = real_path,
							id = -1
						};
					}
					try {
						if (folder.id < 0) {
							yield folder.to_real();
						}
						yield folder.realize(unix_mode);
					} catch (GLib.Error e) {
						GLib.critical("overlay created folder %s: %s", real_path, e.message);
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Banner.show",
							message = "Could not save overlay file: " + real_path
						});
					}
					break;

				case GLib.FileType.SYMBOLIC_LINK:
					var alias = this.manager.file_cache.get(real_path) as FileAlias;
					if (alias == null) {
						alias = new FileAlias(this.manager) {
							path = real_path,
							id = -1
						};
					}
					try {
						var target = GLib.FileUtils.read_link(overlay_path);
						if (alias.id < 0) {
							yield alias.to_real(target);
						}
						yield alias.realize(target, unix_mode);
					} catch (GLib.Error e) {
						GLib.critical("overlay created symlink %s: %s", real_path, e.message);
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Banner.show",
							message = "Could not save overlay file: " + real_path
						});
					}
					break;

				default:
					var file = this.manager.get_file_from_active_project(real_path);
					if (file == null) {
						file = new File(this.manager) {
							path = real_path,
							id = -1
						};
					}
					var change_type = file.id < 0 ? "added" : "modified";
					try {
						if (file.id < 0) {
							yield file.to_real();
						}
						if (change_type == "modified" && this.manager.db != null) {
							file.is_need_approval = true;
							file.last_change_type = "modified";
							var file_history = new FileHistory(this.manager.db,
								file, "modified", new GLib.DateTime.now_local());
							yield file_history.commit();
							file.saveToDB(this.manager.db, null, false);
						}
						var bytes = GLib.File.new_for_path(overlay_path).load_bytes(null);
						yield file.realize((string) bytes.get_data(), unix_mode);
					} catch (GLib.Error e) {
						GLib.critical("overlay created file %s: %s", real_path, e.message);
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Banner.show",
							message = "Could not save overlay file: " + real_path
						});
						return;
					}
					if (change_type == "modified") {
						this.manager.notification(new OLLMrpc.Notification() {
							method = "event.project.invalidate_cache",
							object_type = "Project",
							message = this.manager.active_project.path
						});
					}
					break;
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
			var unix_mode = 0U;
			try {
				var info = GLib.File.new_for_path(overlay_path).query_info(
					GLib.FileAttribute.UNIX_MODE, GLib.FileQueryInfoFlags.NONE, null);
				unix_mode = info.get_attribute_uint32(GLib.FileAttribute.UNIX_MODE) & 0777;
			} catch (GLib.Error e) {
				GLib.warning("Cannot query overlay mode (%s): %s", overlay_path, e.message);
			}
			switch (file_type) {
				case GLib.FileType.DIRECTORY:
					var folder = this.manager.get_folder_at_path(real_path);
					if (folder == null) {
						folder = new Folder(this.manager) {
							path = real_path,
							id = -1
						};
					}
					try {
						if (folder.id < 0) {
							yield folder.to_real();
						}
						yield folder.realize(unix_mode);
					} catch (GLib.Error e) {
						GLib.critical("overlay modified folder %s: %s", real_path, e.message);
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Banner.show",
							message = "Could not update overlay file: " + real_path
						});
					}
					break;

				case GLib.FileType.SYMBOLIC_LINK:
					var alias = this.manager.file_cache.get(real_path) as FileAlias;
					if (alias == null) {
						alias = new FileAlias(this.manager) {
							path = real_path,
							id = -1
						};
					}
					try {
						var target = GLib.FileUtils.read_link(overlay_path);
						if (alias.id < 0) {
							yield alias.to_real(target);
						}
						yield alias.realize(target, unix_mode);
					} catch (GLib.Error e) {
						GLib.critical("overlay modified symlink %s: %s", real_path, e.message);
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Banner.show",
							message = "Could not update overlay file: " + real_path
						});
					}
					break;

				default:
					var file = this.manager.get_file_from_active_project(real_path);
					if (file == null) {
						file = new File(this.manager) {
							path = real_path,
							id = -1
						};
					}
					var change_type = file.id < 0 ? "added" : "modified";
					try {
						if (file.id < 0) {
							yield file.to_real();
						}
						if (change_type == "modified" && this.manager.db != null) {
							file.is_need_approval = true;
							file.last_change_type = "modified";
							var file_history = new FileHistory(this.manager.db,
								file, "modified", new GLib.DateTime.now_local());
							yield file_history.commit();
							file.saveToDB(this.manager.db, null, false);
						}
						var bytes = GLib.File.new_for_path(overlay_path).load_bytes(null);
						yield file.realize((string) bytes.get_data(), unix_mode);
					} catch (GLib.Error e) {
						GLib.critical("overlay modified file %s: %s", real_path, e.message);
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Banner.show",
							message = "Could not update overlay file: " + real_path
						});
						return;
					}
					if (change_type == "modified") {
						this.manager.notification(new OLLMrpc.Notification() {
							method = "event.project.invalidate_cache",
							object_type = "Project",
							message = this.manager.active_project.path
						});
					}
					break;
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
			FileBase? filebase = null;
			if (this.manager.file_cache.has_key(real_path)) {
				filebase = this.manager.file_cache.get(real_path);
			}
			if (filebase == null) {
				filebase = this.manager.get_file_from_active_project(real_path);
			}
			if (filebase == null) {
				filebase = this.manager.get_folder_at_path(real_path);
			}
			if (filebase == null) {
				return;
			}
			try {
				yield this.manager.delete_manager.remove(filebase,
					new GLib.DateTime.now_local());
			} catch (GLib.Error e) {
				GLib.critical("overlay removed failed %s: %s", real_path, e.message);
				this.manager.notification(new OLLMrpc.Notification() {
					method = "Banner.show",
					message = "Could not remove overlay path: " + real_path
				});
			}
		}

		public async void finish()
		{
			if (this.project == null) {
				return;
			}
			yield this.manager.delete_manager.cleanup();
			this.project.refresh_review();
		}
	}
}
