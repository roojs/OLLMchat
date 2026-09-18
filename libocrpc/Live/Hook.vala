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

		/** One in-flight emit: emits nest, so reply state cannot live on the row. */
		private class Frame : GLib.Object
		{
			public bool replied { get; set; default = false; }
			public Gee.ArrayList<GLib.Value?> args {
				get; set; default = new Gee.ArrayList<GLib.Value?>();
			}
		}

		private Gee.HashMap<int, Frame> frames = new Gee.HashMap<int, Frame>();

		/**
		 * Write {@link Invoke} and wait for {@link Callback.reply}.
		 *
		 * @param args packed GI callback arguments
		 */
		public virtual void emit(Gee.ArrayList<GLib.Value?> args)
		{
			var correlation = this.connection.next_handle;
			this.connection.next_handle++;
			var frame = new Frame();
			this.frames.set(correlation, frame);

			this.replied = false;
			this.reply_id = correlation;
			this.connection.write(new Invoke() {
				id = this.id,
				reply_id = correlation,
				args = args
			});
			while (!frame.replied && !this.replied) {
				this.connection.emit_wait_poll();
			}
			this.frames.unset(correlation);
			this.reply_args.clear();
			foreach (var arg in frame.args) {
				this.reply_args.add(arg);
			}
		}

		/**
		 * Complete the emit waiting on ''correlation''.
		 *
		 * @param correlation {@link Invoke.reply_id} the client replied to
		 * @param args values after the ''reply_id'' argument
		 * @return ''false'' when no emit on this row is waiting for it
		 */
		public bool complete(int correlation, Gee.ArrayList<GLib.Value?> args)
		{
			if (!this.frames.has_key(correlation)) {
				return false;
			}
			var frame = this.frames.get(correlation);
			frame.args.clear();
			foreach (var arg in args) {
				frame.args.add(arg);
			}
			frame.replied = true;
			return true;
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
