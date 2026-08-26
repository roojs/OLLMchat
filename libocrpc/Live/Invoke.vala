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
	 * Server → client GI callback invoke (has a {@link Callback.reply}).
	 *
	 * Not a {@link Notification}. Subscribe / banners keep that type.
	 *
	 * == Example ==
	 *
	 * {{{
	 * connection.write(new OLLMrpc.Live.Invoke() {
	 *     id = callback_id,
	 *     reply_id = 3,
	 *     args = OLLMrpc.args("tu", monitor_lease, watch_id)
	 * });
	 * }}}
	 */
	public class Invoke : GLib.Object, Bin.Serializable
	{
		public int id { get; set; default = 0; }
		public int reply_id { get; set; default = 0; }
		public Gee.ArrayList<GLib.Value?> args {
			get; set; default = new Gee.ArrayList<GLib.Value?>();
		}

		public static void rpc_register()
		{
			Bin.register("Invoke", typeof(Invoke));
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		/**
		 * Encode one property.
		 *
		 * Omits {@link reply_id} at 0 and empty {@link args}.
		 *
		 * @param ctx active bin session
		 * @param prop property being written
		 * @throws GLib.Error on encode failure
		 */
		public override void bin_write_prop(
			Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "reply-id":
					if (this.reply_id == 0) {
						return;
					}
					this.bin_default_write_prop(ctx, prop);
					return;
				case "args":
					if (this.args.size == 0) {
						return;
					}
					ctx.write_tag(prop.name);
					ctx.out_stream.put_byte((uint8) GLib.Type.INVALID | 0x80);
					if (this.args.size < 128) {
						ctx.out_stream.put_byte((uint8) this.args.size);
					} else {
						ctx.out_stream.put_byte(
							(uint8) (0x80 | ((this.args.size >> 8) & 0x7F))
						);
						ctx.out_stream.put_byte((uint8) (this.args.size & 0xFF));
					}
					foreach (var val in this.args) {
						Bin.StreamValue.write(ctx, val);
					}
					return;
				default:
					this.bin_default_write_prop(ctx, prop);
					return;
			}
		}

		/**
		 * Decode one property.
		 *
		 * {@link args} is ''ANY[]'' (same encoding as {@link Request.args}).
		 *
		 * @param ctx active bin session
		 * @param prop property being read
		 * @param type_byte wire type byte already consumed
		 * @throws GLib.Error on decode failure
		 */
		public override void bin_read_prop(
			Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			switch (prop.name) {
				case "args":
					var n = ctx.in_stream.read_byte();
					var count = n & 0x7F;
					if ((n & 0x80) != 0) {
						count = (count << 8) | ctx.in_stream.read_byte();
					}
					for (var i = 0; i < count; i++) {
						var elem = ctx.in_stream.read_byte();
						this.args.add(Bin.StreamValue.read(ctx, elem));
					}
					return;
				default:
					this.bin_default_read_prop(ctx, prop, type_byte);
					return;
			}
		}
	}
}
