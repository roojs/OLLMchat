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
	 * Represents a directory/folder in the project.
	 * 
	 * Can also represent a project when is_project = true. Projects are folders with
	 * is_project = true (no separate Project class).
	 * 
	 * == Project Management ==
	 *
	 * On the daemon, {@code project_files} and {@link children} hold the full project
	 * graph ({@code ollmfilesd/Folder.vala}). The client keeps neither — file lists
	 * and path lookups are RPC at the caller ([`2.10.4.9`](../../docs/plans/2.10.4.9-v2-wiring-and-cutover.md)).
	 *
	 * == Git Integration ==
	 *
	 * During filesystem scan the daemon discovers repositories and checks ignored
	 * paths ({@code ollmfilesd/Folder.vala}). The UI process does not scan.
	 *
	 * == Client vs daemon ==
	 *
	 * This file is the **client** {@link Folder} (UI process). Scan, DB, and tree
	 * build live on the daemon. Methods such as {@code read_dir} and
	 * {@code load_files_from_db} are not compiled into the client build — see
	 * {@code ollmfilesd/Folder.vala}. At cutover this replaces
	 * {@code libocfiles/Folder.vala} in the app.
	 *
	 * No {@code project_files} or hydrated {@link children} on the client.
	 */
	public class Folder : FileBase
	{
		public static void rpc_register()
		{
			OLLMrpc.register("Folder", typeof(Folder));
		}

		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public Folder(ProjectManager manager)
		{
			base(manager);
			this.base_type = "d";
		}

		/**
		 * Unix timestamp of last view (stored in database, default: 0, used for projects).
		 */
		public int64 last_viewed { get; set; default = 0; }
		
		/**
		 * List of children (files and subfolders) - used for tree view hierarchy.
		 * Client stub only — not hydrated here; daemon holds the real tree.
		 */
		public FolderFiles children { get; set; default = new FolderFiles(); }
		
		public override string to_summary(
			Gee.HashMap<int, OLLMfiles.SQT.VectorMetadata> keymap, 
			string indent)
		{
			var description = "";
			if (keymap.has_key((int)this.id)) {
				var vm = keymap.get((int)this.id);
				description = vm.description != "" ? ": " + vm.description : "";
			}
			return indent + "- (folder) " + GLib.Path.get_basename(this.path) + description;
		}

		/**
		 * Project-level description from vector metadata ({@code ProjectAnalysis}).
		 *
		 * Shipping reads SQLite in-process. Client calls
		 * {@code vector.project.describe} on the daemon ([`2.10.4.1`](../../docs/plans/2.10.4.1-ollmfilesd-rpc-api.md));
		 * server relay not implemented yet — returns {@code ""} on error.
		 *
		 * Callers ({@code Skill/Runner}, {@code Task/Details}, {@code Task/Tool}) must
		 * {@code yield} this at cutover (was synchronous on shipping {@link Folder}).
		 *
		 * @return description text, or empty string
		 */
		public async string project_description()
		{
			if (!this.is_project || this.path.length == 0) {
				return "";
			}

			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "vector.project.describe",
				param = new OLLMfilesd.VectorParams() { path = this.path }
			});
			if (response.error != null) {
				return "";
			}
			return response.msg;
		}

		/**
		 * Fetch a {@link File} already tracked under this project.
		 *
		 * Checks {@link ProjectManager.file_cache} first, then {@code File.fetch}
		 * on the daemon. Does not scan disk or build a local project index.
		 *
		 * For a path just written to disk that is not in the index yet, use
		 * {@link insert_file} instead.
		 *
		 * @param path Absolute normalized file path
		 * @return The file, or null if not in this project
		 */
		public async File? fetch_file(string path)
		{
			if (this.manager.file_cache.has_key(path)) {
				var cached = this.manager.file_cache.get(path);
				if (cached is File) {
					return (File) cached;
				}
			}

			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "File.fetch",
				param = new OLLMfilesd.FileParams() {
					path = path,
					project_path = this.path
				}
			});
			if (response.error != null) {
				return null;
			}

			var file = (File) response.result;
			file.manager = this.manager;
			this.manager.file_cache.set(path, file);
			return file;
		}

		/**
		 * Whether a directory path is part of this project tree.
		 *
		 * Used before creating a new file under {@code dir_path}. RPC-backed;
		 * not a local {@code folder_map} lookup.
		 *
		 * @param dir_path Absolute normalized directory path
		 * @return true if the directory is tracked under this project
		 */
		public async bool contains_folder(string dir_path)
		{
			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "Folder.contains_folder",
				param = new OLLMfilesd.FolderParams() {
					project_path = this.path,
					path = dir_path
				}
			});
			if (response.error != null) {
				return false;
			}
			return response.msg == "true";
		}

		/**
		 * Fetch flat file rows for this project (file dropdown snapshot).
		 *
		 * Returns daemon rows; the caller builds its own {@code ListStore}. Not
		 * a live alias of daemon {@code ProjectFiles}.
		 *
		 * @return Files in this project for list UI
		 */
		public async Gee.ArrayList<File> fetch_file_list()
		{
			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "Folder.fetch_file_list",
				param = new OLLMfilesd.FolderParams() { path = this.path }
			});
			if (response.error != null) {
				return new Gee.ArrayList<File>();
			}
			var files = (Gee.ArrayList<File>) response.result;
			foreach (var file in files) {
				file.manager = this.manager;
				this.manager.file_cache.set(file.path, file);
			}
			return files;
		}

		/**
		 * Fetch files pending approval in this project.
		 *
		 * Snapshot for the approvals bar; daemon owns {@code is_need_approval}.
		 *
		 * @return Files needing approval
		 */
		public async Gee.ArrayList<File> fetch_pending_approvals()
		{
			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "Folder.fetch_pending_approvals",
				param = new OLLMfilesd.FolderParams() { path = this.path }
			});
			if (response.error != null) {
				return new Gee.ArrayList<File>();
			}
			var files = (Gee.ArrayList<File>) response.result;
			foreach (var file in files) {
				file.manager = this.manager;
				this.manager.file_cache.set(file.path, file);
			}
			return files;
		}

		/**
		 * Insert an on-disk file into this project's tracked index.
		 *
		 * The file must already exist on disk (e.g. after WriteFile). Calls
		 * {@link File.register} on the daemon; does not write bytes locally.
		 * Fake files ({@code id == -1}) receive a real id on success.
		 *
		 * @param file Client file object (often from {@link File.new_fake})
		 * @param path Absolute normalized path (must match {@link File.path})
		 */
		public async void insert_file(File file, string path) throws Error
		{
			if (!yield file.register()) {
				return;
			}
			if (file.buffer == null) {
				this.manager.buffer_provider.create_buffer(file);
			}
			this.manager.file_cache.set(path, file);
		}

	}
}
