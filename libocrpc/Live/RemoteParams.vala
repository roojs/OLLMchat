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
	 * Params for {@link Remote} ref / unref.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var req = new OLLMrpc.Request() {
	 *     method = "RPC-Live-Remote.unref",
	 *     param = new OLLMrpc.Live.RemoteParams() {
	 *         object_id = handle
	 *     }
	 * };
	 * }}}
	 */
	public class RemoteParams : CallParam
	{
		public uint64 object_id { get; set; default = 0; }

		public static void rpc_register()
		{
			Bin.register("RemoteParams", typeof(RemoteParams));
		}
	}
}
