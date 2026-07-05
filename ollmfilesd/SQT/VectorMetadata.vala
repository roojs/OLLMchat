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

namespace OLLMfilesd.SQT
{
	/**
	 * RPC wire type for {@code File.vector_metadata}.
	 *
	 * Extends {@link OLLMvector2.SQT.VectorMetadata}; bin registration and
	 * RPC {@link query} live on this subclass only.
	 */
	public class VectorMetadata : OLLMvector2.SQT.VectorMetadata,
		OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.register(
				"VectorMetadata",
				typeof(VectorMetadata)
			);
		}

		/**
		 * RPC read path — hydrates {@link VectorMetadata} subclass rows.
		 *
		 * Indexing uses {@link OLLMvector2.SQT.VectorMetadata.query} on the parent.
		 */
		public static new SQ.Query<VectorMetadata> query(SQ.Database db)
		{
			return new SQ.Query<VectorMetadata>(db, "vector_metadata");
		}

		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "parent":
				case "children":
					return;
				default:
					bin_default_write_prop(ctx, prop);
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
				case "parent":
				case "children":
					return;
				default:
					bin_default_read_prop(ctx, prop, type_byte);
					return;
			}
		}
	}
}
