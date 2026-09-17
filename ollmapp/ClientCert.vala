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
	 * Desktop-side blank wire container for ''RPC-ClientCert'' rows.
	 *
	 * Mirrors the {@link OLLMfilesd.ClientCert} properties that cross the
	 * wire (the daemon skips its ''app'' handle). ''Bin.register'' is
	 * process-local: the daemon registers its DB entity as ''"ClientCert"'',
	 * the desktop registers this container as the same alias, and the wire
	 * carries the alias string — so the two ends need not share a type.
	 *
	 * @since 1.0
	 */
	public class ClientCert : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public int64 id { get; set; default = 0; }
		public string fingerprint { get; set; default = ""; }
		public int status { get; set; default = 0; }
		public string ip { get; set; default = ""; }
		public int64 created { get; set; default = 0; }
		public string requester { get; set; default = ""; }

		public static void rpc_register()
		{
			OLLMrpc.Bin.register("ClientCert", typeof(ClientCert));
		}
	}
}
