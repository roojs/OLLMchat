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
	 * V2 client flat file list for one project ({@link GLib.ListModel}).
	 *
	 * Populated by {@link refresh} from {@link Folder.fetch_files} RPC.
	 * Not a live mirror of daemon ''ProjectFiles'' — call {@link refresh}
	 * after index changes (open project, write file, approvals, notifications).
	 *
	 * **🚫** no ''folder_map'', ''all_files'', or ''update_from'' —
	 * path lookup uses {@link get_by_path} / {@link ProjectManager.fetch_file}.
	 */
	public class ProjectFiles : Object, GLib.ListModel, Gee.Traversable<ProjectFile>, Gee.Iterable<ProjectFile>
	{
		/**
		 * Project row this list belongs to.
		 */
		public Folder project { get; construct; }

		/**
		 * Backing store: {@link ProjectFile} wrappers for dropdown / search UI.
		 */
		private Gee.ArrayList<ProjectFile> items { get; set;
			default = new Gee.ArrayList<ProjectFile>((a, b) => {
				return a.file.id == b.file.id;
			});
		}

		/**
		 * Total rows matching the current {@link refresh} query (from daemon).
		 */
		public int total { get; private set; default = 0; }

		/**
		 * Next {@link Folder.fetch_files} offset (rows already loaded).
		 */
		public int offset { get; private set; default = 0; }

		/**
		 * Active dropdown filter passed to the last {@link refresh}.
		 */
		public string query { get; private set; default = ""; }

		/**
		 * True while a {@link Folder.fetch_files} RPC is in flight.
		 */
		public bool loading { get; private set; default = false; }

		/**
		 * Emitted when a new file is added to this list after {@link refresh}
		 * or {@link append} (not used for daemon scan discovery).
		 *
		 * @param file The newly listed {@link File}
		 */
		public signal void new_file_added(File file);

		/**
		 * Constructor.
		 *
		 * @param project Project folder (''is_project == true'')
		 */
		public ProjectFiles(Folder project)
		{
			Object(project: project);
		}

		/**
		 * Reload file rows from the daemon (''Folder.fetch_files''), first page.
		 *
		 * @param query Dropdown filter (empty = browse all)
		 */
		public async void refresh(string query = "")
		{
			this.query = query;
			this.offset = 0;
			this.total = 0;

			var old_n_items = this.items.size;
			this.items.clear();

			var response = yield this.project.fetch_files(0, 50, query);
			if (response.error != null) {
				GLib.debug(
					"refresh failed query=%s error=%s items=%u items_changed=no",
					query,
					response.error.message,
					this.items.size
				);
				return;
			}
			this.total = int.parse(response.msg);
			var files = (Gee.ArrayList<File>) response.result;
			foreach (var file in files) {
				this.items.add(new ProjectFile(
					this.project.manager,
					file,
					this.project
				));
			}
			this.offset = this.items.size;

			var new_n_items = this.items.size;
			if (old_n_items > 0 || new_n_items > 0) {
				GLib.debug(
					"items_changed pos=0 removed=%u added=%u query=%s",
					old_n_items,
					new_n_items,
					query
				);
				this.items_changed(0, old_n_items, new_n_items);
			} else {
				GLib.debug(
					"items_changed skipped removed=0 added=0 query=%s",
					query
				);
			}
			GLib.debug(
				"refresh done query=%s total=%d loaded=%u",
				query,
				this.total,
				new_n_items
			);
		}

		/**
		 * Append the next ''Folder.fetch_files'' page when more rows exist.
		 */
		public async void load_more()
		{
			if (this.loading) {
				return;
			}
			if (this.offset >= this.total) {
				return;
			}

			this.loading = true;
			var response = yield this.project.fetch_files(
				this.offset,
				50,
				this.query
			);
			this.loading = false;

			if (response.error != null) {
				return;
			}
			this.total = int.parse(response.msg);
			var files = (Gee.ArrayList<File>) response.result;
			if (files.size == 0) {
				return;
			}

			var start = this.items.size;
			foreach (var file in files) {
				this.items.add(new ProjectFile(
					this.project.manager,
					file,
					this.project
				));
			}
			this.offset = this.items.size;
			this.items_changed(start, 0, files.size);
		}

		/**
		 * Lookup {@link File} by database id in the current snapshot.
		 *
		 * @param file_id Daemon file id
		 * @return Matching file, or null if not in this list
		 */
		public File? get_by_id(int64 file_id)
		{
			if (file_id <= 0 || this.items.size == 0) {
				return null;
			}

			var index = this.items.index_of(
				new ProjectFile(
					this.items[0].file.manager,
					new File(this.items[0].file.manager) {
						id = file_id
					},
					this.items[0].project
				)
			);
			if (index < 0) {
				return null;
			}
			return this.items[index].file;
		}

		/**
		 * Lookup {@link File} by absolute path in the current snapshot.
		 *
		 * @param path Normalized absolute file path
		 * @return Matching file, or null if not in this list
		 */
		public File? get_by_path(string path)
		{
			foreach (var project_file in this.items) {
				if (project_file.file.path == path) {
					return project_file.file;
				}
			}
			return null;
		}

		/**
		 * Gee.Traversable interface implementation: Execute function for each item.
		 *
		 * @param f Function to execute for each {@link ProjectFile}
		 * @return true if all items were processed, false if iteration stopped early
		 */
		public bool foreach(Gee.ForallFunc<ProjectFile> f)
		{
			return this.items.foreach(f);
		}

		/**
		 * Gee.Iterable interface implementation: Get iterator over items.
		 *
		 * @return Iterator over {@link ProjectFile} items
		 */
		public Gee.Iterator<ProjectFile> iterator()
		{
			return this.items.iterator();
		}

		/**
		 * ListModel interface implementation: Get the item type.
		 */
		public Type get_item_type()
		{
			return typeof(ProjectFile);
		}

		/**
		 * ListModel interface implementation: Get the number of items.
		 */
		public uint get_n_items()
		{
			return this.items.size;
		}

		/**
		 * ListModel interface implementation: Get item at position.
		 *
		 * @param position Index into the list
		 * @return The {@link ProjectFile} at @position, or null if out of range
		 */
		public Object? get_item(uint position)
		{
			if (position >= this.items.size) {
				return null;
			}
			return this.items[(int)position];
		}

		/**
		 * Append a row (local UI update; prefer {@link refresh} after daemon index changes).
		 *
		 * @param item {@link ProjectFile} to append
		 */
		public void append(ProjectFile item)
		{
			var position = this.items.size;
			this.items.add(item);
			this.items_changed(position, 0, 1);
			this.new_file_added(item.file);
		}

		/**
		 * Find an item in the list and return its position.
		 *
		 * @param item The {@link ProjectFile} item to find
		 * @param position Output parameter for the position if found
		 * @return true if @item was found, false otherwise
		 */
		public bool find(ProjectFile item, out uint position)
		{
			var index = this.items.index_of(item);
			if (index < 0) {
				position = 0;
				return false;
			}
			position = (uint)index;
			return true;
		}

		/**
		 * Insert an item at a specific position.
		 *
		 * @param position The position to insert at
		 * @param item The {@link ProjectFile} item to insert
		 */
		public void insert(uint position, ProjectFile item)
		{
			if (position > this.items.size) {
				position = this.items.size;
			}

			this.items.insert((int)position, item);
			this.items_changed(position, 0, 1);
		}

		/**
		 * Check if an item exists in the list.
		 *
		 * @param item The {@link ProjectFile} item to check
		 * @return true if @item exists, false otherwise
		 */
		public bool contains(ProjectFile item)
		{
			return this.items.contains(item);
		}

		/**
		 * Remove an item from the list by item reference.
		 *
		 * @param item The {@link ProjectFile} item to remove
		 */
		public void remove(ProjectFile item)
		{
			var position = this.items.index_of(item);
			if (position < 0) {
				return;
			}

			this.remove_at((uint)position);
		}

		/**
		 * Remove an item at a specific position (ListStore-compatible).
		 *
		 * @param position The position of the item to remove
		 */
		public void remove_at(uint position)
		{
			if (position >= this.items.size) {
				return;
			}

			this.items.remove_at((int)position);
			this.items_changed(position, 1, 0);
		}

		/**
		 * Remove all items from the list (ListStore-compatible).
		 */
		public void remove_all()
		{
			var old_n_items = this.items.size;
			this.items.clear();

			if (old_n_items > 0) {
				this.items_changed(0, old_n_items, 0);
			}
		}

		/**
		 * Active file in this list snapshot.
		 *
		 * @deprecated Use {@link ProjectManager.active_file} at cutover.
		 *
		 * @return First file with ''is_active'', or null
		 */
		[Deprecated (since = "2.10.4")]
		public File? get_active_file()
		{
			for (uint i = 0; i < this.get_n_items(); i++) {
				var item = this.get_item(i) as ProjectFile;
				if (item != null && item.file.is_active) {
					return item.file;
				}
			}
			return null;
		}

		/**
		 * Recently modified open files, most recent first.
		 *
		 * @param days Look-back window in days
		 * @return Open files modified within the look-back window
		 */
		public Gee.ArrayList<File> get_recent_list(int days)
		{
			var cutoff_time = new GLib.DateTime.now_local().add_days(-days);
			var filtered_files = new Gee.ArrayList<File>();

			foreach (var project_file in this.items) {
				if (!project_file.file.is_open || project_file.file.last_modified < 1) {
					continue;
				}
				if ((new GLib.DateTime.from_unix_local(project_file.file.last_modified)).compare(cutoff_time) < 1) {
					continue;
				}
				filtered_files.add(project_file.file);
			}

			filtered_files.sort((a, b) => {
				if (a.last_modified == b.last_modified) {
					return 0;
				}
				return a.last_modified < b.last_modified ? 1 : -1;
			});

			return filtered_files;
		}

		/**
		 * File ids as strings, optionally filtered by language.
		 *
		 * @param language Language filter (empty = all)
		 * @return File ids from the current snapshot
		 */
		public Gee.ArrayList<string> get_ids(string language = "")
		{
			var file_ids = new Gee.ArrayList<string>();

			foreach (var project_file in this.items) {
				if (language != "" && project_file.file.language != language) {
					continue;
				}

				file_ids.add(project_file.file.id.to_string());
			}

			return file_ids;
		}
	}
}
