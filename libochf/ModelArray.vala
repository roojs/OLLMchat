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

namespace OLLMhf
{
	/**
	 * Decode-only wrapper for Hub search results.
	 *
	 * Hub {{{GET /api/models}}} returns a JSON array; {@link OLLMrpc.Client}
	 * wraps it as {{{{"items": […]}}}} before bin decode. Use
	 * {@link OLLMrpc.Request.result_type} = typeof(ModelArray) on search calls.
	 */
	public class ModelArray : GLib.Object, OLLMrpc.Bin.Serializable
	{
		/** Models from the search response. */
		public Gee.ArrayList<Model> items {
			get; set; default = new Gee.ArrayList<Model>();
		}

		public static void rpc_register() {
			OLLMrpc.Bin.register("ModelArray", typeof(ModelArray));
		}

		public override void bin_read_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error {
			switch (prop.name) {
				case "items":
					if ((type_byte & 0x7F) != GLib.Type.OBJECT
						|| (type_byte & 0x80) == 0) {
						throw new OLLMrpc.Bin.SerializableError.PROPERTY(
							"prop '%s' expected object array", prop.name);
					}
					ctx.read_gtype();
					var count = (uint) ctx.in_stream.read_byte();
					if ((count & 0x80) != 0) {
						count = ((count & 0x7F) << 8) | ctx.in_stream.read_byte();
					}
					this.items = new Gee.ArrayList<Model>();
					for (var i = 0; i < count; i++) {
						var child = (Model) GLib.Object.new(typeof(Model));
						child.bin_read(ctx);
						this.items.add(child);
					}
					return;
				default:
					this.bin_default_read_prop(ctx, prop, type_byte);
					return;
			}
		}
	}
}
