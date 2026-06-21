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
	 * V2 client: implements {@link GLib.ListModel} over {@link File} rows where
	 * the daemon has {@code is_need_approval == true}. Owns the
	 * {@code Folder.fetch_pending_approvals} RPC — call {@link refresh} to
	 * reload the list model, or {@link fetch_pending} for the snapshot only.
	 */
	public class ReviewFiles : Object, GLib.ListModel
	{
		/**
		 * Project folder this list belongs to.
		 */
		public Folder project { get; construct; }

		/**
		 * Backing store: {@link File} objects pending approval.
		 * Uses database id for equality checks.
		 */
		private Gee.ArrayList<File> items { get; set;
			default = new Gee.ArrayList<File>((a, b) => {
				return a.id == b.id;
			});
		}

		/**
		 * Hashmap of file path => {@link File} object for quick lookup.
		 */
		public Gee.HashMap<string, File> file_map { get; private set;
			default = new Gee.HashMap<string, File>(); }

		/**
		 * Constructor.
		 *
		 * @param project Project folder ({@code is_project == true})
		 */
		public ReviewFiles(Folder project)
		{
			Object(project: project);
		}

		/**
		 * Fetch files pending approval from the daemon ({@code Folder.fetch_pending_approvals} wire).
		 *
		 * Does not update this {@link GLib.ListModel} — use {@link refresh} for that.
		 *
		 * @return Files needing approval in {@link project}
		 */
		public async Gee.ArrayList<File> fetch_pending()
		{
			var response = yield this.project.manager.rpc.call(new OLLMrpc.Request() {
				method = "Folder.fetch_pending_approvals",
				param = new OLLMfilesd.FolderParams() { path = this.project.path }
			});
			if (response.error != null) {
				return new Gee.ArrayList<File>();
			}
			var files = (Gee.ArrayList<File>) response.result;
			foreach (var file in files) {
				file.manager = this.project.manager;
				this.project.manager.file_cache.set(file.path, file);
			}
			return files;
		}

		/**
		 * Reload pending-approval rows from the daemon into this list model.
		 *
		 * Replaces the full snapshot and emits {@link GLib.ListModel.items_changed}
		 * when the row count changes.
		 */
		public async void refresh()
		{
			var old_n_items = this.items.size;
			this.items.clear();
			this.file_map.clear();

			var files = yield this.fetch_pending();
			foreach (var file in files) {
				this.items.add(file);
				this.file_map.set(file.path, file);
			}

			var new_n_items = this.items.size;
			if (old_n_items > 0 || new_n_items > 0) {
				this.items_changed(0, old_n_items, new_n_items);
			}
		}

		/**
		 * ListModel interface implementation: Get the item type.
		 */
		public Type get_item_type()
		{
			return typeof(File);
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
		 * @return The {@link File} at @position, or null if out of range
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

			if (old_n_items > 0) {
				this.items_changed(0, (uint)old_n_items, 0);
			}
		}

		/**
		 * Check if a file is in the list.
		 *
		 * @param file The {@link File} object to check
		 * @return true if @file is in the list, false otherwise
		 */
		public bool contains(File file)
		{
			return this.items.contains(file);
		}

		/**
		 * Append an item to the list (ListStore-compatible).
		 *
		 * Local UI update only — prefer {@link refresh} after daemon index changes.
		 *
		 * @param item The {@link File} item to append
		 */
		public void append(File item)
		{
			var position = this.items.size;
			this.items.add(item);
			this.file_map.set(item.path, item);
			this.items_changed(position, 0, 1);
		}

		/**
		 * Remove an item from the list by item reference.
		 *
		 * @param item The {@link File} item to remove
		 */
		public void remove(File item)
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
