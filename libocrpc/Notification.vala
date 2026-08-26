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
		/** Referenced object id when {@link object_type} has one; 0 for singletons. */
		public int id { get; set; default = 0; }
		public string message { get; set; default = ""; }
		/** Bytes completed when {@link method} carries progress (else 0). */
		public int64 progress_completed { get; set; default = 0; }
		/** Bytes total when {@link method} carries progress (else 0). */
		public int64 progress_total { get; set; default = 0; }
		/**
		 * Banner action: tool verb (''cancel'') or ''rpc.'' + method (''rpc.Codebase.stop'').
		 */
		public string action { get; set; default = ""; }
		/**
		 * Banner button label (''Cancel'', ''Pause'', ''Resume''); empty = no button.
		 */
		public string action_label { get; set; default = ""; }

		/** Filled by {@link Live.BufferStream.attach}; null on send. */
		public Live.Buffer? buffer { get; internal set; default = null; }

		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Notification", typeof(Notification));
		}

		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "buffer":
					return;
				case "method":
					ctx.write_tag(prop.name);
					ctx.write_name_ref(this.method);
					return;
				default:
					this.bin_default_write_prop(ctx, prop);
					return;
			}
		}

		public override void bin_read_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			switch (prop.name) {
				case "buffer":
					return;
				case "method":
					this.method = ctx.read_name_ref(type_byte);
					return;
				default:
					this.bin_default_read_prop(ctx, prop, type_byte);
					return;
			}
		}
	}
}
