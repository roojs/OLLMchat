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
	 * Per-subscription holder for by-name GObject connect.
	 *
	 * {@link emit} is the C-callable method GObject invokes for named
	 * signals. {@link hid} is the handler id for disconnect.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var subscription = new OLLMrpc.Live.Subscription() {
	 *     connection = connection,
	 *     method = "closed",
	 *     id = (int) handle
	 * };
	 * subscription.hid = GLib.Signal.connect_swapped(obj, "closed",
	 *     (GLib.Callback) Subscription.emit, subscription);
	 * }}}
	 */
	public class Subscription : GLib.Object
	{
		public Transport.Connection connection { get; set; }
		public string method { get; set; default = ""; }
		public int id { get; set; default = 0; }
		public ulong hid { get; set; default = 0; }

		public void emit()
		{
			this.connection.write(new Notification() {
				method = this.method,
				id = this.id
			});
		}
	}
}
