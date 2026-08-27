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
	 * Manages files in a project that need approval (flat list for approvals UI).
	 *
	 * V2 client: implements {@link GLib.ListModel} over {@link FileWithHistory}
	 * rows from ''Folder.fetch_pending_approvals''. Call {@link refresh} to
	 * reload the list model, or {@link fetch_pending} for the snapshot only.
	 */
	public class ReviewFiles : Object, GLib.ListModel
	{
		/**
		 * Emitted after {@link refresh} finishes (success or empty RPC result).
		 */
		public signal void refreshed();

		public weak ProjectManager manager { get; construct; }

		/**
		 * Backing store: {@link FileWithHistory} rows pending approval.
		 * Uses database id for equality checks.
		 */
		private Gee.ArrayList<FileWithHistory> items { get; set;
			default = new Gee.ArrayList<FileWithHistory>((a, b) => {
				return a.id == b.id;
			});
		}

		/**
		 * Hashmap of file path => {@link FileWithHistory} row for quick lookup.
		 */
		public Gee.HashMap<string, FileWithHistory> file_map { get; private set;
			default = new Gee.HashMap<string, FileWithHistory>(); }

		private bool refresh_running;
		private bool refresh_queued;

		/** Last `MAX(file_history.id)` from daemon (`Response.msg`); `0` = clear + replay from start. */
		private int64 since_marker;

		/**
		 * Constructor.
		 *
		 * @param manager Owning {@link ProjectManager}
		 */
		public ReviewFiles(ProjectManager manager)
		{
			Object(manager: manager);
		}

		/**
		 * Fetch pending-approval delta from the daemon (''Folder.fetch_pending_approvals'' wire).
		 *
		 * Does not update this {@link GLib.ListModel} — use {@link refresh} for that.
		 * Advances {@link since_marker} from ''Response.msg'' on success.
		 *
		 * @return History rows since the current marker (`status` 0 = upsert, else remove)
		 * @throws GLib.Error if the RPC fails
		 */
		public async Gee.ArrayList<FileWithHistory> fetch_pending() throws GLib.Error
		{
			var project = this.manager.active_project;
			if (project == null) {
				return new Gee.ArrayList<FileWithHistory>();
			}
			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "RPC-Folder.fetch_pending_approvals",
				args = OLLMrpc.args("sx", project.path, this.since_marker)
			});
			if (response.msg != "" && response.msg != "project not found") {
				this.since_marker = int64.parse(response.msg);
			}
			return (Gee.ArrayList<FileWithHistory>) response.result;
		}

		/**
		 * Reload pending-approval rows from the daemon into this list model.
		 *
		 * Queued overlapping callers set {@link refresh_queued}; each loop iteration
		 * fetches with the current marker and applies that batch before the next.
		 */
		public async void refresh()
		{
			if (this.refresh_running) {
				this.refresh_queued = true;
				return;
			}
			this.refresh_running = true;
			do {
				this.refresh_queued = false;
				var replay = this.since_marker == 0;
				var files = yield this.fetch_pending();
				if (replay) {
					var old_n_items = this.items.size;
					this.items.clear();
					this.file_map.clear();
					if (old_n_items > 0) {
						this.items_changed(0, old_n_items, 0);
					}
				}
				foreach (var file in files) {
					if (file.status != 0) {
						if (!this.file_map.has_key(file.path)) {
							continue;
						}
						this.remove(this.file_map.get(file.path));
						continue;
					}
					if (this.file_map.has_key(file.path)) {
						var existing = this.file_map.get(file.path);
						existing.last_change_type = file.last_change_type;
						existing.last_modified = file.last_modified;
						existing.approve_id = file.approve_id;
						existing.reject_id = file.reject_id;
						existing.status = 0;
						continue;
					}
					this.append(file);
				}
			} while (this.refresh_queued);
			this.refreshed();
			this.refresh_running = false;
		}

		/**
		 * ListModel interface implementation: Get the item type.
		 */
		public Type get_item_type()
		{
			return typeof(FileWithHistory);
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
		 * @return The {@link FileWithHistory} at @position, or null if out of range
		 */
		public Object? get_item(uint position)
		{
			if (position >= this.items.size) {
				return null;
			}
			return this.items.get((int)position);
		}

		/**
		 * Clear all items from the list.
		 */
		public void clear()
		{
			var old_n_items = this.items.size;
			this.items.clear();
			this.file_map.clear();
			this.since_marker = 0;

			if (old_n_items > 0) {
				this.items_changed(0, (uint)old_n_items, 0);
			}
		}

		/**
		 * Check if a row is in the list.
		 *
		 * @param file The {@link FileWithHistory} row to check
		 * @return true if @file is in the list, false otherwise
		 */
		public bool contains(FileWithHistory file)
		{
			return this.items.contains(file);
		}

		/**
		 * Append an item to the list (ListStore-compatible).
		 *
		 * Local UI update only — prefer {@link refresh} after daemon index changes.
		 *
		 * @param item The {@link FileWithHistory} item to append
		 */
		public void append(FileWithHistory item)
		{
			var position = this.items.size;
			this.items.add(item);
			this.file_map.set(item.path, item);
			this.items_changed(position, 0, 1);
		}

		/**
		 * Remove an item from the list by item reference.
		 *
		 * @param item The {@link FileWithHistory} item to remove
		 */
		public void remove(FileWithHistory item)
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

			var item = this.items.get((int)position);
			this.items.remove_at((int)position);
			this.file_map.unset(item.path);
			this.items_changed(position, 1, 0);
		}
	}
}
