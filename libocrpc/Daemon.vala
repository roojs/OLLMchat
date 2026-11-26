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
	 * Wire type for Daemon.hello (one {@link Daemon} on {@link Response.retval}).
	 * Client deserializes into this class. ollmfilesd.Daemon
	 * subclasses it and answers hello.
	 */
	public class Daemon : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Daemon", typeof(Daemon));
		}

		/**
		 * Compare this version to ''version'' for ''depth'' leading numbers.
		 *
		 * Append .0.0.0.0, split on the dot, join the leading range,
		 * and compare those strings with filename collation. Depth 1
		 * is the first number. Depth 2 is the first two. Depth 3 is
		 * all three. A missing number is 0.
		 *
		 * @param version the other version
		 * @param depth how many leading numbers to compare
		 * @return 1 when this version is greater, -1 when it is smaller,
		 *   0 when they match
		 */
		public int compare(string version, int depth)
		{
			var ours = string.joinv(".", (this.version + ".0.0.0.0").split(".")[0:depth]);
			var theirs = string.joinv(".", (version + ".0.0.0.0").split(".")[0:depth]);
			var order = GLib.strcmp(ours.collate_key_for_filename(), theirs.collate_key_for_filename());
			return order > 0 ? 1 : order < 0 ? -1 : 0;
		}

		public int protocol { get; set; default = 1; }
		public string server { get; set; default = ""; }
		public bool ready { get; set; default = false; }
		public string version { get; set; default = "0.0.0"; }
	}

}
