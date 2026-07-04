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
	 * Default {@link bin_write_prop} / {@link bin_read_prop} cover scalar
	 * fundamentals and nested {@link Serializable} object properties.
	 *
	 * Override for transient fields, {@code Gee.ArrayList} / list properties,
	 * {@code uint8[]} (wire as blob or typed array — see docs/bin-rpc-protocol.md),
	 * and any other non-scalar shape.
	 *
	 * Override {@link bin_pre} / {@link bin_post} for work before or after
	 * inbound property decode on this object.
	 */
	public interface Serializable : GLib.Object
	{
		public virtual void bin_write (Stream ctx) throws GLib.Error
		{
			foreach (var prop in this.get_class ().list_properties ()) {
				if (prop.name == "g-type-instance" || prop.name == "ref-count") {
					continue;
				}
				this.bin_write_prop (ctx, prop);
			}
			ctx.out_stream.put_uint16 (Stream.TOKEN_END);
		}

		/**
		 * Encode one GObject property onto the stream.
		 *
		 * @param ctx active bin session
		 * @param prop property metadata
		 */
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
					var s = val.get_string ();
					if (s == null) {
						s = "";
					}
					if (s.length > 65535) {
						throw new Error.PROPERTY (
							"Short string prop '%s' is %u bytes — use GLib.Type.BOXED for large payloads",
							prop.name,
							s.length
						);
					}
					ctx.out_stream.put_uint16 ((uint16) s.length);
					size_t written;
					ctx.out_stream.write_all (
						((uint8[]) s)[0:s.length],
						out written
					);
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
					if (val.get_int () >= -128 && val.get_int () <= 127) {
						ctx.out_stream.put_byte (1);
						ctx.out_stream.put_byte ((uint8) (int8) val.get_int ());
						return;
					}
					ctx.out_stream.put_byte (8);
					ctx.out_stream.put_int64 (val.get_int ());
					return;

				case GLib.Type.INT64:
					ctx.write_tag (prop.name);
					ctx.out_stream.put_byte ((uint8) GLib.Type.INT64);
					if (val.get_int64 () >= -128 && val.get_int64 () <= 127) {
						ctx.out_stream.put_byte (1);
						ctx.out_stream.put_byte ((uint8) (int8) val.get_int64 ());
						return;
					}
					ctx.out_stream.put_byte (8);
					ctx.out_stream.put_int64 (val.get_int64 ());
					return;

				case GLib.Type.UINT:
					ctx.write_tag (prop.name);
					ctx.out_stream.put_byte ((uint8) GLib.Type.UINT);
					if (val.get_uint () <= 255) {
						ctx.out_stream.put_byte (1);
						ctx.out_stream.put_byte ((uint8) val.get_uint ());
						return;
					}
					ctx.out_stream.put_byte (8);
					ctx.out_stream.put_uint64 (val.get_uint ());
					return;

				case GLib.Type.UINT64:
					ctx.write_tag (prop.name);
					ctx.out_stream.put_byte ((uint8) GLib.Type.UINT64);
					if (val.get_uint64 () <= 255) {
						ctx.out_stream.put_byte (1);
						ctx.out_stream.put_byte ((uint8) val.get_uint64 ());
						return;
					}
					ctx.out_stream.put_byte (8);
					ctx.out_stream.put_uint64 (val.get_uint64 ());
					return;
			}

			if (prop.value_type.is_a (GLib.Type.ENUM)) {
				ctx.write_tag (prop.name);
				ctx.out_stream.put_byte ((uint8) GLib.Type.ENUM);
				if ((int64) val.get_enum () >= -128
					&& (int64) val.get_enum () <= 127) {
					ctx.out_stream.put_byte (1);
					ctx.out_stream.put_byte (
						(uint8) (int8) (int64) val.get_enum ()
					);
					return;
				}
				ctx.out_stream.put_byte (8);
				ctx.out_stream.put_int64 ((int64) val.get_enum ());
				return;
			}
			if (prop.value_type.is_a (GLib.Type.FLAGS)) {
				ctx.write_tag (prop.name);
				ctx.out_stream.put_byte ((uint8) GLib.Type.FLAGS);
				if ((uint64) val.get_flags () <= 255) {
					ctx.out_stream.put_byte (1);
					ctx.out_stream.put_byte ((uint8) (uint64) val.get_flags ());
					return;
				}
				ctx.out_stream.put_byte (8);
				ctx.out_stream.put_uint64 ((uint64) val.get_flags ());
				return;
			}
			if (prop.value_type.is_a (GLib.Type.OBJECT)) {
				if (val.get_object () == null) {
					return;
				}
				if ((val.get_object () as Serializable) == null) {
					throw new Error.PROPERTY (
						"prop '%s': type '%s' is not Bin.Serializable",
						prop.name,
						val.get_object ().get_type ().name ()
					);
				}
				ctx.write_tag (prop.name);
				ctx.write_gtype (val.get_object ().get_type ());
				((Serializable) val.get_object ()).bin_write (ctx);
				return;
			}

			throw new Error.PROPERTY (
				"unsupported bin prop type '%s' on '%s'",
				prop.value_type.name (),
				prop.name
			);
		}

		public virtual void bin_read (Stream ctx) throws GLib.Error
		{
			this.bin_pre (ctx);

			var prop_name = "";
			var t = (uint16) 0;

			while ((t = ctx.read_tag (out prop_name)) != Stream.TOKEN_END) {
				var b = ctx.in_stream.read_byte ();
				if (b == 0xFF) {
					ctx.read_reg_gtype ();
					b = ctx.in_stream.read_byte ();
				}

				var prop = this.get_class ().find_property (prop_name);
				if (prop == null) {
					throw new Error.PROPERTY (
						"unknown bin property '%s'",
						prop_name
					);
				}
				this.bin_read_prop (ctx, prop, b);
			}

			this.bin_post (ctx);
		}

		/**
		 * Run before inbound properties are decoded into this object.
		 *
		 * @param ctx active bin session
		 */
		public virtual void bin_pre (Stream ctx) throws GLib.Error
		{
		}

		/**
		 * Run after all inbound properties are decoded.
		 *
		 * @param ctx active bin session
		 */
		public virtual void bin_post (Stream ctx) throws GLib.Error
		{
		}

		/**
		 * Decode one wire property into this object.
		 *
		 * @param ctx active bin session
		 * @param prop property metadata
		 * @param type_byte wire type byte ({@link GLib.Type} fundamental; bit 7 = array)
		 */
		public virtual void bin_read_prop (
			Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			if ((type_byte & 0x80) != 0) {
				throw new Error.PROPERTY (
					"array prop '%s' requires a bin_read_prop override",
					prop.name
				);
			}

			var val = GLib.Value (prop.value_type);
			var width = (uint8) 0;

			switch ((GLib.Type) (type_byte & 0x7F)) {
				case GLib.Type.STRING:
					if (prop.value_type != GLib.Type.STRING) {
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
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
						throw new Error.PROPERTY (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					var child = ctx.parse_object ();
					if (!child.get_type ().is_a (prop.value_type)) {
						throw new Error.PROPERTY (
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

			throw new Error.PROPERTY (
				"unsupported wire type 0x%02X on prop '%s'",
				type_byte & 0x7F,
				prop.name
			);
		}
	}
}
