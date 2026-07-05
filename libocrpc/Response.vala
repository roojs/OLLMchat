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
	/** Bin RPC response (wire {@link id}, plus {@link result} or {@link error}). */
	public class Response : GLib.Object, Bin.Serializable
	{
		public int id { get; set; default = 0; }
		public Error? error { get; set; default = null; }
		/** Object list on the wire (length 0, 1, or N). Single objects use one element. Never null. */
		public Gee.ArrayList<GLib.Object> result {
			get;
			set;
			default = new Gee.ArrayList<GLib.Object> ();
		}
		public string msg { get; set; default = ""; }
		/**
		 * {{{File.read}}} only: {{{0}}} = plain UTF-8 ({{{is_text}}}),
		 * {{{1}}} = base64 (not {{{is_text}}}).
		 */
		public int msg_encode { get; set; default = 0; }

		public static void rpc_register()
		{
			Bin.register("Response", typeof(Response));
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public override void bin_write_prop (
			Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "result":
					if (this.result.size == 0) {
						return;
					}
					ctx.write_tag (prop.name);
					ctx.write_gtype (
						this.result.get (0).get_type (),
						(uint8) GLib.Type.OBJECT | 0x80
					);
					if (this.result.size < 128) {
						ctx.out_stream.put_byte ((uint8) this.result.size);
					} else {
						ctx.out_stream.put_byte (
							(uint8) (0x80 | ((this.result.size >> 8) & 0x7F))
						);
						ctx.out_stream.put_byte (
							(uint8) (this.result.size & 0xFF)
						);
					}
					foreach (var child in this.result) {
						((Bin.Serializable) child).bin_write (ctx);
					}
					return;
				default:
					this.bin_default_write_prop (ctx, prop);
					return;
			}
		}

		public override void bin_read_prop (
			Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			switch (prop.name) {
				case "result":
					if ((type_byte & 0x80) == 0
						|| (type_byte & 0x7F) != GLib.Type.OBJECT) {
						this.bin_default_read_prop (ctx, prop, type_byte);
						return;
					}
					this.result = ctx.parse_object_array ();
					return;
				default:
					this.bin_default_read_prop (ctx, prop, type_byte);
					return;
			}
		}
	}
}
