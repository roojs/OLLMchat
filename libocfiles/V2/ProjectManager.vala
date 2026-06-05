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
	 * V2 client {@link ProjectManager} — RPC to {@code ollmfilesd}, local UI state only.
	 *
	 * Filesystem, SQLite, and scan work stay on the daemon. This class keeps
	 * {@link active_project}, {@link active_file}, signals, and thin project rows.
	 */
	public class ProjectManager : Object
	{
		public RpcClient rpc { get; private set; default = new RpcClient(); }

		/**
		 * Editor / tool buffers (client-only; {@link Window} sets {@code OLLMcoder.BufferProvider}).
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
		 * Activate a file (deactivates previous active file).
		 * Local state + signal first; RPC is fire-and-forget ({@link RpcClient.failed}).
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

			this.rpc.call.begin(new Rpc.Request() {
				method = "File.activate",
				param = new Rpc.CallParam() {
					path = file != null ? file.path : ""
				}
			}, (obj, res) => {
				this.rpc.call.end(res);
			});
		}
		
		/**
		 * Activate a project (deactivates previous active project).
		 * Local state + signal first; RPC is fire-and-forget ({@link RpcClient.failed}).
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

			this.rpc.call.begin(new Rpc.Request() {
				method = "ProjectManager.activate_project",
				param = new Rpc.CallParam() {
					skip_scan = this.disable_initial_scan,
					path = project != null ? project.path : ""
				}
			}, (obj, res) => {
				this.rpc.call.end(res);
			});
		}
		
		
		/**
		 * Notify that a file's metadata has changed (client-local only).
		 *
		 * @deprecated Kept for shipping {@code SourceView} callers during cutover.
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
		 */
		public async void load_projects_from_db()
		{
			var response = yield this.rpc.call(new Rpc.Request() {
				method = "ProjectManager.load_projects_from_db",
				param = new Rpc.CallParam()
			});
			if (response.error != null) {
				return;
			}
			foreach (var folder in (Gee.ArrayList<Folder>) response.result) {
				folder.manager = this;
				this.projects.append(folder);
			}
		}
		
		/**
		 * Find a Folder at the given path (e.g. subfolder of a project, or in DB).
		 * Daemon is authoritative; does not use local {@link projects} / folder_map.
		 *
		 * @param path Normalized absolute path
		 * @return The Folder if found, null otherwise
		 */
		public async Folder? get_folder_at_path(string path)
		{
			var response = yield this.rpc.call(new Rpc.Request() {
				method = "ProjectManager.get_folder_at_path",
				param = new Rpc.CallParam() { path = path }
			});
			if (response.error != null) {
				return null;
			}
			var folder = (Folder) response.result;
			folder.manager = this;
			return folder;
		}

		/**
		 * Ensure a project exists at the given path.
		 * Caller must have verified the path is not already a project (path_map).
		 * If we have a Folder at this path (folder_map or DB), promote it; otherwise create new.
		 *
		 * @param path Normalized absolute path to the folder
		 * @return The Folder that is the project at that path (existing or new)
		 */
		public async Folder create_project(string path)
		{
			var response = yield this.rpc.call(new Rpc.Request() {
				method = "ProjectManager.create_project",
				param = new Rpc.CallParam() { path = path }
			});
			if (response.error != null) {
				return new Folder(this) {
					is_project = true,
					path = path
				};
			}
			var project = (Folder) response.result;
			project.manager = this;
			project.is_project = true;
			this.file_cache.set(project.path, project);
			this.projects.append(project);
			return project;
		}

		/**
		 * Remove a project from the projects list by clearing the is_project flag.
		 * Local state first; RPC is fire-and-forget ({@link RpcClient.failed}).
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

			this.rpc.call.begin(new Rpc.Request() {
				method = "ProjectManager.remove_project",
				param = new Rpc.CallParam() { path = project.path }
			}, (obj, res) => {
				this.rpc.call.end(res);
			});
		}
		
		/**
		 * Check if a file path is in the active project.
		 * 
		 * @param file_path The normalized file path to check
		 * @return The File object if found in active project, null otherwise
		 */
		public File? get_file_from_active_project(string file_path)
		{
			if (this.active_project == null) {
				return null;
			}
			
			var project_file = this.active_project.project_files.child_map.get(file_path);
			return (project_file == null) ? null : project_file.file;
			
		}
		
		/**
		 * Converts a fake file (id = -1) to a real {@link File} via {@code File.register}.
		 *
		 * Daemon creates DB row + parent folders; client hydrates local tree + buffer.
		 *
		 * @param file The fake file to convert (must have id = -1)
		 * @param file_path The normalized file path
		 */
		public async void convert_fake_file_to_real(File file, string file_path) throws Error
		{
			if (this.active_project == null) {
				return;
			}

			var response = yield this.rpc.call(new Rpc.Request() {
				method = "File.register",
				param = new Rpc.CallParam() { path = file_path }
			});
			if (response.error != null) {
				return;
			}

			var real_file = (File) response.result;
			real_file.manager = this;
			this.file_cache.set(real_file.path, real_file);
			this.buffer_provider.create_buffer(real_file);
			this.active_project.project_files.update_from(this.active_project);
			this.active_project.project_files.new_file_added(real_file);
		}
		
		/**
		 * Restore active project and file from in-memory data structures.
		 */
		public void restore_active_state()
		{
			var project = this.projects.get_active_project();
			if (project == null) {
				foreach (var other_project in this.projects.project_map.values) {
					if (other_project.is_project && other_project.is_active) {
						other_project.is_active = false;
					}
				}
				return;
			}

			if (project.is_active) {
				project.is_active = false;
			}

			GLib.debug ("restoring session project path=%s", project.path);
			this.activate_project(project);

			var file = project.project_files.get_active_file();
			if (file != null) {
				this.activate_file(file);
			}
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

			var response = yield this.rpc.call(new Rpc.Request() {
				method = "File.changed.check",
				param = new Rpc.CallParam() {
					path = this.active_file.path,
					buffer_dirty = this.active_file.buffer != null
						&& this.active_file.buffer.is_modified,
					last_known_mtime = this.active_file.last_modified
				}
			});
			if (response.error != null) {
				return FileUpdateStatus.NO_CHANGE;
			}

			return (FileUpdateStatus) (int) response.result;
		}
		
		/**
		 * Writes current buffer contents via {@code File.write}.
		 * Scan/index queue is on the daemon. RPC errors: {@link RpcClient.failed}.
		 */
		public void write_buffer_to_disk()
		{
			if (this.active_file == null || this.active_file.buffer == null) {
				return;
			}

			var file = this.active_file;
			var content = file.buffer.get_text();
			this.rpc.call.begin(new Rpc.Request() {
				method = "File.write",
				param = new Rpc.CallParam() {
					path = file.path,
					content = content
				}
			}, (obj, res) => {
				this.rpc.call.end(res);
			});
		}
		
		/**
		 * Reloads active file from daemon via {@code File.read} into buffer.
		 * Must await RPC — buffer update needs {@code response.result} (not fire-and-forget).
		 */
		public async void reload_file_from_disk()
		{
			if (this.active_file == null || this.active_file.buffer == null) {
				return;
			}

			var file = this.active_file;
			var response = yield this.rpc.call(new Rpc.Request() {
				method = "File.read",
				param = new Rpc.CallParam() { path = file.path }
			});
			if (response.error != null) {
				return;
			}
			// TODO: overlay filebase + content from response.result (JsonOverlay / wire type TBD)
			// file.buffer.set_text(content);
		}
		
	}
}
