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

namespace OLLMchat.History
{
	/**
	 * Manages session list with deduplication and fast lookup.
	 * 
	 * Implements ListModel interface using Gee.ArrayList as backing store.
	 * Provides ListStore-compatible methods that update the backing store and emit items_changed signals.
	 * Maintains multiple hashmaps for fast lookup by id and fid.
	 */
	public class SessionList : Object, GLib.ListModel
	{
		/**
		 * Backing store: ArrayList containing SessionBase objects.
		 * Uses id-based comparison for equality checks (since sessions come from database).
		 */
		private Gee.ArrayList<SessionBase> items { get; set; 
			default = new Gee.ArrayList<SessionBase>((a, b) => {
				return a.id == b.id;
			});
		}
		
		/**
		 * Hashmap of session id (as string) => SessionBase object for quick lookup.
		 */
		public Gee.HashMap<string, SessionBase> id_map { get; private set;
			default = new Gee.HashMap<string, SessionBase>(); }
		
		/**
		 * Hashmap of session fid => SessionBase object for quick fid lookup.
		 */
		public Gee.HashMap<string, SessionBase> fid_map { get; private set;
			default = new Gee.HashMap<string, SessionBase>(); }
		
		/**
		 * Constructor.
		 */
		public SessionList()
		{
			Object();
		}
		
		/**
		 * ListModel interface implementation: Get the item type.
		 */
		public Type get_item_type()
		{
			return typeof(SessionBase);
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
		 * Checks for duplicates by id before adding.
		 * Updates both id_map and fid_map.
		 * 
		 * @param item The SessionBase item to append
		 */
		public void append(SessionBase item)
		{
			// Check for duplicates by id
			if (this.contains(item)) {
				return;
			}
			
			this.items.add(item);
			this.id_map.set(item.id.to_string(), item);
			
			// Track in fid_map if fid is available
			if (item.fid != "") {
				this.fid_map.set(item.fid, item);
			}
			
			// Emit items_changed signal
			this.items_changed(this.items.size - 1, 0, 1);
		}
		
		/**
		 * Check if an item exists in the list.
		 * 
		 * @param item The SessionBase item to check
		 * @return true if item exists, false otherwise
		 */
		public bool contains(SessionBase item)
		{
			return this.id_map.has_key(item.id.to_string());
		}
		
		/**
		 * Remove an item from the list by item reference.
		 * Updates both id_map and fid_map.
		 * 
		 * @param item The SessionBase item to remove
		 */
		public void remove(SessionBase item)
		{
			var position = this.items.index_of(item);
			if (position < 0) {
				return; // Not found
			}
			
			this.remove_at((uint)position);
		}
		
		/**
		 * Remove an item at a specific position (ListStore-compatible).
		 * Updates both id_map and fid_map.
		 * 
		 * @param position The position of the item to remove
		 */
		public void remove_at(uint position)
		{
			if (position >= this.items.size) {
				return; // Invalid position
			}
			
			var item = this.items[(int)position];
			this.items.remove_at((int)position);
			
			// Remove from id_map and fid_map
			this.id_map.unset(item.id.to_string());
			if (item.fid != "") {
				this.fid_map.unset(item.fid);
			}
			
			// Emit items_changed signal
			this.items_changed(position, 1, 0);
		}
		
		/**
		 * Remove all items from the list (ListStore-compatible).
		 */
		public void remove_all()
		{
			var old_n_items = this.items.size;
			this.items.clear();
			this.id_map.clear();
			this.fid_map.clear();
			
			// Emit items_changed signal for ListModel
			if (old_n_items > 0) {
				this.items_changed(0, old_n_items, 0);
			}
		}
		
		/**
		 * Find an item in the list and return its position.
		 * 
		 * @param item The SessionBase item to find
		 * @param position Output parameter for the position if found
		 * @return true if item was found, false otherwise
		 */
		public bool find(SessionBase item, out uint position)
		{
			var index = this.items.index_of(item);
			if (index >= 0) {
				position = (uint)index;
				return true;
			}
			position = 0;
			return false;
		}
		
		/**
		 * Insert an item at a specific position.
		 * Updates both id_map and fid_map.
		 * 
		 * @param position The position to insert at
		 * @param item The SessionBase item to insert
		 */
		public void insert(uint position, SessionBase item)
		{
			// Check for duplicates by id
			if (this.contains(item)) {
				return;
			}
			
			if (position > this.items.size) {
				position = this.items.size;
			}
			
			this.items.insert((int)position, item);
			this.id_map.set(item.id.to_string(), item);
			
			// Track in fid_map if fid is available
			if (item.fid != "") {
				this.fid_map.set(item.fid, item);
			}
			
			// Emit items_changed signal
			this.items_changed(position, 0, 1);
		}
		
		/**
		 * Get a session by fid using the fid_map.
		 * 
		 * @param fid The file ID to lookup
		 * @return SessionBase object, or null if not found
		 */
		public SessionBase? get_by_fid(string fid)
		{
			if (fid == "") {
				return null;
			}
			return this.fid_map.get(fid);
		}
		
		/**
		 * Get a session by id using the id_map.
		 * 
		 * @param id The session ID to lookup
		 * @return SessionBase object, or null if not found
		 */
		public SessionBase? get_by_id(int64 id)
		{
			if (id <= 0) {
				return null;
			}
			return this.id_map.get(id.to_string());
		}
		
		/**
		 * Replace an item at a specific position.
		 * Updates both id_map and fid_map.
		 * 
		 * @param position The position of the item to replace
		 * @param item The new SessionBase item to replace with
		 */
		public void replace_at(uint position, SessionBase item)
		{
			if (position >= this.items.size) {
				return; // Invalid position
			}
			
			var old_item = this.items[(int)position];
			
			// Remove old item from maps
			this.id_map.unset(old_item.id.to_string());
			if (old_item.fid != "") {
				this.fid_map.unset(old_item.fid);
			}
			
			// Replace in list
			this.items[(int)position] = item;
			
			// Add new item to maps
			this.id_map.set(item.id.to_string(), item);
			if (item.fid != "") {
				this.fid_map.set(item.fid, item);
			}
			
			// Emit items_changed signal (1 removed, 1 added at same position)
			this.items_changed(position, 1, 1);
		}
		
		/**
		 * Update fid mapping for a session.
		 * Called when a session's fid changes.
		 * 
		 * @param session The session to update
		 * @param old_fid The previous fid (if any)
		 */
		public void update_fid(SessionBase session, string old_fid = "")
		{
			// Remove old fid from map if it exists
			if (old_fid != "") {
				this.fid_map.unset(old_fid);
			}
			
			// Add new fid to map if it exists
			if (session.fid != "") {
				this.fid_map.set(session.fid, session);
			}
		}
		
	}
}

