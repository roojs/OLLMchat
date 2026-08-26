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
	 * JSON ↔ bin bridge for tests, HTTP tooling, and debugging.
	 *
	 * Encodes json-glib trees onto a {@link Stream} and decodes wire bytes
	 * back into JSON nodes. Property layout follows the JSON shape and wire
	 * type bytes — not a live GObject schema. Objects need meta key ''*type''
	 * unless {@link Mode.AUTO}. Keys starting with ''*'' are meta only and
	 * stripped before encode. Register aliases with {@link register} first.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Bin.register("Pair", typeof(Pair));
	 * var json = new OLLMrpc.Bin.Json();
	 * var parser = new global::Json.Parser();
	 * parser.load_from_data(
	 *     "{\"*type\":\"Pair\",\"name\":\"a\",\"count\":1}", -1);
	 * var mem = new GLib.MemoryOutputStream.resizable();
	 * var bin = new OLLMrpc.Bin.Stream(
	 *     null, new GLib.DataOutputStream(mem));
	 * json.json_to_bin(parser.get_root().get_object(), bin);
	 * }}}
	 *
	 * == GObject to JSON ==
	 *
	 * {{{
	 * var node = json.from_gobject(pair);
	 * }}}
	 *
	 * Prefer {@link from_gobject} over hand-rolled memory pipes.
	 *
	 * @see Stream
	 * @see Mode
	 */
	public class Json : GLib.Object
	{
		public Mode mode { get; construct; default = Mode.EXPLICIT; }

		public Json(Mode mode = Mode.EXPLICIT)
		{
			Object(mode: mode);
			if (alias_to_gtype == null) {
				alias_to_gtype = new Gee.HashMap<string, GLib.Type>();
				gtype_to_alias = new Gee.HashMap<GLib.Type, string>();
			}
			if (!gtype_to_alias.has_key(typeof(GLib.Object))) {
				alias_to_gtype.set("GLib.Object", typeof(GLib.Object));
				gtype_to_alias.set(typeof(GLib.Object), "GLib.Object");
			}
		}

		/**
		 * Encode one JSON object as bin bytes on {@link bin}.
		 *
		 * @param src JSON object tree
		 * @param bin bin stream to write into
		 * @param type root object {@link GLib.Type} when {@link mode} includes
		 *     {@link Mode.AUTO} and {@link src} has no ''*type'' member;
		 *     default {@link GLib.Type.INVALID}
		 */
		public void json_to_bin(
			global::Json.Object src,
			Stream bin,
			GLib.Type type = GLib.Type.INVALID
		) throws GLib.Error
		{
			if (!src.has_member("*type") && ((this.mode & Mode.AUTO) == 0 || type == GLib.Type.INVALID)) {
				throw new StreamError.PROTOCOL(
					"JSON object missing '*type'"
				);
			}
			if (!src.has_member("*type") && !gtype_to_alias.has_key(type)) {
				throw new StreamError.REGISTRATION(
					"unregistered JSON type for '%s'",
					type.name()
				);
			}
			if (!src.has_member("*type")) {
				bin.write_gtype(type);
				this.json_to_bin_object(src, bin);
				return;
			}

			var alias = src.get_string_member("*type");
			if (!alias_to_gtype.has_key(alias)) {
				throw new StreamError.REGISTRATION(
					"unregistered JSON type alias '%s'",
					alias
				);
			}
			bin.write_gtype(alias_to_gtype.get(alias));
			this.json_to_bin_object(src, bin);
		}

		/**
		 * Decode bin bytes from {@link bin} into a JSON object tree.
		 *
		 * @param bin bin stream to read from
		 * @return JSON object node; ''*type'' meta omitted when
		 *     {@link mode} includes {@link Mode.AUTO}
		 */
		public global::Json.Node bin_to_json(Stream bin) throws GLib.Error
		{
			var b = bin.in_stream.read_byte();
			if (b == 0xFF) {
				bin.read_reg_gtype();
				b = bin.in_stream.read_byte();
			}
			if ((b & 0x80) != 0) {
				throw new StreamError.PROTOCOL(
					"root parse does not accept object arrays"
				);
			}
			if (b != (uint8) GLib.Type.OBJECT) {
				throw new StreamError.PROTOCOL(
					"expected object type byte, got 0x%02X",
					b
				);
			}
			var gtype = bin.read_gtype();
			if (gtype_to_alias == null || !gtype_to_alias.has_key(gtype)) {
				throw new StreamError.REGISTRATION(
					"unregistered JSON type for '%s'",
					gtype.name()
				);
			}
			return this.bin_to_json_object(bin, gtype_to_alias.get(gtype));
		}

		public void json_to_bin_object(
			global::Json.Object src,
			Stream bin
		) throws GLib.Error
		{
			foreach (var name in src.get_members()) {
				if (name.has_prefix("*")) {
					continue;
				}
				this.json_member_to_bin(
					name,
					src.get_member(name),
					bin
				);
			}
			bin.out_stream.put_uint16(Stream.TOKEN_END);
		}

		/**
		 * Decode one object body into a JSON object node.
		 *
		 * @param bin active bin session to read from
		 * @param alias wire type alias for ''*type'' (EXPLICIT mode only)
		 */
		public global::Json.Node bin_to_json_object(
			Stream bin,
			string alias
		) throws GLib.Error
		{
			var root = new global::Json.Object();
			if ((this.mode & Mode.AUTO) == 0) {
				root.set_string_member("*type", alias);
			}

			var prop_name = "";
			var t = (uint16) 0;
			while ((t = bin.read_tag(out prop_name)) != Stream.TOKEN_END) {
				var b = bin.in_stream.read_byte();
				if (b == 0xFF) {
					bin.read_reg_gtype();
					b = bin.in_stream.read_byte();
				}
				root.set_member(prop_name, this.bin_member_to_json(bin, b));
			}

			var out_node = new global::Json.Node(global::Json.NodeType.OBJECT);
			out_node.set_object(root);
			return out_node;
		}

		public void json_member_to_bin(
			string name,
			global::Json.Node node,
			Stream bin
		) throws GLib.Error
		{
			if (node.get_node_type() == global::Json.NodeType.NULL) {
				return;
			}
			var tag_name = name;
			if ((this.mode & Mode.AUTO) != 0) {
				if (tag_name.has_prefix("_")) {
					tag_name = "underscore_" + tag_name.substring(1);
				}
				tag_name = tag_name.replace("_", "-");
			}
			if (node.get_node_type() == global::Json.NodeType.OBJECT) {
				var child_obj = node.get_object();
				if (child_obj.has_member("*array")) {
					if (!child_obj.has_member("items")) {
						throw new StreamError.PROTOCOL(
							"member '%s' object array wrapper missing 'items'",
							name
						);
					}
					var element_alias = child_obj.get_string_member("*array");
					if (alias_to_gtype == null || !alias_to_gtype.has_key(element_alias)) {
						throw new StreamError.REGISTRATION(
							"unregistered JSON type alias '%s'",
							element_alias
						);
					}
					var items = child_obj.get_member("items").get_array();
					bin.write_tag(tag_name);
					bin.write_gtype(alias_to_gtype.get(element_alias), (uint8) GLib.Type.OBJECT | 0x80);
					var count = items.get_length();
					if (count < 128) {
						bin.out_stream.put_byte((uint8) count);
					} else {
						bin.out_stream.put_byte((uint8) (0x80 | ((count >> 8) & 0x7F)));
						bin.out_stream.put_byte((uint8) (count & 0xFF));
					}
					for (var i = 0u; i < count; i++) {
						var elem = items.get_object_element(i);
						if (!elem.has_member("*type")) {
							elem.set_string_member("*type", element_alias);
						}
						this.json_to_bin_object(elem, bin);
					}
					return;
				}
				if (!child_obj.has_member("*type")) {
					if ((this.mode & Mode.AUTO) == 0) {
						throw new StreamError.PROTOCOL(
							"member '%s' nested object missing '*type'",
							name
						);
					}
					bin.write_tag(tag_name);
					bin.write_gtype(typeof(GLib.Object));
					this.json_to_bin_object(child_obj, bin);
					return;
				}
				var child_alias = child_obj.get_string_member("*type");
				if (alias_to_gtype == null || !alias_to_gtype.has_key(child_alias)) {
					throw new StreamError.REGISTRATION(
						"unregistered JSON type alias '%s'",
						child_alias
					);
				}
				bin.write_tag(tag_name);
				bin.write_gtype(alias_to_gtype.get(child_alias));
				this.json_to_bin_object(child_obj, bin);
				return;
			}

			if (node.get_node_type() == global::Json.NodeType.ARRAY) {
				var items = node.get_array();
				if (items.get_length() == 0) {
					return;
				}
				if (tag_name == "args") {
					this.json_array_to_bin(tag_name, items, bin, name);
					return;
				}
				var first_node = items.get_element(0);
				if (first_node.get_node_type() == global::Json.NodeType.VALUE && first_node.get_value_type() == GLib.Type.STRING) {
					string[] arr = {};
					for (var i = 0u; i < items.get_length(); i++) {
						var elem = items.get_string_element(i);
						if (elem == null) {
							arr += "";
							continue;
						}
						arr += elem;
					}
					bin.write_tag(tag_name);
					var val = GLib.Value(typeof(string[]));
					val = arr;
					StreamValue.write(bin, val);
					return;
				}
				var first = items.get_object_element(0);
				if (!first.has_member("*type")) {
					if ((this.mode & Mode.AUTO) == 0) {
						throw new StreamError.PROTOCOL(
							"member '%s' object array element missing '*type'",
							name
						);
					}
					bin.write_tag(tag_name);
					bin.write_gtype(typeof(GLib.Object), (uint8) GLib.Type.OBJECT | 0x80);
					var obj_count = items.get_length();
					if (obj_count < 128) {
						bin.out_stream.put_byte((uint8) obj_count);
					} else {
						bin.out_stream.put_byte((uint8) (0x80 | ((obj_count >> 8) & 0x7F)));
						bin.out_stream.put_byte((uint8) (obj_count & 0xFF));
					}
					for (var i = 0u; i < obj_count; i++) {
						this.json_to_bin_object(items.get_object_element(i), bin);
					}
					return;
				}
				var element_alias = first.get_string_member("*type");
				if (alias_to_gtype == null || !alias_to_gtype.has_key(element_alias)) {
					throw new StreamError.REGISTRATION(
						"unregistered JSON type alias '%s'",
						element_alias
					);
				}
				bin.write_tag(tag_name);
				bin.write_gtype(alias_to_gtype.get(element_alias), (uint8) GLib.Type.OBJECT | 0x80);
				var obj_count = items.get_length();
				if (obj_count < 128) {
					bin.out_stream.put_byte((uint8) obj_count);
				} else {
					bin.out_stream.put_byte((uint8) (0x80 | ((obj_count >> 8) & 0x7F)));
					bin.out_stream.put_byte((uint8) (obj_count & 0xFF));
				}
				for (var i = 0u; i < obj_count; i++) {
					var elem = items.get_object_element(i);
					if (!elem.has_member("*type")) {
						elem.set_string_member("*type", element_alias);
					}
					this.json_to_bin_object(elem, bin);
				}
				return;
			}

			if (node.get_node_type() != global::Json.NodeType.VALUE) {
				throw new StreamError.PROTOCOL("member '%s' expected JSON value", name);
			}

			switch (node.get_value_type()) {
				case GLib.Type.STRING:
					bin.write_tag(tag_name);
					if (tag_name == "method") {
						bin.write_name_ref(
							node.get_string() != null ? node.get_string() : ""
						);
						return;
					}
					var str_val = GLib.Value(typeof(string));
					str_val.set_string(node.get_string() != null ? node.get_string() : "");
					StreamValue.write(bin, str_val);
					return;

				case GLib.Type.BOOLEAN:
					bin.write_tag(tag_name);
					var bool_val = GLib.Value(typeof(bool));
					bool_val.set_boolean(node.get_boolean());
					StreamValue.write(bin, bool_val);
					return;

				case GLib.Type.INT:
				case GLib.Type.INT64:
				case GLib.Type.DOUBLE:
					var i64 = (int64) node.get_int();
					bin.write_tag(tag_name);
					if (i64 >= int.MIN && i64 <= int.MAX) {
						var int_val = GLib.Value(typeof(int));
						int_val.set_int((int) i64);
						StreamValue.write(bin, int_val);
						return;
					}
					var wide_val = GLib.Value(typeof(int64));
					wide_val.set_int64(i64);
					StreamValue.write(bin, wide_val);
					return;

				default:
					break;
			}

			throw new StreamError.PROTOCOL("unsupported JSON value type '%s' on member '%s'",
				node.get_value_type().name(), name);
		}

		/**
		 * Write a JSON array as wire ''ANY[]'' (heterogeneous args).
		 *
		 * Each element is a scalar or nested string array, encoded via
		 * {@link StreamValue.write} after the ''INVALID|0x80'' header.
		 *
		 * @param tag_name wire property name (e.g. ''args'')
		 * @param items JSON array body
		 * @param bin destination stream
		 * @param name original member name for error text
		 */
		void json_array_to_bin(
			string tag_name,
			global::Json.Array items,
			Stream bin,
			string name
		) throws GLib.Error
		{
			bin.write_tag(tag_name);
			bin.out_stream.put_byte((uint8) GLib.Type.INVALID | 0x80);
			var any_count = items.get_length();
			if (any_count < 128) {
				bin.out_stream.put_byte((uint8) any_count);
			} else {
				bin.out_stream.put_byte(
					(uint8) (0x80 | ((any_count >> 8) & 0x7F)));
				bin.out_stream.put_byte((uint8) (any_count & 0xFF));
			}
			for (var i = 0u; i < any_count; i++) {
				var elem = items.get_element(i);
				if (elem.get_node_type() == global::Json.NodeType.ARRAY) {
					string[] arr = {};
					var nested = elem.get_array();
					for (var j = 0u; j < nested.get_length(); j++) {
						var s = nested.get_string_element(j);
						arr += s != null ? s : "";
					}
					var as_val = GLib.Value(typeof(string[]));
					as_val.set_boxed(arr);
					StreamValue.write(bin, as_val);
					continue;
				}
				if (elem.get_node_type() != global::Json.NodeType.VALUE) {
					throw new StreamError.PROTOCOL(
						"member '%s' ANY[] element unsupported",
						name
					);
				}
				switch (elem.get_value_type()) {
					case GLib.Type.STRING:
						var str_val = GLib.Value(typeof(string));
						str_val.set_string(
							elem.get_string() != null ? elem.get_string() : ""
						);
						StreamValue.write(bin, str_val);
						break;
					case GLib.Type.BOOLEAN:
						var bool_val = GLib.Value(typeof(bool));
						bool_val.set_boolean(elem.get_boolean());
						StreamValue.write(bin, bool_val);
						break;
					case GLib.Type.INT:
					case GLib.Type.INT64:
					case GLib.Type.DOUBLE:
						var i64 = (int64) elem.get_int();
						if (i64 >= int.MIN && i64 <= int.MAX) {
							var int_val = GLib.Value(typeof(int));
							int_val.set_int((int) i64);
							StreamValue.write(bin, int_val);
							break;
						}
						var wide_val = GLib.Value(typeof(int64));
						wide_val.set_int64(i64);
						StreamValue.write(bin, wide_val);
						break;
					default:
						throw new StreamError.PROTOCOL(
							"unsupported JSON value type '%s' in args",
							elem.get_value_type().name()
						);
				}
			}
		}

		public global::Json.Node bin_member_to_json(
			Stream bin,
			uint8 type_byte
		) throws GLib.Error
		{
			if (type_byte == Stream.TYPE_NAME_REF
				|| type_byte == Stream.TYPE_NAME_REF_REG) {
				var member = new global::Json.Node(global::Json.NodeType.VALUE);
				member.set_string(bin.read_name_ref(type_byte));
				return member;
			}
			if ((type_byte & 0x7F) == GLib.Type.INVALID && (type_byte & 0x80) != 0) {
				var n = bin.in_stream.read_byte();
				var count = n & 0x7F;
				if ((n & 0x80) != 0) {
					count = (count << 8) | bin.in_stream.read_byte();
				}
				var items = new global::Json.Array();
				for (var i = 0; i < count; i++) {
					var elem = bin.in_stream.read_byte();
					items.add_element(this.bin_member_to_json(bin, elem));
				}
				var out_node = new global::Json.Node(global::Json.NodeType.ARRAY);
				out_node.set_array(items);
				return out_node;
			}
			if ((type_byte & 0x7F) == GLib.Type.OBJECT) {
				if ((type_byte & 0x80) != 0) {
					var element_gtype = bin.read_gtype();
					if (gtype_to_alias == null || !gtype_to_alias.has_key(element_gtype)) {
						throw new StreamError.REGISTRATION(
							"unregistered JSON type for '%s'",
							element_gtype.name()
						);
					}
					var element_alias = gtype_to_alias.get(element_gtype);
					var count = (uint) bin.in_stream.read_byte();
					if ((count & 0x80) != 0) {
						count = ((count & 0x7F) << 8) | bin.in_stream.read_byte();
					}
					var items = new global::Json.Array();
					for (var i = 0u; i < count; i++) {
						items.add_object_element(this.bin_to_json_object(bin, element_alias).get_object());
					}
					var out_node = new global::Json.Node(global::Json.NodeType.ARRAY);
					out_node.set_array(items);
					return out_node;
				}
				var nested_gtype = bin.read_gtype();
				if (gtype_to_alias == null || !gtype_to_alias.has_key(nested_gtype)) {
					throw new StreamError.REGISTRATION(
						"unregistered JSON type for '%s'",
						nested_gtype.name()
					);
				}
				return this.bin_to_json_object(bin, gtype_to_alias.get(nested_gtype));
			}

			var val = StreamValue.read(bin, type_byte);
			if (val.type() == typeof(string[])) {
				var arr = (string[]) val;
				var json_arr = new global::Json.Array();
				foreach (var s in arr) {
					json_arr.add_string_element(s);
				}
				var arr_node = new global::Json.Node(global::Json.NodeType.ARRAY);
				arr_node.set_array(json_arr);
				return arr_node;
			}

			var member = new global::Json.Node(global::Json.NodeType.VALUE);
			switch (val.type()) {
				case GLib.Type.STRING:
					member.set_string(val.get_string());
					return member;

				case GLib.Type.BOOLEAN:
					member.set_boolean(val.get_boolean());
					return member;

				case GLib.Type.INT:
					member.set_int(val.get_int());
					return member;

				case GLib.Type.INT64:
					member.set_int(val.get_int64());
					return member;

				case GLib.Type.UINT:
					member.set_int((int64) val.get_uint());
					return member;

				case GLib.Type.UINT64:
					member.set_int((int64) val.get_uint64());
					return member;

				default:
					break;
			}

			throw new StreamError.PROTOCOL("unsupported wire type 0x%02X", type_byte & 0x7F);
		}

		/**
		 * Encode {@link Serializable} to memory, then decode to a JSON tree.
		 *
		 * == Example ==
		 *
		 * {{{
		 * var json = new OLLMrpc.Bin.Json();
		 * var node = json.from_gobject(pair);
		 * stdout.printf("%s\n",
		 *     global::Json.to_string(node, true));
		 * }}}
		 *
		 * @param src object to encode
		 * @return JSON object tree for {@link src}
		 */
		public global::Json.Node from_gobject(
			Serializable src
		) throws GLib.Error
		{
			var mem = new GLib.MemoryOutputStream.resizable();
			var encode_out = new GLib.DataOutputStream(mem);
			var encode_bin = new Stream(null, encode_out);
			encode_bin.write(src);
			encode_out.close();

			var read_bin = new Stream(
				new GLib.DataInputStream(
					new GLib.MemoryInputStream.from_bytes(mem.steal_as_bytes())
				),
				null
			);
			return this.bin_to_json(read_bin);
		}
	}
}
