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

namespace OLLMrpc
{
	/**
	 * Base class for typed {@link Request.param} bags.
	 *
	 * Subclass and add GObject properties for each wire field. Daemon
	 * param types live in ollmfilesd (FolderParams, FileParams, …).
	 *
	 * == Example ==
	 *
	 * {{{
	 * public class DaemonParams : OLLMrpc.CallParam {
	 *     public int protocol { get; set; default = 0; }
	 *     public string client { get; set; default = ""; }
	 *
	 *     public static void rpc_register() {
	 *         OLLMrpc.Bin.register("DaemonParams", typeof(DaemonParams));
	 *     }
	 * }
	 *
	 * var req = new OLLMrpc.Request() {
	 *     method = "Daemon.hello",
	 *     param = new DaemonParams() {
	 *         protocol = 1,
	 *         client = "my-app"
	 *     }
	 * };
	 * }}}
	 *
	 * @see Request
	 */
	public class CallParam : GLib.Object, Bin.Serializable
	{
		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}
	}
}
