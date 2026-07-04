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
	 * GObject types that read/write on a {@link Stream} session.
	 *
	 * Override {@link bin_write_prop} / {@link bin_read_prop} for short/long
	 * lists, nested objects, and transient fields.
	 */
	public interface Serializable : GLib.Object
	{
		public virtual void bin_write (Stream ctx) throws GLib.Error
		{
			unowned GLib.ObjectClass obj_class = this.get_class ();
			GLib.ParamSpec[] properties = obj_class.list_properties ();

			foreach (var prop in properties) {
				if (prop.name == "g-type-instance" || prop.name == "ref-count") {
					continue;
				}
				if (!this.bin_write_prop (ctx, prop)) {
					continue;
				}
			}
			ctx.out_stream.put_uint16 (Stream.TOKEN_END);
		}

		/**
		 * Encode one GObject property onto the stream.
		 *
		 * @param ctx active bin session
		 * @param prop property metadata
		 * @return true when the prop was written; false to omit (transient / unsupported)
		 */
		public virtual bool bin_write_prop (
			Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			GLib.Value val = GLib.Value (prop.value_type);
			this.get_property (prop.name, ref val);

			if (prop.value_type == typeof (string)) {
				ctx.write_tag (prop.name);
				string s = val.get_string () ?? "";
				if (s.length > 65535) {
					GLib.error (
						"Short string prop '%s' is %u bytes — use uint8[] for large payloads",
						prop.name,
						s.length
					);
				}
				ctx.out_stream.put_uint16 ((uint16) s.length);
				size_t written;
				ctx.out_stream.write_all (((uint8[]) s)[0:s.length], out written);
				return true;
			}

			if (prop.value_type == typeof (bool)) {
				ctx.write_tag (prop.name);
				ctx.out_stream.put_byte (val.get_boolean () ? 1 : 0);
				return true;
			}

			if (prop.value_type == typeof (char)) {
				ctx.write_tag (prop.name);
				ctx.out_stream.put_byte ((uint8) val.get_char ());
				return true;
			}

			if (prop.value_type == typeof (int8)) {
				ctx.write_tag (prop.name);
				ctx.out_stream.put_byte ((uint8) val.get_schar ());
				return true;
			}

			if (prop.value_type == typeof (uchar)) {
				ctx.write_tag (prop.name);
				ctx.out_stream.put_byte ((uint8) val.get_uchar ());
				return true;
			}

			if (prop.value_type.is_a (GLib.Type.ENUM)) {
				ctx.write_tag (prop.name);
				int64 enum_iv = (int64) val.get_enum ();
				if (enum_iv >= -128 && enum_iv <= 127) {
					ctx.out_stream.put_byte (1);
					ctx.out_stream.put_byte ((uint8) (int8) enum_iv);
					return true;
				}
				ctx.out_stream.put_byte (8);
				ctx.out_stream.put_int64 (enum_iv);
				return true;
			}

			if (prop.value_type.is_a (GLib.Type.FLAGS)) {
				ctx.write_tag (prop.name);
				uint64 flags_uv = (uint64) val.get_flags ();
				if (flags_uv <= 255) {
					ctx.out_stream.put_byte (1);
					ctx.out_stream.put_byte ((uint8) flags_uv);
					return true;
				}
				ctx.out_stream.put_byte (8);
				ctx.out_stream.put_uint64 (flags_uv);
				return true;
			}

			if (prop.value_type == typeof (int)) {
				ctx.write_tag (prop.name);
				int64 iv = val.get_int ();
				if (iv >= -128 && iv <= 127) {
					ctx.out_stream.put_byte (1);
					ctx.out_stream.put_byte ((uint8) (int8) iv);
					return true;
				}
				ctx.out_stream.put_byte (8);
				ctx.out_stream.put_int64 (iv);
				return true;
			}

			if (prop.value_type == typeof (int64)) {
				ctx.write_tag (prop.name);
				int64 iv = val.get_int64 ();
				if (iv >= -128 && iv <= 127) {
					ctx.out_stream.put_byte (1);
					ctx.out_stream.put_byte ((uint8) (int8) iv);
					return true;
				}
				ctx.out_stream.put_byte (8);
				ctx.out_stream.put_int64 (iv);
				return true;
			}

			if (prop.value_type == typeof (uint)) {
				ctx.write_tag (prop.name);
				uint64 uv = val.get_uint ();
				if (uv <= 255) {
					ctx.out_stream.put_byte (1);
					ctx.out_stream.put_byte ((uint8) uv);
					return true;
				}
				ctx.out_stream.put_byte (8);
				ctx.out_stream.put_uint64 (uv);
				return true;
			}

			if (prop.value_type == typeof (uint64)) {
				ctx.write_tag (prop.name);
				uint64 uv = val.get_uint64 ();
				if (uv <= 255) {
					ctx.out_stream.put_byte (1);
					ctx.out_stream.put_byte ((uint8) uv);
					return true;
				}
				ctx.out_stream.put_byte (8);
				ctx.out_stream.put_uint64 (uv);
				return true;
			}

			return false;
		}

		public virtual void bin_read (Stream ctx) throws GLib.Error
		{
			string prop_name;
			uint16 t;

			while ((t = ctx.read_tag (out prop_name)) != Stream.TOKEN_END) {
				GLib.ParamSpec? prop = this.get_class ().find_property (prop_name);
				if (prop == null) {
					continue;
				}
				if (!this.bin_read_prop (ctx, prop)) {
					GLib.error ("cannot decode bin prop '%s'", prop_name);
				}
			}
		}

		/**
		 * Decode one wire property into this object.
		 *
		 * @param ctx active bin session
		 * @param prop property metadata
		 * @return true when the prop was consumed; false if unsupported
		 */
		public virtual bool bin_read_prop (
			Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			GLib.Value val = GLib.Value (prop.value_type);

			if (prop.value_type == typeof (string)) {
				uint16 len = ctx.in_stream.read_uint16 ();
				uint8[] buf = new uint8[len + 1];
				size_t read_bytes;
				ctx.in_stream.read_all (buf[0:len], out read_bytes);
				buf[len] = 0;
				val.set_string ((string) buf);
				this.set_property (prop.name, val);
				return true;
			}

			if (prop.value_type == typeof (bool)) {
				val.set_boolean (ctx.in_stream.read_byte () == 1);
				this.set_property (prop.name, val);
				return true;
			}

			if (prop.value_type == typeof (char)) {
				val.set_char ((char) (int8) ctx.in_stream.read_byte ());
				this.set_property (prop.name, val);
				return true;
			}

			if (prop.value_type == typeof (int8)) {
				val.set_schar ((int8) ctx.in_stream.read_byte ());
				this.set_property (prop.name, val);
				return true;
			}

			if (prop.value_type == typeof (uchar)) {
				val.set_uchar ((uchar) ctx.in_stream.read_byte ());
				this.set_property (prop.name, val);
				return true;
			}

			if (prop.value_type.is_a (GLib.Type.ENUM)) {
				uint8 enum_width = ctx.in_stream.read_byte ();
				if (enum_width == 1) {
					val.set_enum ((int) (int8) ctx.in_stream.read_byte ());
					this.set_property (prop.name, val);
					return true;
				}
				if (enum_width != 8) {
					GLib.error (
						"invalid enum integer width %u on prop '%s'",
						enum_width,
						prop.name
					);
				}
				val.set_enum ((int) ctx.in_stream.read_int64 ());
				this.set_property (prop.name, val);
				return true;
			}

			if (prop.value_type.is_a (GLib.Type.FLAGS)) {
				uint8 flags_width = ctx.in_stream.read_byte ();
				if (flags_width == 1) {
					val.set_flags ((uint) ctx.in_stream.read_byte ());
					this.set_property (prop.name, val);
					return true;
				}
				if (flags_width != 8) {
					GLib.error (
						"invalid flags integer width %u on prop '%s'",
						flags_width,
						prop.name
					);
				}
				val.set_flags ((uint) ctx.in_stream.read_uint64 ());
				this.set_property (prop.name, val);
				return true;
			}

			if (prop.value_type == typeof (int)) {
				uint8 signed_width = ctx.in_stream.read_byte ();
				if (signed_width == 1) {
					val.set_int ((int) (int8) ctx.in_stream.read_byte ());
					this.set_property (prop.name, val);
					return true;
				}
				if (signed_width != 8) {
					GLib.error (
						"invalid signed integer width %u on prop '%s'",
						signed_width,
						prop.name
					);
				}
				val.set_int ((int) ctx.in_stream.read_int64 ());
				this.set_property (prop.name, val);
				return true;
			}

			if (prop.value_type == typeof (int64)) {
				uint8 signed_width = ctx.in_stream.read_byte ();
				if (signed_width == 1) {
					val.set_int64 ((int64) (int8) ctx.in_stream.read_byte ());
					this.set_property (prop.name, val);
					return true;
				}
				if (signed_width != 8) {
					GLib.error (
						"invalid signed integer width %u on prop '%s'",
						signed_width,
						prop.name
					);
				}
				val.set_int64 (ctx.in_stream.read_int64 ());
				this.set_property (prop.name, val);
				return true;
			}

			if (prop.value_type == typeof (uint)) {
				uint8 unsigned_width = ctx.in_stream.read_byte ();
				if (unsigned_width == 1) {
					val.set_uint ((uint) ctx.in_stream.read_byte ());
					this.set_property (prop.name, val);
					return true;
				}
				if (unsigned_width != 8) {
					GLib.error (
						"invalid unsigned integer width %u on prop '%s'",
						unsigned_width,
						prop.name
					);
				}
				val.set_uint ((uint) ctx.in_stream.read_uint64 ());
				this.set_property (prop.name, val);
				return true;
			}

			if (prop.value_type == typeof (uint64)) {
				uint8 unsigned_width = ctx.in_stream.read_byte ();
				if (unsigned_width == 1) {
					val.set_uint64 ((uint64) ctx.in_stream.read_byte ());
					this.set_property (prop.name, val);
					return true;
				}
				if (unsigned_width != 8) {
					GLib.error (
						"invalid unsigned integer width %u on prop '%s'",
						unsigned_width,
						prop.name
					);
				}
				val.set_uint64 (ctx.in_stream.read_uint64 ());
				this.set_property (prop.name, val);
				return true;
			}

			return false;
		}
	}
}
