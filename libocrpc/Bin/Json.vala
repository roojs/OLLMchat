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

namespace OLLMrpc.Bin
{
	/**
	 * JSON ↔ {@link Stream} bridge for tests and tooling.
	 *
	 * Encodes json-glib nodes directly onto a {@link Stream} out_stream and
	 * decodes wire bytes back into json-glib nodes. Property layout follows
	 * JSON node shape and wire type bytes only — no {@link Serializable}
	 * instances and no GObject property schema.
	 *
	 * Wire aliases live in meta keys (not payload properties):
	 *
	 *  * `*type` on every object (`"Request"`, `"File"`, …)
	 *  * `*array` + `items` on object-array wrappers
	 *
	 * Any key starting with `*` is meta only and is stripped before bin encode.
	 * Type aliases must be registered via {@link Stream.register} before use.
	 */
	public class Json : GLib.Object
	{
		/**
		 * Encode one JSON object onto {@link ctx}.
		 *
		 * @param ctx bin stream to write to
		 * @param src JSON object with a {@code *type} meta member
		 */
		public void write (
			Stream ctx,
			global::Json.Object src
		) throws GLib.Error
		{
			if (!src.has_member ("*type")) {
				throw new StreamError.PROTOCOL (
					"JSON object missing '*type'"
				);
			}
			var alias = src.get_string_member ("*type");
			if (alias_to_gtype == null || !alias_to_gtype.has_key (alias)) {
				throw new StreamError.REGISTRATION (
					"unregistered JSON type alias '%s'",
					alias
				);
			}
			ctx.write_gtype (alias_to_gtype.get (alias));
			this.write_object (ctx, src);
		}

		/**
		 * Decode one root bin object from {@link ctx} into a JSON node.
		 *
		 * @param ctx bin stream to read from
		 * @return JSON object node with {@code *type} meta member
		 */
		public global::Json.Node parse (Stream ctx) throws GLib.Error
		{
			var b = ctx.in_stream.read_byte ();
			if (b == 0xFF) {
				ctx.read_reg_gtype ();
				b = ctx.in_stream.read_byte ();
			}
			if ((b & 0x80) != 0) {
				throw new StreamError.PROTOCOL (
					"root parse does not accept object arrays"
				);
			}
			if (b != (uint8) GLib.Type.OBJECT) {
				throw new StreamError.PROTOCOL (
					"expected object type byte, got 0x%02X",
					b
				);
			}
			var gtype = ctx.read_gtype ();
			if (gtype_to_alias == null || !gtype_to_alias.has_key (gtype)) {
				throw new StreamError.REGISTRATION (
					"unregistered JSON type for '%s'",
					gtype.name ()
				);
			}
			return this.read_object (ctx, gtype_to_alias.get (gtype));
		}

		/**
		 * Write one object body (properties + {@link Stream.TOKEN_END}).
		 *
		 * @param ctx active bin session
		 * @param src JSON property members for this object
		 */
		public void write_object (
			Stream ctx,
			global::Json.Object src
		) throws GLib.Error
		{
			foreach (var name in src.get_members ()) {
				if (name.has_prefix ("*")) {
					continue;
				}
				this.write_member (ctx, name, src.get_member (name));
			}
			ctx.out_stream.put_uint16 (Stream.TOKEN_END);
		}

		/**
		 * Read one object body into a JSON object node.
		 *
		 * @param ctx active bin session
		 * @param alias wire type alias for {@code *type}
		 */
		public global::Json.Node read_object (
			Stream ctx,
			string alias
		) throws GLib.Error
		{
			var root = new global::Json.Object ();
			root.set_string_member ("*type", alias);

			var prop_name = "";
			var t = (uint16) 0;
			while ((t = ctx.read_tag (out prop_name)) != Stream.TOKEN_END) {
				var b = ctx.in_stream.read_byte ();
				if (b == 0xFF) {
					ctx.read_reg_gtype ();
					b = ctx.in_stream.read_byte ();
				}
				root.set_member (
					prop_name,
					this.read_member (ctx, b)
				);
			}

			var out_node = new global::Json.Node (global::Json.NodeType.OBJECT);
			out_node.set_object (root);
			return out_node;
		}

		public void write_member (
			Stream ctx,
			string name,
			global::Json.Node node
		) throws GLib.Error
		{
			if (node.get_node_type () == global::Json.NodeType.OBJECT) {
				var child_obj = node.get_object ();
				if (child_obj.has_member ("*array")) {
					if (!child_obj.has_member ("items")) {
						throw new StreamError.PROTOCOL (
							"member '%s' object array wrapper missing 'items'",
							name
						);
					}
					var element_alias = child_obj.get_string_member ("*array");
					if (alias_to_gtype == null
						|| !alias_to_gtype.has_key (element_alias)) {
						throw new StreamError.REGISTRATION (
							"unregistered JSON type alias '%s'",
							element_alias
						);
					}
					var items = child_obj.get_member ("items").get_array ();
					ctx.write_tag (name);
					ctx.write_gtype (
						alias_to_gtype.get (element_alias),
						(uint8) GLib.Type.OBJECT | 0x80
					);
					var count = items.get_length ();
					if (count < 128) {
						ctx.out_stream.put_byte ((uint8) count);
					} else {
						ctx.out_stream.put_byte (
							(uint8) (0x80 | ((count >> 8) & 0x7F))
						);
						ctx.out_stream.put_byte (
							(uint8) (count & 0xFF)
						);
					}
					for (var i = 0u; i < count; i++) {
						var elem = items.get_object_element (i);
						if (!elem.has_member ("*type")) {
							elem.set_string_member ("*type", element_alias);
						}
						this.write_object (ctx, elem);
					}
					return;
				}
				if (!child_obj.has_member ("*type")) {
					throw new StreamError.PROTOCOL (
						"member '%s' nested object missing '*type'",
						name
					);
				}
				var child_alias = child_obj.get_string_member ("*type");
				if (alias_to_gtype == null
					|| !alias_to_gtype.has_key (child_alias)) {
					throw new StreamError.REGISTRATION (
						"unregistered JSON type alias '%s'",
						child_alias
					);
				}
				ctx.write_tag (name);
				ctx.write_gtype (alias_to_gtype.get (child_alias));
				this.write_object (ctx, child_obj);
				return;
			}

			if (node.get_node_type () == global::Json.NodeType.ARRAY) {
				var items = node.get_array ();
				if (items.get_length () == 0) {
					return;
				}
				var first_node = items.get_element (0);
				if (first_node.get_node_type () == global::Json.NodeType.VALUE
					&& first_node.get_value_type () == GLib.Type.STRING) {
					var count = items.get_length ();
					ctx.write_tag (name);
					ctx.out_stream.put_byte (
						(uint8) GLib.Type.STRING | 0x80
					);
					if (count < 128) {
						ctx.out_stream.put_byte ((uint8) count);
					} else {
						ctx.out_stream.put_byte (
							(uint8) (0x80 | ((count >> 8) & 0x7F))
						);
						ctx.out_stream.put_byte (
							(uint8) (count & 0xFF)
						);
					}
					for (var i = 0u; i < count; i++) {
						var elem = items.get_string_element (i) != null
							? items.get_string_element (i)
							: "";
						if (elem.length < 128) {
							ctx.out_stream.put_byte ((uint8) elem.length);
						} else {
							ctx.out_stream.put_byte (
								(uint8) (0x80 | ((elem.length >> 8) & 0x7F))
							);
							ctx.out_stream.put_byte (
								(uint8) (elem.length & 0xFF)
							);
						}
						size_t elem_written;
						ctx.out_stream.write_all (
							((uint8[]) elem)[0:elem.length],
							out elem_written
						);
					}
					return;
				}
				var first = items.get_object_element (0);
				if (!first.has_member ("*type")) {
					throw new StreamError.PROTOCOL (
						"member '%s' object array element missing '*type'",
						name
					);
				}
				var element_alias = first.get_string_member ("*type");
				if (alias_to_gtype == null
					|| !alias_to_gtype.has_key (element_alias)) {
					throw new StreamError.REGISTRATION (
						"unregistered JSON type alias '%s'",
						element_alias
					);
				}
				ctx.write_tag (name);
				ctx.write_gtype (
					alias_to_gtype.get (element_alias),
					(uint8) GLib.Type.OBJECT | 0x80
				);
				var obj_count = items.get_length ();
				if (obj_count < 128) {
					ctx.out_stream.put_byte ((uint8) obj_count);
				} else {
					ctx.out_stream.put_byte (
						(uint8) (0x80 | ((obj_count >> 8) & 0x7F))
					);
					ctx.out_stream.put_byte (
						(uint8) (obj_count & 0xFF)
					);
				}
				for (var i = 0u; i < obj_count; i++) {
					var elem = items.get_object_element (i);
					if (!elem.has_member ("*type")) {
						elem.set_string_member ("*type", element_alias);
					}
					this.write_object (ctx, elem);
				}
				return;
			}

			if (node.get_node_type () != global::Json.NodeType.VALUE) {
				throw new StreamError.PROTOCOL (
					"member '%s' expected JSON value",
					name
				);
			}

			switch (node.get_value_type ()) {
				case GLib.Type.STRING:
					var s = node.get_string () != null ? node.get_string () : "";
					ctx.write_tag (name);
					if (s.length > 32767) {
						ctx.out_stream.put_byte ((uint8) GLib.Type.BOXED);
						ctx.out_stream.put_uint32 ((uint32) s.length);
						size_t written;
						ctx.out_stream.write_all (
							((uint8[]) s)[0:s.length],
							out written
						);
						return;
					}
					ctx.out_stream.put_byte ((uint8) GLib.Type.STRING);
					if (s.length < 128) {
						ctx.out_stream.put_byte ((uint8) s.length);
					} else {
						ctx.out_stream.put_byte (
							(uint8) (0x80 | ((s.length >> 8) & 0x7F))
						);
						ctx.out_stream.put_byte (
							(uint8) (s.length & 0xFF)
						);
					}
					size_t written;
					ctx.out_stream.write_all (
						((uint8[]) s)[0:s.length],
						out written
					);
					return;

				case GLib.Type.BOOLEAN:
					ctx.write_tag (name);
					ctx.out_stream.put_byte ((uint8) GLib.Type.BOOLEAN);
					ctx.out_stream.put_byte (node.get_boolean () ? 1 : 0);
					return;

				case GLib.Type.INT:
				case GLib.Type.INT64:
				case GLib.Type.DOUBLE:
					var i64 = (int64) node.get_int ();
					ctx.write_tag (name);
					if (i64 >= int.MIN && i64 <= int.MAX) {
						ctx.out_stream.put_byte ((uint8) GLib.Type.INT);
						var iv = (int) i64;
						if (iv >= -128 && iv <= 127) {
							ctx.out_stream.put_byte (1);
							ctx.out_stream.put_byte ((uint8) (int8) iv);
							return;
						}
						ctx.out_stream.put_byte (8);
						ctx.out_stream.put_int64 (iv);
						return;
					}
					ctx.out_stream.put_byte ((uint8) GLib.Type.INT64);
					if (i64 >= -128 && i64 <= 127) {
						ctx.out_stream.put_byte (1);
						ctx.out_stream.put_byte ((uint8) (int8) i64);
						return;
					}
					ctx.out_stream.put_byte (8);
					ctx.out_stream.put_int64 (i64);
					return;

				default:
					break;
			}

			throw new StreamError.PROTOCOL (
				"unsupported JSON value type '%s' on member '%s'",
				node.get_value_type ().name (),
				name
			);
		}

		public global::Json.Node read_member (
			Stream ctx,
			uint8 type_byte
		) throws GLib.Error
		{
			if ((type_byte & 0x7F) == GLib.Type.OBJECT) {
				if ((type_byte & 0x80) != 0) {
					var element_gtype = ctx.read_gtype ();
					if (gtype_to_alias == null
						|| !gtype_to_alias.has_key (element_gtype)) {
						throw new StreamError.REGISTRATION (
							"unregistered JSON type for '%s'",
							element_gtype.name ()
						);
					}
					var element_alias = gtype_to_alias.get (element_gtype);
					var count = (uint) ctx.in_stream.read_byte ();
					if ((count & 0x80) != 0) {
						count = ((count & 0x7F) << 8)
							| ctx.in_stream.read_byte ();
					}
					var items = new global::Json.Array ();
					for (var i = 0u; i < count; i++) {
						items.add_object_element (
							this.read_object (
								ctx,
								element_alias
							).get_object ()
						);
					}
					var wrapper = new global::Json.Object ();
					wrapper.set_string_member ("*array", element_alias);
					wrapper.set_array_member ("items", items);
					var out_node = new global::Json.Node (
						global::Json.NodeType.OBJECT
					);
					out_node.set_object (wrapper);
					return out_node;
				}
				var nested_gtype = ctx.read_gtype ();
				if (gtype_to_alias == null
					|| !gtype_to_alias.has_key (nested_gtype)) {
					throw new StreamError.REGISTRATION (
						"unregistered JSON type for '%s'",
						nested_gtype.name ()
					);
				}
				return this.read_object (
					ctx,
					gtype_to_alias.get (nested_gtype)
				);
			}

			var member = new global::Json.Node (global::Json.NodeType.VALUE);
			var width = (uint8) 0;

			switch ((GLib.Type) (type_byte & 0x7F)) {
				case GLib.Type.STRING:
					if ((type_byte & 0x80) != 0) {
						var count = (uint) ctx.in_stream.read_byte ();
						if ((count & 0x80) != 0) {
							count = ((count & 0x7F) << 8)
								| ctx.in_stream.read_byte ();
						}
						var json_arr = new global::Json.Array ();
						for (var i = 0u; i < count; i++) {
							var elem_len = (uint) ctx.in_stream.read_byte ();
							if ((elem_len & 0x80) != 0) {
								elem_len = ((elem_len & 0x7F) << 8)
									| ctx.in_stream.read_byte ();
							}
							var buf = new uint8[elem_len + 1];
							size_t read_bytes;
							ctx.in_stream.read_all (
								buf[0:elem_len],
								out read_bytes
							);
							buf[elem_len] = 0;
							json_arr.add_string_element ((string) buf);
						}
						var arr_node = new global::Json.Node (
							global::Json.NodeType.ARRAY
						);
						arr_node.set_array (json_arr);
						return arr_node;
					}
					var str_len = (uint) ctx.in_stream.read_byte ();
					if ((str_len & 0x80) != 0) {
						str_len = ((str_len & 0x7F) << 8)
							| ctx.in_stream.read_byte ();
					}
					var str_buf = new uint8[str_len + 1];
					size_t str_read;
					ctx.in_stream.read_all (
						str_buf[0:str_len],
						out str_read
					);
					str_buf[str_len] = 0;
					member.set_string ((string) str_buf);
					return member;

				case GLib.Type.BOXED:
					var blob_len = ctx.in_stream.read_uint32 ();
					var blob_buf = new uint8[blob_len + 1];
					size_t blob_read;
					ctx.in_stream.read_all (
						blob_buf[0:blob_len],
						out blob_read
					);
					blob_buf[blob_len] = 0;
					member.set_string ((string) blob_buf);
					return member;

				case GLib.Type.BOOLEAN:
					member.set_boolean (ctx.in_stream.read_byte () == 1);
					return member;

				case GLib.Type.ENUM:
					width = ctx.in_stream.read_byte ();
					if (width == 1) {
						member.set_int (
							(int64) (int8) ctx.in_stream.read_byte ()
						);
						return member;
					}
					if (width != 8) {
						throw new StreamError.PROTOCOL (
							"invalid enum integer width %u",
							width
						);
					}
					member.set_int (ctx.in_stream.read_int64 ());
					return member;

				case GLib.Type.INT:
				case GLib.Type.INT64:
					width = ctx.in_stream.read_byte ();
					if (width == 1) {
						member.set_int (
							(int64) (int8) ctx.in_stream.read_byte ()
						);
						return member;
					}
					if (width != 8) {
						throw new StreamError.PROTOCOL (
							"invalid signed integer width %u",
							width
						);
					}
					member.set_int (ctx.in_stream.read_int64 ());
					return member;

				case GLib.Type.UINT:
				case GLib.Type.UINT64:
					width = ctx.in_stream.read_byte ();
					if (width == 1) {
						member.set_int ((int64) ctx.in_stream.read_byte ());
						return member;
					}
					if (width != 8) {
						throw new StreamError.PROTOCOL (
							"invalid unsigned integer width %u",
							width
						);
					}
					member.set_int ((int64) ctx.in_stream.read_uint64 ());
					return member;

				default:
					break;
			}

			throw new StreamError.PROTOCOL (
				"unsupported wire type 0x%02X",
				type_byte & 0x7F
			);
		}
	}
}
