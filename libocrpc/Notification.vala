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

namespace OLLMrpc
{
	/** Bin RPC notification (no matching {@link Response} id). */
	public class Notification : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string method { get; set; default = ""; }
		public string object_type { get; set; default = ""; }
		/** Referenced object id when {@link object_type} has one; {@code 0} for singletons. */
		public int id { get; set; default = 0; }
		public string message { get; set; default = ""; }

		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Notification", typeof(Notification));
		}
	}
}
