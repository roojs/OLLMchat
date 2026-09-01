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
	 * V2 client {@link ProjectManager} — RPC to ''ollmfilesd'', local UI state only.
	 *
	 * Filesystem, SQLite, and scan work stay on the daemon. This class keeps
	 * {@link active_project}, {@link active_file}, signals, and thin project rows.
	 */
	public class ProjectManager : Object
	{
		public OLLMrpc.Client rpc {
			get; private set;
		}

		/**
		 * Editor / tool buffers (client-only; {@link Window} sets ''OLLMcoder.BufferProvider'').
		 */
		public BufferProviderBase buffer_provider { get; set; default = new BufferProviderBase(); }
		
		public Gee.HashMap<string,FileBase> file_cache {
			get; set;
			default = new Gee.HashMap<string,FileBase>(); 
		}
		
		/**
		 * List of all projects (folders where is_project = true).
		 */
		public ProjectList projects { get; private set;
			default = new ProjectList(); }
		
		/**
		 * Currently active project (folder with is_project = true).
		 */
		public Folder? active_project { get; private set; default = null; }

		/**
		 * Pending-approval list (shared by Approvals + tools). Same instance for all projects.
		 */
		public ReviewFiles review_files { get; private set; }
		
		/**
		 * Currently active file.
		 */
		public File? active_file { get; private set; default = null; }
		
		/**
		 * Emitted when active file changes.
		 */
		public signal void active_file_changed(File? file);
		
		/**
		 * Emitted when active project changes.
		 * Note: Projects are Folders with is_project = true.
		 */
		public signal void active_project_changed(Folder? project);
		
		/**
		 * Emitted when file metadata changes (cursor, scroll, last_viewed, etc.).
		 * This signal is emitted for metadata-only updates that don't require background scanning.
		 */
		public signal void file_metadata_changed(File file);
		
		/**
		 * When true, {@link activate_project} tells the daemon to skip initial scan.
		 */
		public bool disable_initial_scan { get; set; default = false; }

		/**
		 * File deletion facade — {@link File.rpc_delete} RPC on the daemon.
		 */
		public DeleteManager delete_manager { get; private set; }

		/**
		 * Constructor.
		 */
		public ProjectManager()
		{
			Object();
			this.rpc = new OLLMrpc.Client(
				GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(),
					"ollmchat"
				),
				"ollmfilesd.pid",
				"ollmfilesd.sock"
			);
			this.delete_manager = new DeleteManager(this);
			this.review_files = new ReviewFiles(this);
		}
		
		/**
		 * Activate a file (deactivates previous active file).
		 * Client-local only: updates ''is_active'', emits
		 * {@link active_file_changed}. No daemon RPC.
		 *
		 * @param file The file to activate
		 */
		public void activate_file(File? file)
		{
			if (this.active_file != null && this.active_file != file) {
				this.active_file.is_active = false;
			}
			this.active_file = file;
			if (file != null) {
				file.is_active = true;
			}
			this.active_file_changed(file);
		}
		
		/**
		 * Activate a project in this client ProjectManager.
		 *
		 * Updates local ''is_active'' / {@link active_project} for UI.
		 * RPC ''ProjectManager.rpc_activate_project'' asks the daemon to
		 * load/scan/index that path — not to persist UI selection
		 * (Config2 ''Settings.Window'' owns that).
		 *
		 * @param project The project folder to activate (must have is_project = true)
		 */
		public void activate_project(Folder? project)
		{
			if (this.active_project == project && project != null && project.is_active) {
				GLib.debug ("opening project skipped already active path=%s", project.path);
				return;
			}

			foreach (var other_project in this.projects.project_map.values) {
				if (other_project != project && other_project.is_active) {
					other_project.is_active = false;
				}
			}
			if (this.active_project != null && this.active_project != project) {
				this.active_project.is_active = false;
			}

			this.active_project = project;
			if (project != null && project.is_project) {
				GLib.debug ("opening project path=%s", project.path);
				project.is_active = true;
			}
			this.disable_initial_scan = false;
			this.active_project_changed(project);

			if (project != null && project.is_project) {
				this.review_files.clear();
				this.review_files.refresh.begin();
			}

			this.rpc.call.begin(new OLLMrpc.Request() {
				method = "RPC-ProjectManager.rpc_activate_project",
				args = OLLMrpc.args(
					"sb",
					project != null ? project.path : "",
					this.disable_initial_scan
				)
			}, (obj, res) => {
				try {
					this.rpc.call.end(res);
				} catch (GLib.Error e) {
					GLib.critical ("activate project failed %s: %s",
						project != null ? project.path : "", e.message);
					this.rpc.notification (new OLLMrpc.Notification () {
						method = "Banner.show",
						message = "Could not activate project: " + e.message
					});
				}
			});
		}
		
		
		/**
		 * Notify that a file's metadata has changed (client-local only).
		 *
		 * @deprecated Kept for shipping ''SourceView'' callers during cutover.
		 *   Cursor, scroll, and last_viewed are per-window in-memory state on
		 *   {@link File} — not RPC, not daemon SQLite. Callers should set those
		 *   fields directly and drop this hook when session restore is redesigned.
		 *
		 * @param file The file whose metadata changed
		 */
		[Deprecated (since = "2.10.4")]
		public void on_file_metadata_change(File file)
		{
			this.file_metadata_changed(file);
		}
		
		/**
		 * Load projects from database.
		 * 
		 * Queries database for all folders where is_project = 1 and loads them
		 * into the manager.projects list.
		 *
		 * @throws GLib.Error if the RPC fails
		 */
		public async void rpc_load_projects_from_db() throws GLib.Error
		{
			var response = yield this.rpc.call(new OLLMrpc.Request() {
				method = "RPC-ProjectManager.rpc_load_projects_from_db"
			});
			if (response.retval.type() == GLib.Type.INVALID) {
				return;
			}
			foreach (var folder in (Gee.ArrayList<Folder>) response.retval.get_object()) {
				folder.manager = this;
				this.projects.append(folder);
			}
		}
		
		/**
		 * Fetch a {@link Folder} row at an absolute path (any project).
		 *
		 * Uses ''Folder.fetch'' on the daemon. For files inside a known
		 * project, prefer {@link Folder.fetch_file} on the project row.
		 *
		 * @param path Normalized absolute path
		 * @return The folder row, or null if not found
		 * @throws GLib.Error if the RPC fails
		 */
		public async Folder? fetch_folder(string path) throws GLib.Error
		{
			var response = yield this.rpc.call(new OLLMrpc.Request() {
				method = "RPC-Folder.fetch",
				args = OLLMrpc.args("s", path)
			});
			if (response.retval.type() == GLib.Type.INVALID) {
				return null;
			}
			var folder = (Folder) response.retval.get_object();
			folder.manager = this;
			this.file_cache.set(folder.path, folder);
			return folder;
		}

		/**
		 * Ensure a project exists at the given path.
		 * Caller must have verified the path is not already a project (path_map).
		 * If we have a Folder at this path (folder_map or DB), promote it; otherwise create new.
		 *
		 * @param path Normalized absolute path to the folder
		 * @return The Folder that is the project at that path (existing or new)
		 * @throws GLib.Error if the RPC fails
		 */
		public async Folder rpc_create_project(string path) throws GLib.Error
		{
			var response = yield this.rpc.call(new OLLMrpc.Request() {
				method = "RPC-ProjectManager.rpc_create_project",
				args = OLLMrpc.args("s", path)
			});
			if (response.retval.type() == GLib.Type.INVALID) {
				return new Folder(this) {
					is_project = true,
					path = path
				};
			}
			var project = (Folder) response.retval.get_object();
			project.manager = this;
			project.is_project = true;
			this.file_cache.set(project.path, project);
			this.projects.append(project);
			return project;
		}

		/**
		 * Remove a project from the projects list by clearing the is_project flag.
		 * Local state first; RPC is fire-and-forget ({@link OLLMrpc.Client.failed}).
		 *
		 * @param project The project folder to remove
		 */
		public void remove_project(Folder project)
		{
			if (this.active_project == project) {
				this.active_project = null;
				this.active_project_changed(null);
			}
			this.projects.remove(project);
			project.is_project = false;

			this.rpc.call.begin(new OLLMrpc.Request() {
				method = "RPC-ProjectManager.remove_project",
				args = OLLMrpc.args("s", project.path)
			}, (obj, res) => {
				try {
					this.rpc.call.end(res);
				} catch (GLib.Error e) {
					GLib.critical ("remove project failed %s: %s",
						project.path, e.message);
					this.rpc.notification (new OLLMrpc.Notification () {
						method = "Alert.show",
						message = "Could not remove project from daemon: "
							+ e.message
					});
				}
			});
		}
		
		/**
		 * Restore active project and file from Config2 Window paths.
		 *
		 * Does not read DB ''is_active'' flags. Empty ''project_path'' is a
		 * no-op. Empty ''file_path'' activates the project only.
		 *
		 * @param project_path Absolute project path from ''Settings.Window.project''
		 * @param file_path Absolute file path from ''Settings.Window.file'', or empty
		 */
		public async void restore_active_state(string project_path, string file_path = "")
		{
			if (project_path == "") {
				return;
			}
			if (!this.projects.path_map.has_key(project_path)) {
				GLib.warning("restore: project path not in list: %s", project_path);
				return;
			}
			var project = this.projects.path_map.get(project_path);
			GLib.debug("restoring window config project path=%s", project.path);
			this.activate_project(project);
			if (file_path == "") {
				return;
			}
			try {
				var file = yield project.fetch_file(file_path);
				if (file != null) {
					this.activate_file(file);
					return;
				}
			} catch (GLib.Error e) {
				GLib.critical("restore open file failed %s: %s", file_path, e.message);
				this.rpc.notification(new OLLMrpc.Notification() {
					method = "Alert.show",
					message = "Could not restore last file: " + e.message
				});
				return;
			}
			GLib.warning("restore open file not in project: %s", file_path);
			this.rpc.notification(new OLLMrpc.Notification() {
				method = "Alert.show",
				message = "Last file is not in the project: "
					+ GLib.Path.get_basename(file_path)
			});
		}
		
		/**
		 * Timestamp of last backup cleanup run (Unix timestamp).
		 * Used to ensure cleanup only runs once per day.
		 */
		
		/**
		 * Check if the active file has been modified on disk and differs from the buffer.
		 *
		 * @return FileUpdateStatus indicating what action should be taken
		 */
		public async FileUpdateStatus check_active_file_changed()
		{
			if (this.active_file == null) {
				return FileUpdateStatus.NO_CHANGE;
			}

			try {
				return yield this.active_file.check_changed();
			} catch (GLib.Error e) {
				GLib.critical ("check_active_file_changed: %s: %s",
					this.active_file.path, e.message);
				this.rpc.notification (new OLLMrpc.Notification () {
					method = "Banner.show",
					message = "Could not check file on disk: " + e.message
				});
				return FileUpdateStatus.NO_CHANGE;
			}
		}
		
		/**
		 * Writes current buffer contents via ''File.rpc_write''.
		 * Scan/index queue is on the daemon. RPC errors: {@link OLLMrpc.Client.failed}.
		 */
		public async void write_buffer_to_disk()
		{
			if (this.active_file == null || this.active_file.buffer == null) {
				return;
			}

			try {
				yield this.active_file.rpc_write();
			} catch (GLib.Error e) {
				GLib.critical ("write_buffer_to_disk: %s: %s",
					this.active_file.path, e.message);
				this.rpc.notification (new OLLMrpc.Notification () {
					method = "Alert.show",
					message = "Could not save file: " + e.message
				});
			}
		}
		
		/**
		 * Reloads active file via {@link File.read} (daemon filebase + RPC content).
		 */
		public async void reload_file_from_disk()
		{
			if (this.active_file == null || this.active_file.buffer == null) {
				return;
			}

			try {
				yield this.active_file.read();
			} catch (GLib.Error e) {
				GLib.critical ("reload_file_from_disk: %s: %s",
					this.active_file.path, e.message);
				this.rpc.notification (new OLLMrpc.Notification () {
					method = "Banner.show",
					message = "Could not reload file: " + e.message
				});
			}
		}
		
	}
}
