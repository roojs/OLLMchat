/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMrpc.Live
{
	/**
	 * Per-callback row: write {@link Invoke} and wait for {@link Callback.reply}.
	 *
	 * {@link emit} is the generic fire (consumer trampolines pack args
	 * then call this). {@link drop} is DestroyNotify.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var row = connection.callbacks.get(id);
	 * row.emit(OLLMrpc.args("tu", connection.export(monitor), watch_id));
	 * }}}
	 */
	public class Hook : GLib.Object
	{
		public Transport.Connection connection { get; set; }
		public int id { get; set; default = 0; }
		public int reply_id { get; set; default = 0; }
		public bool replied { get; set; default = false; }
		public Gee.ArrayList<GLib.Value?> reply_args {
			get; set; default = new Gee.ArrayList<GLib.Value?>();
		}

		/**
		 * Write {@link Invoke} and wait for {@link Callback.reply}.
		 *
		 * @param args packed GI callback arguments
		 */
		public void emit(Gee.ArrayList<GLib.Value?> args)
		{
			this.replied = false;
			this.reply_id = this.connection.next_handle;
			this.connection.next_handle++;
			this.connection.write(new Invoke() {
				id = this.id,
				reply_id = this.reply_id,
				args = args
			});
			while (!this.replied) {
				GLib.MainContext.default().iteration(true);
			}
		}

		/**
		 * DestroyNotify: drop the row and tell the client to forget.
		 *
		 * @param user row from {@link Transport.Connection.callbacks}
		 */
		public static void drop(Hook user)
		{
			user.replied = true;
			if (!user.connection.callbacks.has_key(user.id)) {
				return;
			}
			user.connection.callbacks.unset(user.id);
			user.connection.write(new Notification() {
				method = "RPC-Live-Callback.unregister",
				id = user.id
			});
		}
	}
}
