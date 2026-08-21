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
	 * Encode or decode one {@link GLib.Value} on a {@link Stream}.
	 *
	 * Type byte + payload, no property tag. Keeps {@link Stream} small.
	 * {@link GLib.Type.OBJECT} uses {@link Stream.write_gtype} and
	 * {@link Stream.parse_object}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * StreamValue.write(ctx, val);
	 * var got = StreamValue.read(ctx, type_byte);
	 * }}}
	 */
	public class StreamValue : GLib.Object
	{
		/**
		 * Encode one {@link GLib.Value} (type byte + payload, no property tag).
		 *
		 * {@link GLib.Type.OBJECT} uses {@link Stream.write_gtype} and
		 * {@link Serializable.bin_write}, so ''ctx'' is the session.
		 *
		 * @param ctx active bin session
		 * @param val value to write
		 */
		public static void write(Stream ctx, GLib.Value val) throws GLib.Error
		{
			switch (val.type()) {
				case GLib.Type.STRING:
					var s = val.get_string() != null ? val.get_string() : "";
					if (s.length > 32767) {
						ctx.out_stream.put_byte((uint8) GLib.Type.BOXED);
						ctx.out_stream.put_uint32((uint32) s.length);
						size_t written;
						ctx.out_stream.write_all(((uint8[]) s)[0:s.length], out written);
						return;
					}
					ctx.out_stream.put_byte((uint8) GLib.Type.STRING);
					if (s.length < 128) {
						ctx.out_stream.put_byte((uint8) s.length);
						size_t written;
						ctx.out_stream.write_all(((uint8[]) s)[0:s.length], out written);
						return;
					}
					ctx.out_stream.put_byte((uint8) (0x80 | ((s.length >> 8) & 0x7F)));
					ctx.out_stream.put_byte((uint8) (s.length & 0xFF));
					size_t written;
					ctx.out_stream.write_all(((uint8[]) s)[0:s.length], out written);
					return;

				case GLib.Type.BOOLEAN:
					ctx.out_stream.put_byte((uint8) GLib.Type.BOOLEAN);
					ctx.out_stream.put_byte(val.get_boolean() ? 1 : 0);
					return;

				case GLib.Type.CHAR:
					ctx.out_stream.put_byte((uint8) GLib.Type.CHAR);
					ctx.out_stream.put_byte((uint8) val.get_schar());
					return;

				case GLib.Type.UCHAR:
					ctx.out_stream.put_byte((uint8) GLib.Type.UCHAR);
					ctx.out_stream.put_byte((uint8) val.get_uchar());
					return;

				case GLib.Type.INT:
					ctx.out_stream.put_byte((uint8) GLib.Type.INT);
					if (val.get_int() >= -128 && val.get_int() <= 127) {
						ctx.out_stream.put_byte(1);
						ctx.out_stream.put_byte((uint8) (int8) val.get_int());
						return;
					}
					ctx.out_stream.put_byte(8);
					ctx.out_stream.put_int64(val.get_int());
					return;

				case GLib.Type.INT64:
					ctx.out_stream.put_byte((uint8) GLib.Type.INT64);
					if (val.get_int64() >= -128 && val.get_int64() <= 127) {
						ctx.out_stream.put_byte(1);
						ctx.out_stream.put_byte((uint8) (int8) val.get_int64());
						return;
					}
					ctx.out_stream.put_byte(8);
					ctx.out_stream.put_int64(val.get_int64());
					return;

				case GLib.Type.UINT:
					ctx.out_stream.put_byte((uint8) GLib.Type.UINT);
					if (val.get_uint() <= 255) {
						ctx.out_stream.put_byte(1);
						ctx.out_stream.put_byte((uint8) val.get_uint());
						return;
					}
					ctx.out_stream.put_byte(8);
					ctx.out_stream.put_uint64(val.get_uint());
					return;

				case GLib.Type.UINT64:
					ctx.out_stream.put_byte((uint8) GLib.Type.UINT64);
					if (val.get_uint64() <= 255) {
						ctx.out_stream.put_byte(1);
						ctx.out_stream.put_byte((uint8) val.get_uint64());
						return;
					}
					ctx.out_stream.put_byte(8);
					ctx.out_stream.put_uint64(val.get_uint64());
					return;
			}

			if (val.type() == typeof(string[])) {
				string[] arr = (string[]) val;
				ctx.out_stream.put_byte((uint8) GLib.Type.STRING | 0x80);
				if (arr.length < 128) {
					ctx.out_stream.put_byte((uint8) arr.length);
				} else {
					ctx.out_stream.put_byte((uint8) (0x80 | ((arr.length >> 8) & 0x7F)));
					ctx.out_stream.put_byte((uint8) (arr.length & 0xFF));
				}
				foreach (var s in arr) {
					var elem = s != null ? s : "";
					if (elem.length < 128) {
						ctx.out_stream.put_byte((uint8) elem.length);
					} else {
						ctx.out_stream.put_byte((uint8) (0x80 | ((elem.length >> 8) & 0x7F)));
						ctx.out_stream.put_byte((uint8) (elem.length & 0xFF));
					}
					size_t written;
					ctx.out_stream.write_all(((uint8[]) elem)[0:elem.length], out written);
				}
				return;
			}

			if (val.type().is_a(GLib.Type.ENUM)) {
				ctx.out_stream.put_byte((uint8) GLib.Type.ENUM);
				if ((int64) val.get_enum() >= -128 && (int64) val.get_enum() <= 127) {
					ctx.out_stream.put_byte(1);
					ctx.out_stream.put_byte((uint8) (int8) (int64) val.get_enum());
					return;
				}
				ctx.out_stream.put_byte(8);
				ctx.out_stream.put_int64((int64) val.get_enum());
				return;
			}
			if (val.type().is_a(GLib.Type.FLAGS)) {
				ctx.out_stream.put_byte((uint8) GLib.Type.FLAGS);
				if ((uint64) val.get_flags() <= 255) {
					ctx.out_stream.put_byte(1);
					ctx.out_stream.put_byte((uint8) (uint64) val.get_flags());
					return;
				}
				ctx.out_stream.put_byte(8);
				ctx.out_stream.put_uint64((uint64) val.get_flags());
				return;
			}
			if (val.type().is_a(GLib.Type.OBJECT)) {
				if (val.get_object() == null) {
					return;
				}
				if ((val.get_object() as Serializable) == null) {
					throw new StreamError.PROTOCOL(
						"value type '%s' is not Bin.Serializable",
						val.get_object().get_type().name()
					);
				}
				ctx.write_gtype(val.get_object().get_type());
				((Serializable) val.get_object()).bin_write(ctx);
				return;
			}

			throw new StreamError.PROTOCOL(
				"unsupported bin value type '%s'",
				val.type().name()
			);
		}

		/**
		 * Decode one wire value (type byte already consumed by the caller).
		 *
		 * Returns a {@link GLib.Value}. Does not assign GObject properties.
		 *
		 * @param ctx active bin session
		 * @param type_byte wire type byte ({@link GLib.Type} fundamental; bit 7 = array)
		 * @return decoded value
		 */
		public static GLib.Value read(Stream ctx, uint8 type_byte) throws GLib.Error
		{
			if ((GLib.Type) (type_byte & 0x7F) == GLib.Type.BOXED) {
				var blob_len = ctx.in_stream.read_uint32();
				var blob_buf = new uint8[blob_len + 1];
				size_t blob_read;
				ctx.in_stream.read_all(blob_buf[0:blob_len], out blob_read);
				blob_buf[blob_len] = 0;
				var blob_val = GLib.Value(typeof(string));
				blob_val.set_string((string) blob_buf);
				return blob_val;
			}
			if ((GLib.Type) (type_byte & 0x7F) == GLib.Type.STRING) {
				if ((type_byte & 0x80) == 0) {
					var lo = ctx.in_stream.read_byte();
					if ((lo & 0x80) == 0) {
						var str_buf = new uint8[lo + 1];
						size_t str_read;
						ctx.in_stream.read_all(str_buf[0:lo], out str_read);
						str_buf[lo] = 0;
						var str_val = GLib.Value(typeof(string));
						str_val.set_string((string) str_buf);
						return str_val;
					}
					var str_len = ((lo & 0x7F) << 8) | ctx.in_stream.read_byte();
					var long_buf = new uint8[str_len + 1];
					size_t long_read;
					ctx.in_stream.read_all(long_buf[0:str_len], out long_read);
					long_buf[str_len] = 0;
					var long_val = GLib.Value(typeof(string));
					long_val.set_string((string) long_buf);
					return long_val;
				}
				var n = ctx.in_stream.read_byte();
				var count = n & 0x7F;
				if ((n & 0x80) != 0) {
					count = (count << 8) | ctx.in_stream.read_byte();
				}
				string[] arr = {};
				for (var i = 0; i < count; i++) {
					var el = ctx.in_stream.read_byte();
					if ((el & 0x80) == 0) {
						var buf = new uint8[el + 1];
						size_t read_bytes;
						ctx.in_stream.read_all(buf[0:el], out read_bytes);
						buf[el] = 0;
						arr += (string) buf;
						continue;
					}
					var elem_len = ((el & 0x7F) << 8) | ctx.in_stream.read_byte();
					var elem_buf = new uint8[elem_len + 1];
					size_t elem_read;
					ctx.in_stream.read_all(elem_buf[0:elem_len], out elem_read);
					elem_buf[elem_len] = 0;
					arr += (string) elem_buf;
				}
				return arr;
			}
			switch ((GLib.Type) (type_byte & 0x7F)) {
				case GLib.Type.BOOLEAN:
					var bool_val = GLib.Value(typeof(bool));
					bool_val.set_boolean(ctx.in_stream.read_byte() == 1);
					return bool_val;

				case GLib.Type.CHAR:
					var char_val = GLib.Value(GLib.Type.CHAR);
					char_val.set_schar((int8) ctx.in_stream.read_byte());
					return char_val;

				case GLib.Type.UCHAR:
					var uchar_val = GLib.Value(GLib.Type.UCHAR);
					uchar_val.set_uchar((uchar) ctx.in_stream.read_byte());
					return uchar_val;

				case GLib.Type.ENUM:
					var enum_width = ctx.in_stream.read_byte();
					var enum_val = GLib.Value(typeof(int));
					if (enum_width == 1) {
						enum_val.set_int((int) (int8) ctx.in_stream.read_byte());
						return enum_val;
					}
					if (enum_width != 8) {
						throw new StreamError.PROTOCOL(
							"invalid enum integer width %u",
							enum_width
						);
					}
					enum_val.set_int((int) ctx.in_stream.read_int64());
					return enum_val;

				case GLib.Type.FLAGS:
					var flags_width = ctx.in_stream.read_byte();
					var flags_val = GLib.Value(typeof(uint));
					if (flags_width == 1) {
						flags_val.set_uint((uint) ctx.in_stream.read_byte());
						return flags_val;
					}
					if (flags_width != 8) {
						throw new StreamError.PROTOCOL(
							"invalid flags integer width %u",
							flags_width
						);
					}
					flags_val.set_uint((uint) ctx.in_stream.read_uint64());
					return flags_val;

				case GLib.Type.INT:
					var int_width = ctx.in_stream.read_byte();
					var int_val = GLib.Value(typeof(int));
					if (int_width == 1) {
						int_val.set_int((int) (int8) ctx.in_stream.read_byte());
						return int_val;
					}
					if (int_width != 8) {
						throw new StreamError.PROTOCOL(
							"invalid signed integer width %u",
							int_width
						);
					}
					int_val.set_int((int) ctx.in_stream.read_int64());
					return int_val;

				case GLib.Type.INT64:
					var i64_width = ctx.in_stream.read_byte();
					var i64_val = GLib.Value(typeof(int64));
					if (i64_width == 1) {
						i64_val.set_int64((int64) (int8) ctx.in_stream.read_byte());
						return i64_val;
					}
					if (i64_width != 8) {
						throw new StreamError.PROTOCOL(
							"invalid signed integer width %u",
							i64_width
						);
					}
					i64_val.set_int64(ctx.in_stream.read_int64());
					return i64_val;

				case GLib.Type.UINT:
					var uint_width = ctx.in_stream.read_byte();
					var uint_val = GLib.Value(typeof(uint));
					if (uint_width == 1) {
						uint_val.set_uint((uint) ctx.in_stream.read_byte());
						return uint_val;
					}
					if (uint_width != 8) {
						throw new StreamError.PROTOCOL(
							"invalid unsigned integer width %u",
							uint_width
						);
					}
					uint_val.set_uint((uint) ctx.in_stream.read_uint64());
					return uint_val;

				case GLib.Type.UINT64:
					var u64_width = ctx.in_stream.read_byte();
					var u64_val = GLib.Value(typeof(uint64));
					if (u64_width == 1) {
						u64_val.set_uint64((uint64) ctx.in_stream.read_byte());
						return u64_val;
					}
					if (u64_width != 8) {
						throw new StreamError.PROTOCOL(
							"invalid unsigned integer width %u",
							u64_width
						);
					}
					u64_val.set_uint64(ctx.in_stream.read_uint64());
					return u64_val;

				case GLib.Type.OBJECT:
					var child = ctx.parse_object();
					var obj_val = GLib.Value(child.get_type());
					obj_val.set_object(child);
					return obj_val;
			}

			throw new StreamError.PROTOCOL(
				"unsupported wire type 0x%02X",
				type_byte & 0x7F
			);
		}
	}
}
