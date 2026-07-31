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

namespace OLLMchat
{
	/**
	 * Mid-run queue of {@link Message} rows as a {@link GLib.ListModel}.
	 *
	 * Same shape as {@link History.SessionList}: Gee.ArrayList backing store,
	 * ListStore-compatible ''append'' / ''remove'' / ''remove_at'' that emit
	 * ''items_changed''. Replacing {@link items} (e.g. session load) also
	 * emits ''items_changed''.
	 *
	 * Temporary store only: pending vs urgent is the message ''role'' string
	 * while queued (''"user"'' = pending / follow-up; ''"urgent"'' = urgent).
	 * UI / callers set ''role''; this class only owns the list model. Always
	 * {@link append} — {@link insert} is unsupported.
	 *
	 * == Usage Examples ==
	 *
	 * {{{
	 *   var items = new Gee.ArrayList<Message>();  // session-owned
	 *   var q = new MessageQueue(items);
	 *   q.append(user_msg);
	 *   user_msg.role = "urgent";   // UI escalates
	 *
	 *   // Session load: swap backing list (ColumnView keeps the same model)
	 *   q.items = loaded_session.queued_messages;
	 *
	 *   // Drain most recent urgent via FilterListModel, then remove from q
	 *   var urgent = new Gtk.FilterListModel(q, new Gtk.CustomFilter((item) => {
	 *       return ((Message) item).role == "urgent";
	 *   }));
	 *   if (urgent.get_n_items() > 0) {
	 *       var msg = (Message) urgent.get_item(urgent.get_n_items() - 1);
	 *       q.remove(msg);
	 *       msg.role = "user";
	 *   }
	 * }}}
	 */
	public class MessageQueue : Object, GLib.ListModel
	{
		private Gee.ArrayList<Message> items_store = new Gee.ArrayList<Message>();

		/**
		 * Backing store of queued messages (append order = enqueue time).
		 *
		 * Session-owned. Replace on session load; emits ''items_changed'' for
		 * the full old→new range.
		 */
		public Gee.ArrayList<Message> items {
			get {
				return this.items_store;
			}
			set {
				if (this.items_store == value) {
					return;
				}
				var removed = this.items_store.size;
				this.items_store = value;
				this.items_changed(0, removed, value.size);
			}
		}

		/**
		 * Relay: Agent / Factory emit to toggle mid-run composer + strip.
		 * ChatWidget connects; this class does not store the flag.
		 *
		 * @param enabled whether mid-run queuing is on
		 */
		public signal void can_queue(bool enabled);

		/**
		 * @param items session-owned list to back this model (may be empty)
		 */
		public MessageQueue(Gee.ArrayList<Message> items)
		{
			Object();
			this.items = items;
		}

		/**
		 * ListModel: item type.
		 */
		public Type get_item_type()
		{
			return typeof(Message);
		}

		/**
		 * ListModel: number of items.
		 */
		public uint get_n_items()
		{
			return this.items.size;
		}

		/**
		 * ListModel: item at ''position''.
		 *
		 * @param position zero-based index
		 * @return the {@link Message}, or null if out of range
		 */
		public Object? get_item(uint position)
		{
			if (position >= this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Append a message (ListStore-compatible). Emits ''items_changed''.
		 *
		 * @param message row to queue
		 */
		public void append(Message message)
		{
			if (this.items.contains(message)) {
				return;
			}
			this.items.add(message);
			this.items_changed(this.items.size - 1, 0, 1);
		}

		/**
		 * Whether ''message'' is in the queue.
		 *
		 * @param message candidate
		 * @return true if present
		 */
		public bool contains(Message message)
		{
			return this.items.contains(message);
		}

		/**
		 * Remove by reference (ListStore-compatible).
		 *
		 * @param message row to remove
		 */
		public void remove(Message message)
		{
			var position = this.items.index_of(message);
			if (position < 0) {
				return;
			}
			this.remove_at((uint) position);
		}

		/**
		 * Remove at ''position'' (ListStore-compatible). Emits ''items_changed''.
		 *
		 * @param position index to remove
		 */
		public void remove_at(uint position)
		{
			if (position >= this.items.size) {
				return;
			}
			this.items.remove_at((int) position);
			this.items_changed(position, 1, 0);
		}

		/**
		 * Remove all rows (ListStore-compatible).
		 */
		public void remove_all()
		{
			var old_n = this.items.size;
			this.items.clear();
			if (old_n > 0) {
				this.items_changed(0, old_n, 0);
			}
		}

		/**
		 * Find ''message'' and return its position.
		 *
		 * @param message row to find
		 * @param position set when found
		 * @return true if found
		 */
		public bool find(Message message, out uint position)
		{
			var index = this.items.index_of(message);
			if (index >= 0) {
				position = (uint) index;
				return true;
			}
			position = 0;
			return false;
		}

		/**
		 * Unsupported — queue is append-only. Asserts not reached.
		 *
		 * @param position ignored
		 * @param message ignored
		 */
		public void insert(uint position, Message message)
		{
			GLib.assert_not_reached();
		}
	}
}
