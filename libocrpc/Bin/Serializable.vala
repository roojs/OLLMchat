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
	 * {@link Serializable} property encode/decode failures (throw/catch).
	 *
	 * Not {@link GLib.Error} abort — use {{{throw new SerializableError.*}}}
	 * from {@link bin_write_prop} / {@link bin_read_prop} paths.
	 */
	public errordomain SerializableError
	{
		PROPERTY
	}

	/**
	 * GObject types that read/write on a {@link Stream} session.
	 *
	 * Override {@link bin_write_prop} / {@link bin_read_prop} to omit or
	 * customize props; call {@link bin_default_write_prop} /
	 * {@link bin_default_read_prop} for stock scalar encoding.
	 *
	 * Override for {{{Gee.ArrayList}}} / list properties,
	 * {{{uint8[]}}} (wire as blob or typed array — see docs/bin-rpc-protocol.md),
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

		public virtual void bin_write_prop (
			Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			this.bin_default_write_prop (ctx, prop);
		}

		/**
		 * Stock scalar/object encode for one property.
		 *
		 * Omit overrides call this from their {@link bin_write_prop} default
		 * branch.
		 *
		 * @param ctx active bin session
		 * @param prop property metadata
		 */
		public virtual void bin_default_write_prop (
			Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			var val = GLib.Value (prop.value_type);
			this.get_property (prop.name, ref val);

			switch (prop.value_type) {
				case GLib.Type.STRING:
					ctx.write_tag (prop.name);
					var s = val.get_string () != null
						? val.get_string ()
						: "";
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
						size_t written;
						ctx.out_stream.write_all (
							((uint8[]) s)[0:s.length],
							out written
						);
						return;
					}
					ctx.out_stream.put_byte (
						(uint8) (0x80 | ((s.length >> 8) & 0x7F))
					);
					ctx.out_stream.put_byte (
						(uint8) (s.length & 0xFF)
					);
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

			if (prop.value_type == typeof (string[])) {
				var arr = (string[]) val;
				ctx.write_tag (prop.name);
				ctx.out_stream.put_byte (
					(uint8) GLib.Type.STRING | 0x80
				);
				if (arr.length < 128) {
					ctx.out_stream.put_byte ((uint8) arr.length);
				} else {
					ctx.out_stream.put_byte (
						(uint8) (0x80 | ((arr.length >> 8) & 0x7F))
					);
					ctx.out_stream.put_byte (
						(uint8) (arr.length & 0xFF)
					);
				}
				foreach (var s in arr) {
					var elem = s != null ? s : "";
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
					size_t written;
					ctx.out_stream.write_all (
						((uint8[]) elem)[0:elem.length],
						out written
					);
				}
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
					throw new SerializableError.PROPERTY (
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

			throw new SerializableError.PROPERTY (
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
					throw new SerializableError.PROPERTY (
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

		public virtual void bin_read_prop (
			Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			this.bin_default_read_prop (ctx, prop, type_byte);
		}

		/**
		 * Stock scalar/object decode for one property.
		 *
		 * Omit overrides call this from their {@link bin_read_prop} default
		 * branch.
		 *
		 * @param ctx active bin session
		 * @param prop property metadata
		 * @param type_byte wire type byte ({@link GLib.Type} fundamental; bit 7 = array)
		 */
		public virtual void bin_default_read_prop (
			Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			var val = GLib.Value (prop.value_type);
			var width = (uint8) 0;

			switch ((GLib.Type) (type_byte & 0x7F)) {
				case GLib.Type.STRING:
					if ((type_byte & 0x80) != 0) {
						if (prop.value_type != typeof (string[])) {
							throw new SerializableError.PROPERTY (
								"prop '%s' cannot decode wire string[]",
								prop.name
							);
						}

						var count = (uint) ctx.in_stream.read_byte ();
						if ((count & 0x80) != 0) {
							count = ((count & 0x7F) << 8)
								| ctx.in_stream.read_byte ();
						}
						string[] arr = {};
						for (var i = 0; i < count; i++) {
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
							arr += (string) buf;
						}

						val = arr;
						this.set_property (prop.name, val);
						return;
					}

					if (prop.value_type != GLib.Type.STRING) {
						throw new SerializableError.PROPERTY (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
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
					val.set_string ((string) str_buf);
					this.set_property (prop.name, val);
					return;

				case GLib.Type.BOXED:
					if (prop.value_type != GLib.Type.STRING) {
						throw new SerializableError.PROPERTY (
							"prop '%s' cannot decode wire blob 0x%02X",
							prop.name,
							type_byte
						);
					}
					var blob_len = ctx.in_stream.read_uint32 ();
					var blob_buf = new uint8[blob_len + 1];
					size_t blob_read;
					ctx.in_stream.read_all (
						blob_buf[0:blob_len],
						out blob_read
					);
					blob_buf[blob_len] = 0;
					val.set_string ((string) blob_buf);
					this.set_property (prop.name, val);
					return;

				case GLib.Type.BOOLEAN:
					if (prop.value_type != GLib.Type.BOOLEAN) {
						throw new SerializableError.PROPERTY (
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
						throw new SerializableError.PROPERTY (
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
						throw new SerializableError.PROPERTY (
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
						throw new SerializableError.PROPERTY (
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
						throw new SerializableError.PROPERTY (
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
						throw new SerializableError.PROPERTY (
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
						throw new SerializableError.PROPERTY (
							"invalid flags integer width %u on prop '%s'",
							width,
							prop.name
						);
					}
					val.set_flags ((uint) ctx.in_stream.read_uint64 ());
					this.set_property (prop.name, val);
					return;

				case GLib.Type.INT:
					if (prop.value_type != GLib.Type.INT
						&& prop.value_type != GLib.Type.INT64) {
						throw new SerializableError.PROPERTY (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					width = ctx.in_stream.read_byte ();
					if (width == 1) {
						var iv = (int64) (int8) ctx.in_stream.read_byte ();
						if (prop.value_type == GLib.Type.INT64) {
							val.set_int64 (iv);
						} else {
							val.set_int ((int) iv);
						}
						this.set_property (prop.name, val);
						return;
					}
					if (width != 8) {
						throw new SerializableError.PROPERTY (
							"invalid signed integer width %u on prop '%s'",
							width,
							prop.name
						);
					}
					var i64 = ctx.in_stream.read_int64 ();
					if (prop.value_type == GLib.Type.INT64) {
						val.set_int64 (i64);
					} else {
						val.set_int ((int) i64);
					}
					this.set_property (prop.name, val);
					return;

				case GLib.Type.INT64:
					if (prop.value_type != GLib.Type.INT64) {
						throw new SerializableError.PROPERTY (
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
						throw new SerializableError.PROPERTY (
							"invalid signed integer width %u on prop '%s'",
							width,
							prop.name
						);
					}
					val.set_int64 (ctx.in_stream.read_int64 ());
					this.set_property (prop.name, val);
					return;

				case GLib.Type.UINT:
					if (prop.value_type != GLib.Type.UINT
						&& prop.value_type != GLib.Type.UINT64) {
						throw new SerializableError.PROPERTY (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					width = ctx.in_stream.read_byte ();
					if (width == 1) {
						var uv = (uint64) ctx.in_stream.read_byte ();
						if (prop.value_type == GLib.Type.UINT64) {
							val.set_uint64 (uv);
						} else {
							val.set_uint ((uint) uv);
						}
						this.set_property (prop.name, val);
						return;
					}
					if (width != 8) {
						throw new SerializableError.PROPERTY (
							"invalid unsigned integer width %u on prop '%s'",
							width,
							prop.name
						);
					}
					var u64 = ctx.in_stream.read_uint64 ();
					if (prop.value_type == GLib.Type.UINT64) {
						val.set_uint64 (u64);
					} else {
						val.set_uint ((uint) u64);
					}
					this.set_property (prop.name, val);
					return;

				case GLib.Type.UINT64:
					if (prop.value_type != GLib.Type.UINT64) {
						throw new SerializableError.PROPERTY (
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
						throw new SerializableError.PROPERTY (
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
						throw new SerializableError.PROPERTY (
							"prop '%s' cannot decode wire type 0x%02X",
							prop.name,
							type_byte
						);
					}
					var child = ctx.parse_object ();
					if (!child.get_type ().is_a (prop.value_type)) {
						throw new SerializableError.PROPERTY (
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

			if ((type_byte & 0x80) != 0) {
				throw new SerializableError.PROPERTY (
					"array prop '%s' requires a bin_read_prop override",
					prop.name
				);
			}

			throw new SerializableError.PROPERTY (
				"unsupported wire type 0x%02X on prop '%s'",
				type_byte & 0x7F,
				prop.name
			);
		}
	}
}
