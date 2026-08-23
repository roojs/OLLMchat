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
					var s = val.get_string();
					s = s != null ? s : "";
					if (s.length > 32767) {
						throw new StreamError.PROTOCOL("string value longer than 32767");
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

				case GLib.Type.FLOAT:
					var f = val.get_float();
					var f_bits = (uint32) 0;
					GLib.Memory.copy(&f_bits, &f, 4);
					ctx.out_stream.put_byte((uint8) GLib.Type.FLOAT);
					ctx.out_stream.put_uint32(f_bits);
					return;

				case GLib.Type.DOUBLE:
					var d = val.get_double();
					var d_bits = (uint64) 0;
					GLib.Memory.copy(&d_bits, &d, 8);
					ctx.out_stream.put_byte((uint8) GLib.Type.DOUBLE);
					ctx.out_stream.put_uint64(d_bits);
					return;
			}

			if (val.type() == typeof(GLib.Bytes)) {
				var blob = (GLib.Bytes) val.get_boxed();
				ctx.out_stream.put_byte((uint8) GLib.Type.BOXED);
				ctx.out_stream.put_uint32((uint32) blob.get_size());
				if (blob.get_size() == 0) {
					return;
				}
				size_t written;
				ctx.out_stream.write_all(blob.get_data(), out written);
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

			if (val.type() == typeof(int[])) {
				var arr = (int[]) val;
				StreamValue.write_numeric_array(
					ctx, GLib.Type.INT, arr.length, arr, sizeof(int));
				return;
			}
			if (val.type() == typeof(uint[])) {
				var arr = (uint[]) val;
				StreamValue.write_numeric_array(
					ctx, GLib.Type.UINT, arr.length, arr, sizeof(uint));
				return;
			}
			if (val.type() == typeof(int64[])) {
				var arr = (int64[]) val;
				StreamValue.write_numeric_array(
					ctx, GLib.Type.INT64, arr.length, arr, sizeof(int64));
				return;
			}
			if (val.type() == typeof(uint64[])) {
				var arr = (uint64[]) val;
				StreamValue.write_numeric_array(
					ctx, GLib.Type.UINT64, arr.length, arr, sizeof(uint64));
				return;
			}
			if (val.type() == typeof(float[])) {
				var arr = (float[]) val;
				StreamValue.write_numeric_array(
					ctx, GLib.Type.FLOAT, arr.length, arr, sizeof(float));
				return;
			}
			if (val.type() == typeof(double[])) {
				var arr = (double[]) val;
				StreamValue.write_numeric_array(
					ctx, GLib.Type.DOUBLE, arr.length, arr, sizeof(double));
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
				var blob_buf = new uint8[blob_len];
				if (blob_len > 0) {
					size_t blob_read;
					ctx.in_stream.read_all(blob_buf[0:blob_len], out blob_read);
				}
				var blob_val = GLib.Value(typeof(GLib.Bytes));
				blob_val.set_boxed(new GLib.Bytes(blob_buf));
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
			if ((type_byte & 0x80) != 0) {
				return StreamValue.read_array(ctx, type_byte);
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

				case GLib.Type.FLOAT:
					var f_bits = ctx.in_stream.read_uint32();
					var f = (float) 0;
					GLib.Memory.copy(&f, &f_bits, 4);
					var f_val = GLib.Value(typeof(float));
					f_val.set_float(f);
					return f_val;

				case GLib.Type.DOUBLE:
					var d_bits = ctx.in_stream.read_uint64();
					var d = (double) 0;
					GLib.Memory.copy(&d, &d_bits, 8);
					var d_val = GLib.Value(typeof(double));
					d_val.set_double(d);
					return d_val;

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

		private static void write_numeric_array(
			Stream ctx,
			GLib.Type fundamental,
			int count,
			void* native,
			size_t elem_size
		) throws GLib.Error
		{
			ctx.out_stream.put_byte((uint8) fundamental | 0x80);
			if (count < 128) {
				ctx.out_stream.put_byte((uint8) count);
			} else {
				ctx.out_stream.put_byte((uint8) (0x80 | ((count >> 8) & 0x7F)));
				ctx.out_stream.put_byte((uint8) (count & 0xFF));
			}
			if (count == 0) {
				return;
			}
			var nbytes = count * elem_size;
			var payload = new uint8[nbytes];
			GLib.Memory.copy(payload, native, nbytes);
			size_t written;
			ctx.out_stream.write_all(payload, out written);
		}

		/**
		 * Decode a homogeneous scalar array (type byte has array flag).
		 *
		 * Compact count (§9), then one fixed-width **native-endian** payload slab —
		 * not the per-element type-byte property layout in §15. Same-endian peers only.
		 *
		 * @param ctx active bin session
		 * @param type_byte wire type with bit 7 set
		 * @return array {@link GLib.Value} (''int[]'', ''uint[]'', …)
		 */
		private static GLib.Value read_array(Stream ctx, uint8 type_byte) throws GLib.Error
		{
			var n = ctx.in_stream.read_byte();
			var count = n & 0x7F;
			if ((n & 0x80) != 0) {
				count = (count << 8) | ctx.in_stream.read_byte();
			}
			switch ((GLib.Type) (type_byte & 0x7F)) {
				case GLib.Type.INT:
					var ints = new int[count];
					size_t int_read;
					ctx.in_stream.read_all(
						((uint8[]) ints)[0:count * sizeof(int)], out int_read);
					return ints;

				case GLib.Type.UINT:
					var uints = new uint[count];
					size_t uint_read;
					ctx.in_stream.read_all(
						((uint8[]) uints)[0:count * sizeof(uint)], out uint_read);
					return uints;

				case GLib.Type.INT64:
					var i64s = new int64[count];
					size_t i64_read;
					ctx.in_stream.read_all(
						((uint8[]) i64s)[0:count * sizeof(int64)], out i64_read);
					return i64s;

				case GLib.Type.UINT64:
					var u64s = new uint64[count];
					size_t u64_read;
					ctx.in_stream.read_all(
						((uint8[]) u64s)[0:count * sizeof(uint64)], out u64_read);
					return u64s;

				case GLib.Type.FLOAT:
					var floats = new float[count];
					size_t float_read;
					ctx.in_stream.read_all(
						((uint8[]) floats)[0:count * sizeof(float)], out float_read);
					return floats;

				case GLib.Type.DOUBLE:
					var doubles = new double[count];
					size_t double_read;
					ctx.in_stream.read_all(
						((uint8[]) doubles)[0:count * sizeof(double)], out double_read);
					return doubles;

				default:
					throw new StreamError.PROTOCOL(
						"unsupported bin array type 0x%02X",
						type_byte & 0x7F
					);
			}
		}
	}
}
