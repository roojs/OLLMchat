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
		public GLib.Object? result { get; set; default = null; }
		public string msg { get; set; default = ""; }
		/**
		 * {@code File.read} only: {@code 0} = plain UTF-8 ({@code is_text}),
		 * {@code 1} = base64 (not {@code is_text}).
		 */
		public int msg_encode { get; set; default = 0; }
		/**
		 * Set by handlers before reply; used when encoding empty object arrays.
		 */
		public string result_type { get; set; default = ""; }
		/** When true, {@link result} is a {@link Gee.ArrayList} on the wire. */
		public bool is_array { get; set; default = false; }

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
					if (this.result == null) {
						return;
					}
					if (!this.is_array) {
						this.bin_default_write_prop (ctx, prop);
						return;
					}
					var list = this.result as Gee.ArrayList<GLib.Object>;
					if (list == null) {
						GLib.error(
							"Response: is_array but result is not Gee.ArrayList"
						);
					}
					ctx.write_tag (prop.name);
					if (list.size == 0 && (
						Bin.alias_to_gtype == null
						|| !Bin.alias_to_gtype.has_key (
							this.result_type
						)
					)) {
						throw new Bin.StreamError.REGISTRATION (
							"Unrecognized type alias: %s",
							this.result_type
						);
					}
					ctx.write_gtype (
						list.size > 0
							? list.get (0).get_type ()
							: Bin.alias_to_gtype.get (
								this.result_type
							),
						(uint8) GLib.Type.OBJECT | 0x80
					);
					if (list.size < 128) {
						ctx.out_stream.put_byte ((uint8) list.size);
					} else {
						ctx.out_stream.put_byte (
							(uint8) (0x80 | ((list.size >> 8) & 0x7F))
						);
						ctx.out_stream.put_byte (
							(uint8) (list.size & 0xFF)
						);
					}
					foreach (var child in list) {
						((Bin.Serializable) child).bin_write (ctx);
					}
					return;
				case "result-type":
				case "is-array":
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
					this.is_array = true;
					this.result = ctx.parse_object_array ();
					return;
				case "result-type":
				case "is-array":
					return;
				default:
					this.bin_default_read_prop (ctx, prop, type_byte);
					return;
			}
		}
	}
}
