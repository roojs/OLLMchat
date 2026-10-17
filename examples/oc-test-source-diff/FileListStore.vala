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

namespace OLLMapp
{
	/**
	 * Files for the folder selected in the file selector.
	 *
	 * A {@link GLib.ListModel} of {@link OLLMfiles.File}. {@link load}
	 * asks the file server for one folder and keeps that reply as the
	 * model. The rows are not copied into a {@link GLib.ListStore}. A
	 * newer {@link load} or {@link clear} drops a reply that is still
	 * waiting. {@link empty} is true only after a reply that listed no
	 * files. It stays false while a request is waiting.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new FileListStore();
	 * yield store.load(folder);
	 * }}}
	 */
	class FileListStore : Object, GLib.ListModel
	{
		/**
		 * Rows from the last reply. This list is the model. It is not
		 * copied into a {@link GLib.ListStore}.
		 */
		public Gee.ArrayList<OLLMfiles.File> items {
			get; private set; default = new Gee.ArrayList<OLLMfiles.File>();
		}

		/**
		 * Generation of the folder-file request. A newer load or clear
		 * drops the reply from the previous one.
		 */
		private int epoch = 0;

		/**
		 * True after a reply that listed no files. False while a
		 * request is waiting, and false when rows are shown.
		 */
		public bool empty { get; private set; default = false; }

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(OLLMfiles.File);
		}

		/**
		 * Number of files in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * File at ''position''.
		 *
		 * @param position Zero-based index
		 * @return The file, or null when ''position'' is past the end
		 */
		public Object? get_item(uint position)
		{
			if (position >= this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Drop every file. A newer folder selection uses this before
		 * the reply, and a cleared selection uses it on its own.
		 */
		public void clear()
		{
			this.epoch++;
			this.empty = false;
			if (this.items.size == 0) {
				return;
			}
			var removed = this.items.size;
			this.items.clear();
			this.items_changed(0, (uint) removed, 0);
		}

		/**
		 * Ask the file server for ''folder'''s files and show those
		 * rows. A newer call drops the previous reply.
		 *
		 * @param folder Folder whose files should be listed
		 */
		public async void load(OLLMfiles.Folder folder)
		{
			this.clear();
			var epoch = this.epoch;
			OLLMrpc.Response response;
			try {
				response = yield folder.manager.rpc.call(new OLLMrpc.Request() {
					method = "Folder.fetch_dir",
					args = OLLMrpc.args("s", folder.path)
				});
			} catch (GLib.Error e) {
				if (epoch != this.epoch) {
					return;
				}
				if (e.code == (int) OLLMrpc.RpcErrorCode.NOT_CONNECTED) {
					folder.manager.rpc.notification(new OLLMrpc.Notification() {
						method = "client.filesd.unreachable",
						id = e.code
					});
					return;
				}
				folder.manager.rpc.notification(new OLLMrpc.Notification() {
					method = "Banner.show",
					message = "Could not load files: " + e.message
				});
				return;
			}
			if (epoch != this.epoch) {
				return;
			}
			if (response.retval.type() == GLib.Type.INVALID) {
				this.empty = true;
				return;
			}
			var rows = (Gee.ArrayList<OLLMfiles.File>) response.retval.get_object();
			if (rows.size == 0) {
				this.empty = true;
				return;
			}
			foreach (var file in rows) {
				file.manager = folder.manager;
			}
			this.items = rows;
			this.items_changed(0, 0, (uint) rows.size);
		}
	}
}
