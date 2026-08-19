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
	 * Params for {@link Subscribe} signal / unsubscribe.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var req = new OLLMrpc.Request() {
	 *     method = "RPC-Live-Subscribe.signal",
	 *     param = new OLLMrpc.Live.SubscribeParams() {
	 *         object_id = handle,
	 *         name = "notify::title"
	 *     }
	 * };
	 * }}}
	 */
	public class SubscribeParams : CallParam
	{
		public uint64 object_id { get; set; default = 0; }
		public string name { get; set; default = ""; }

		public static void rpc_register()
		{
			Bin.register("SubscribeParams", typeof(SubscribeParams));
		}
	}
}
