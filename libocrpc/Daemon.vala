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
	/**
	 * Wire type for {@code Daemon.hello} ({@code result_type = "Daemon"}).
	 * Client deserializes into this class. Server type is
	 * {@code ollmfilesd/Daemon.vala} (unchanged).
	 */
	public class Daemon : GLib.Object, Json.Serializable
	{
		public static void rpc_register()
		{
			register("Daemon", typeof(Daemon));
		}

		public int protocol { get; set; default = 1; }
		public string server { get; set; default = ""; }
		public bool ready { get; set; default = false; }
	}

}
