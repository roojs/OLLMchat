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
	 * Manages immediate children of one {@link Folder} (flat list for tree UI).
	 *
	 * V2 client: used as {@link Folder.children}. Provides list
	 * ({@link GLib.ListModel}) and {@link child_map} (basename lookup) for one
	 * directory level. The daemon builds the full tree via {@code read_dir};
	 * this list is not hydrated automatically — populate via {@link append} /
	 * {@link remove} until a {@code Folder.fetch_children} RPC lands (plan
	 * 2.10.4.16). No {@code cleanup_deleted} on the client (daemon-only).
	 */
	public class FolderFiles : Object, GLib.ListModel
	{
		/**
		 * Backing store: files and subfolders in one directory.
		 * Uses path-based comparison for equality checks.
		 */
		public Gee.ArrayList<FileBase> items {
			get; set; default = new Gee.ArrayList<FileBase>((a, b) => {
				return a.path == b.path;
			});
		}

		/**
		 * Hashmap of [name in dir] => {@link FileBase} for quick lookup by basename.
		 */
		public Gee.HashMap<string, FileBase> child_map { get; private set;
			default = new Gee.HashMap<string, FileBase>(); }

		/**
		 * Constructor.
		 */
		public FolderFiles()
		{
			Object();
		}

		/**
		 * ListModel interface implementation: Get the item type.
		 */
		public Type get_item_type()
		{
			return typeof(FileBase);
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
		 * @return The {@link FileBase} at @position, or null if out of range
		 */
		public Object? get_item(uint position)
		{
			if (position >= this.items.size) {
				return null;
			}
			return this.items[(int)position];
		}

		/**
		 * Append an item to the list (ListStore-compatible).
		 * Checks for duplicates before adding.
		 *
		 * @param item The {@link FileBase} item to append
		 */
		public void append(FileBase item)
		{
			if (this.contains(item)) {
				return;
			}

			var position = this.items.size;
			this.items.add(item);
			this.child_map.set(GLib.Path.get_basename(item.path), item);
			this.items_changed(position, 0, 1);
		}

		/**
		 * Find an item in the list and return its position.
		 *
		 * @param item The {@link FileBase} item to find
		 * @param position Output parameter for the position if found
		 * @return true if @item was found, false otherwise
		 */
		public bool find(FileBase item, out uint position)
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
		 * @param item The {@link FileBase} item to insert
		 */
		public void insert(uint position, FileBase item)
		{
			if (position > this.items.size) {
				position = this.items.size;
			}

			this.items.insert((int)position, item);
			this.child_map.set(GLib.Path.get_basename(item.path), item);
			this.items_changed(position, 0, 1);
		}

		/**
		 * Check if an item exists in the list.
		 *
		 * @param item The {@link FileBase} item to check
		 * @return true if @item exists, false otherwise
		 */
		public bool contains(FileBase item)
		{
			return this.child_map.has_key(GLib.Path.get_basename(item.path));
		}

		/**
		 * Remove an item from the list by item reference.
		 *
		 * @param item The {@link FileBase} item to remove
		 */
		public void remove(FileBase item)
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

			var item = this.items[(int)position];
			this.items.remove_at((int)position);
			this.child_map.unset(GLib.Path.get_basename(item.path));
			this.items_changed(position, 1, 0);
		}

		/**
		 * Remove all items from the list (ListStore-compatible).
		 */
		public void remove_all()
		{
			var old_n_items = this.items.size;
			this.items.clear();
			this.child_map.clear();

			if (old_n_items > 0) {
				this.items_changed(0, old_n_items, 0);
			}
		}
	}
}
