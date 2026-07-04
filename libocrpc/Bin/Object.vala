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
	 * Convenience base for {@link Serializable} GObject types.
	 *
	 * Subclasses can {@code override} {@link bin_write_prop} / {@link bin_read_prop}
	 * for lists, blobs, and transient fields; {@link bin_pre} / {@link bin_post}
	 * for inbound object hooks; delegate to {@code base} for scalars and nested
	 * {@link Serializable} properties.
	 */
	public abstract class Object : GLib.Object, Serializable
	{
		public virtual void bin_write (Stream ctx) throws GLib.Error
		{
			unowned GLib.ObjectClass obj_class = this.get_class ();
			GLib.ParamSpec[] properties = obj_class.list_properties ();

			foreach (var prop in properties) {
				if (prop.name == "g-type-instance" || prop.name == "ref-count") {
					continue;
				}
				this.bin_write_prop (ctx, prop);
			}
			ctx.out_stream.put_uint16 (Stream.TOKEN_END);
		}

		public virtual void bin_write_prop (
			Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			var val = GLib.Value (prop.value_type);
			this.get_property (prop.name, ref val);

			switch (prop.value_type) {
				case GLib.Type.STRING:
					ctx.write_tag (prop.name);
					ctx.out_stream.put_byte ((uint8) GLib.Type.STRING);
					var s = val.get_string () ?? "";
					if (s.length > 65535) {
						GLib.error (
							"Short string prop '%s' is %u bytes — use GLib.Type.BOXED for large payloads",
							prop.name,
							s.length
						);
					}
					ctx.out_stream.put_uint16 ((uint16) s.length);
					size_t written;
					ctx.out_stream.write_all (((uint8[]) s)[0:s.length], out written);
					return;

				case GLib.Type.BOOLEAN:
					ctx.write_tag (prop.name);
					ctx.out_stream.put_byte ((uint8) GLib.Type.BOOLEAN);
					ctx.out_stream.put_byte (val.get_boolean () ? 1 : 0);
					return;

				case GLib.Type.CHAR:
					ctx.write_tag (prop.name);
					ctx.out_stream.put_byte ((uint8) GLib.Type.CHAR);
					ctx.out_stream.put_byte ((uint8) val.get_schar ());
					return;

				case GLib.Type.UCHAR:
					ctx.write_tag (prop.name);
					ctx.out_stream.put_byte ((uint8) GLib.Type.UCHAR);
					ctx.out_stream.put_byte ((uint8) val.get_uchar ());
					return;

				case GLib.Type.INT:
					ctx.write_tag (prop.name);
					ctx.out_stream.put_byte ((uint8) GLib.Type.INT);
					var iv = val.get_int ();
					if (iv >= -128 && iv <= 127) {
						ctx.out_stream.put_byte (1);
						ctx.out_stream.put_byte ((uint8) (int8) iv);
						return;
					}
					ctx.out_stream.put_byte (8);
					ctx.out_stream.put_int64 (iv);
					return;

				case GLib.Type.INT64:
					ctx.write_tag (prop.name);
					ctx.out_stream.put_byte ((uint8) GLib.Type.INT64);
					var iv64 = val.get_int64 ();
					if (iv64 >= -128 && iv64 <= 127) {
						ctx.out_stream.put_byte (1);
						ctx.out_stream.put_byte ((uint8) (int8) iv64);
						return;
					}
					ctx.out_stream.put_byte (8);
					ctx.out_stream.put_int64 (iv64);
					return;

				case GLib.Type.UINT:
					ctx.write_tag (prop.name);
					ctx.out_stream.put_byte ((uint8) GLib.Type.UINT);
					var uv = val.get_uint ();
					if (uv <= 255) {
						ctx.out_stream.put_byte (1);
						ctx.out_stream.put_byte ((uint8) uv);
						return;
					}
					ctx.out_stream.put_byte (8);
					ctx.out_stream.put_uint64 (uv);
					return;

				case GLib.Type.UINT64:
					ctx.write_tag (prop.name);
					ctx.out_stream.put_byte ((uint8) GLib.Type.UINT64);
					var uv64 = val.get_uint64 ();
					if (uv64 <= 255) {
						ctx.out_stream.put_byte (1);
						ctx.out_stream.put_byte ((uint8) uv64);
						return;
					}
					ctx.out_stream.put_byte (8);
					ctx.out_stream.put_uint64 (uv64);
					return;
			}

			if (prop.value_type.is_a (GLib.Type.ENUM)) {
				ctx.write_tag (prop.name);
				ctx.out_stream.put_byte ((uint8) GLib.Type.ENUM);
				var enum_iv = (int64) val.get_enum ();
				if (enum_iv >= -128 && enum_iv <= 127) {
					ctx.out_stream.put_byte (1);
					ctx.out_stream.put_byte ((uint8) (int8) enum_iv);
					return;
				}
				ctx.out_stream.put_byte (8);
				ctx.out_stream.put_int64 (enum_iv);
				return;
			}
			if (prop.value_type.is_a (GLib.Type.FLAGS)) {
				ctx.write_tag (prop.name);
				ctx.out_stream.put_byte ((uint8) GLib.Type.FLAGS);
				var flags_uv = (uint64) val.get_flags ();
				if (flags_uv <= 255) {
					ctx.out_stream.put_byte (1);
					ctx.out_stream.put_byte ((uint8) flags_uv);
					return;
				}
				ctx.out_stream.put_byte (8);
				ctx.out_stream.put_uint64 (flags_uv);
				return;
			}
			if (prop.value_type.is_a (GLib.Type.OBJECT)) {
				var obj = val.get_object ();
				if (obj == null) {
					return;
				}
				var ser = obj as Serializable;
				if (ser == null) {
					GLib.error (
						"prop '%s': type '%s' is not Bin.Serializable",
						prop.name,
						obj.get_type ().name ()
					);
				}
				ctx.write_tag (prop.name);
				ctx.write_gtype (obj.get_type ());
				ser.bin_write (ctx);
				return;
			}

			GLib.error (
				"unsupported bin prop type '%s' on '%s'",
				prop.value_type.name (),
				prop.name
			);
		}

		public virtual void bin_read (Stream ctx) throws GLib.Error
		{
			this.bin_pre (ctx);

			var prop_name = "";
			uint16 t;

			while ((t = ctx.read_tag (out prop_name)) != Stream.TOKEN_END) {
				var b = ctx.in_stream.read_byte ();
				if (b == 0xFF) {
					ctx.read_reg_gtype ();
					b = ctx.in_stream.read_byte ();
				}

				GLib.ParamSpec? prop = this.get_class ().find_property (prop_name);
				if (prop == null) {
					GLib.error ("unknown bin property '%s'", prop_name);
				}
				this.bin_read_prop (ctx, prop, b);
			}

			this.bin_post (ctx);
		}

		public virtual void bin_pre (Stream ctx) throws GLib.Error
		{
		}

		public virtual void bin_post (Stream ctx) throws GLib.Error
		{
		}

		public virtual void bin_read_prop (
			Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			var base_type = (uint8) (type_byte & 0x7F);
			if ((type_byte & 0x80) != 0) {
				GLib.error (
					"array prop '%s' requires a bin_read_prop override",
					prop.name
				);
			}

			var val = GLib.Value (prop.value_type);
			var width = (uint8) 0;

			switch ((GLib.Type) base_type) {
				case GLib.Type.STRING:
					if (prop.value_type != GLib.Type.STRING) {
						GLib.error (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					var len = ctx.in_stream.read_uint16 ();
					var buf = new uint8[len + 1];
					size_t read_bytes;
					ctx.in_stream.read_all (buf[0:len], out read_bytes);
					buf[len] = 0;
					val.set_string ((string) buf);
					this.set_property (prop.name, val);
					return;

				case GLib.Type.BOOLEAN:
					if (prop.value_type != GLib.Type.BOOLEAN) {
						GLib.error (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					val.set_boolean (ctx.in_stream.read_byte () == 1);
					this.set_property (prop.name, val);
					return;

				case GLib.Type.CHAR:
					if (prop.value_type != GLib.Type.CHAR) {
						GLib.error (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					val.set_schar ((int8) ctx.in_stream.read_byte ());
					this.set_property (prop.name, val);
					return;

				case GLib.Type.UCHAR:
					if (prop.value_type != GLib.Type.UCHAR) {
						GLib.error (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					val.set_uchar ((uchar) ctx.in_stream.read_byte ());
					this.set_property (prop.name, val);
					return;

				case GLib.Type.ENUM:
					if (!prop.value_type.is_a (GLib.Type.ENUM)) {
						GLib.error (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					width = ctx.in_stream.read_byte ();
					if (width == 1) {
						val.set_enum ((int) (int8) ctx.in_stream.read_byte ());
						this.set_property (prop.name, val);
						return;
					}
					if (width != 8) {
						GLib.error (
							"invalid enum integer width %u on prop '%s'",
							width,
							prop.name
						);
					}
					val.set_enum ((int) ctx.in_stream.read_int64 ());
					this.set_property (prop.name, val);
					return;

				case GLib.Type.FLAGS:
					if (!prop.value_type.is_a (GLib.Type.FLAGS)) {
						GLib.error (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					width = ctx.in_stream.read_byte ();
					if (width == 1) {
						val.set_flags ((uint) ctx.in_stream.read_byte ());
						this.set_property (prop.name, val);
						return;
					}
					if (width != 8) {
						GLib.error (
							"invalid flags integer width %u on prop '%s'",
							width,
							prop.name
						);
					}
					val.set_flags ((uint) ctx.in_stream.read_uint64 ());
					this.set_property (prop.name, val);
					return;

				case GLib.Type.INT:
					if (prop.value_type != GLib.Type.INT) {
						GLib.error (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					width = ctx.in_stream.read_byte ();
					if (width == 1) {
						val.set_int ((int) (int8) ctx.in_stream.read_byte ());
						this.set_property (prop.name, val);
						return;
					}
					if (width != 8) {
						GLib.error (
							"invalid signed integer width %u on prop '%s'",
							width,
							prop.name
						);
					}
					val.set_int ((int) ctx.in_stream.read_int64 ());
					this.set_property (prop.name, val);
					return;

				case GLib.Type.INT64:
					if (prop.value_type != GLib.Type.INT64) {
						GLib.error (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					width = ctx.in_stream.read_byte ();
					if (width == 1) {
						val.set_int64 ((int64) (int8) ctx.in_stream.read_byte ());
						this.set_property (prop.name, val);
						return;
					}
					if (width != 8) {
						GLib.error (
							"invalid signed integer width %u on prop '%s'",
							width,
							prop.name
						);
					}
					val.set_int64 (ctx.in_stream.read_int64 ());
					this.set_property (prop.name, val);
					return;

				case GLib.Type.UINT:
					if (prop.value_type != GLib.Type.UINT) {
						GLib.error (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					width = ctx.in_stream.read_byte ();
					if (width == 1) {
						val.set_uint ((uint) ctx.in_stream.read_byte ());
						this.set_property (prop.name, val);
						return;
					}
					if (width != 8) {
						GLib.error (
							"invalid unsigned integer width %u on prop '%s'",
							width,
							prop.name
						);
					}
					val.set_uint ((uint) ctx.in_stream.read_uint64 ());
					this.set_property (prop.name, val);
					return;

				case GLib.Type.UINT64:
					if (prop.value_type != GLib.Type.UINT64) {
						GLib.error (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					width = ctx.in_stream.read_byte ();
					if (width == 1) {
						val.set_uint64 ((uint64) ctx.in_stream.read_byte ());
						this.set_property (prop.name, val);
						return;
					}
					if (width != 8) {
						GLib.error (
							"invalid unsigned integer width %u on prop '%s'",
							width,
							prop.name
						);
					}
					val.set_uint64 (ctx.in_stream.read_uint64 ());
					this.set_property (prop.name, val);
					return;

				case GLib.Type.OBJECT:
					if (!prop.value_type.is_a (GLib.Type.OBJECT)) {
						GLib.error (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					var child = ctx.parse_object ();
					if (!child.get_type ().is_a (prop.value_type)) {
						GLib.error (
							"prop '%s' cannot assign '%s' to '%s'",
							prop.name,
							child.get_type ().name (),
							prop.value_type.name ()
						);
					}
					val.set_object (child);
					this.set_property (prop.name, val);
					return;
			}

			GLib.error (
				"unsupported wire type 0x%02X on prop '%s'",
				base_type,
				prop.name
			);
		}
	}
}
