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
	 * One file row from Hub {@code GET /api/models/{id}/tree/{rev}}.
	 */
	public class ModelTreeEntry : GLib.Object, OLLMrpc.Bin.Serializable
	{
		/** Repo-relative path (Hub {@code path}). */
		public string path { get; set; default = ""; }

		/** File size in bytes when present on the tree row. */
		public int64 size { get; set; default = 0; }

		public static void rpc_register() {
			OLLMrpc.Bin.register("ModelTreeEntry", typeof(ModelTreeEntry));
		}
	}

	/**
	 * Decode-only wrapper for Hub repo tree listings.
	 *
	 * Hub returns a JSON array; {@link OLLMrpc.Client} wraps it as
	 * {@code {"items": […]}} before bin decode.
	 */
	public class ModelTreeArray : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public Gee.ArrayList<ModelTreeEntry> items {
			get; set; default = new Gee.ArrayList<ModelTreeEntry>();
		}

		public static void rpc_register() {
			OLLMrpc.Bin.register("ModelTreeArray", typeof(ModelTreeArray));
		}

		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error {
			switch (prop.name) {
				case "items":
					this.bin_write_prop_array(
						ctx,
						prop.name,
						typeof(ModelTreeEntry)
					);
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
		) throws GLib.Error {
			switch (prop.name) {
				case "items":
					this.items = (Gee.ArrayList<ModelTreeEntry>) this.read_anon_array(
						ctx,
						prop.name,
						type_byte,
						typeof(ModelTreeEntry)
					);
					return;
				default:
					this.bin_default_read_prop(ctx, prop, type_byte);
					return;
			}
		}
	}
}
