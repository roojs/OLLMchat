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
	/** Process-wide wire alias → GType for bin encode/decode. */
	public static Gee.HashMap<string, GLib.Type> alias_to_gtype;

	/** Process-wide GType → wire alias. */
	internal static Gee.HashMap<GLib.Type, string> gtype_to_alias;

	/**
	 * {@link Stream} wire / registration failures (throw/catch).
	 *
	 * Not {@link GLib.Error} abort — throw StreamError from
	 * {@link Stream} encode/decode paths.
	 */
	public errordomain StreamError
	{
		PROTOCOL,
		REGISTRATION
	}

	/**
	 * Map a wire alias string to a local GObject type (process-wide).
	 *
	 * Both peers register the same alias strings; each maps to its own
	 * local type. Call before connect/listen (usually from each type's
	 * ''rpc_register()''). Property keys do not need register — they JIT
	 * on the connection via {@link Stream}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Bin.register("Pair", typeof(Pair));
	 * OLLMrpc.Bin.register("File", typeof(OLLMfiles.V2.File));
	 * }}}
	 *
	 * @param alias wire type name
	 * @param gtype GObject type for that alias
	 */
	public static void register(
		string alias,
		GLib.Type gtype
	) throws GLib.Error
	{
		if (alias_to_gtype == null) {
			alias_to_gtype = new Gee.HashMap<string, GLib.Type>();
			gtype_to_alias = new Gee.HashMap<GLib.Type, string>();
		}
		if (alias_to_gtype.has_key(alias)) {
			throw new StreamError.REGISTRATION(
				"duplicate register of alias '%s'",
				alias
			);
		}

		alias_to_gtype.set(alias, gtype);
		gtype_to_alias.set(gtype, alias);
	}

	/**
	 * Per-connection bin codec — write and parse {@link Serializable} objects.
	 *
	 * Owns the I/O streams and even/odd wire-name tables for one channel.
	 * {@link OLLMrpc.Client} and {@link OLLMrpc.Transport.Connection} keep one
	 * Stream for the connection lifetime. Call {@link write} to send a root
	 * object; {@link parse} to receive one.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Bin.register("Pair", typeof(Pair));
	 *
	 * var mem = new GLib.MemoryOutputStream.resizable();
	 * var out_stream = new GLib.DataOutputStream(mem);
	 * var write_bin = new OLLMrpc.Bin.Stream(null, out_stream);
	 * write_bin.write(new Pair() { name = "alpha", count = 42 });
	 * out_stream.close();
	 *
	 * var read_bin = new OLLMrpc.Bin.Stream(
	 *     new GLib.DataInputStream(
	 *         new GLib.MemoryInputStream.from_bytes(mem.steal_as_bytes())),
	 *     null);
	 * var parsed = read_bin.parse() as Pair;
	 * }}}
	 *
	 * Pass ''null'' for the unused direction in memory-only tests.
	 *
	 * @see Serializable
	 * @see register
	 */
	public class Stream : GLib.Object
	{
		public GLib.DataOutputStream? out_stream { get; construct; }
		public GLib.DataInputStream? in_stream { get; construct; }

		/** Copied from {@link Json.mode} for GObject decode on this stream. */
		public Mode mode { get; set; default = Mode.EXPLICIT; }

		internal string[] client_names = {};
		internal string[] server_names = {};
		internal Gee.HashMap<string, uint16> name_to_token =
			new Gee.HashMap<string, uint16>();
		/**
		 * True on the daemon/accepting end — allocates odd wire name tokens.
		 * Client end leaves this false and allocates even tokens.
		 */
		public bool is_server { get; construct; default = false; }

		public bool live_handles { get; set; default = false; }

		public const uint16 TOKEN_REG_KEY = 0xFFFF;
		public const uint16 TOKEN_REG_TYPE = 0xFFFE;
		public const uint16 TOKEN_END = 0xFFFD;

		public Stream(
			GLib.DataInputStream? in_stream,
			GLib.DataOutputStream? out_stream,
			bool is_server = false
		) {
			GLib.Object(
				in_stream: in_stream,
				out_stream: out_stream,
				is_server: is_server
			);
			if (this.out_stream != null) {
				this.out_stream.set_byte_order(GLib.DataStreamByteOrder.BIG_ENDIAN);
			}
			if (this.in_stream != null) {
				this.in_stream.set_byte_order(GLib.DataStreamByteOrder.BIG_ENDIAN);
			}
		}

		public void write(Serializable obj) throws GLib.Error
		{
			this.write_gtype(obj.get_type());
			obj.bin_write(this);
		}

		public Serializable parse() throws GLib.Error
		{
			var b = this.in_stream.read_byte();
			if (b == 0xFF) {
				this.read_reg_gtype();
				b = this.in_stream.read_byte();
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
			return this.parse_object();
		}

		/**
		 * Read one object body after its {@link GLib.Type.OBJECT} type byte.
		 *
		 * When object_type is set (homogeneous object arrays), skip
		 * {@link read_gtype} and decode the property stream for that class.
		 * When wire {@link GLib.Object} is anonymous, decode as expected_type
		 * when that type implements {@link Serializable}.
		 *
		 * @param object_type element class when already read from an array header
		 * @param expected_type GObject property type for anonymous nested objects
		 */
		public Serializable parse_object(
			GLib.Type object_type = GLib.Type.INVALID,
			GLib.Type expected_type = GLib.Type.INVALID
		) throws GLib.Error
		{
			var wire_gtype = object_type != GLib.Type.INVALID
				? object_type
				: this.read_gtype();
			var decode_type = wire_gtype;
			if (wire_gtype == typeof(GLib.Object)
				&& expected_type != GLib.Type.INVALID
				&& expected_type.is_a(typeof(Serializable))) {
				decode_type = expected_type;
			}
			var obj = (Serializable) GLib.Object.new(decode_type);
			obj.bin_read(this);
			return obj;
		}

		/**
		 * Homogeneous object-array body after wire byte ''0xD0'': element class,
		 * count, then one property stream per element.
		 *
		 * @return decoded elements
		 */
		public Gee.ArrayList<GLib.Object> parse_object_array()
			throws GLib.Error
		{
			var elem_gtype = this.read_gtype();
			var count = (uint) this.in_stream.read_byte();
			if ((count & 0x80) != 0) {
				count = ((count & 0x7F) << 8) | this.in_stream.read_byte();
			}
			var list = new Gee.ArrayList<GLib.Object>();
			for (var i = 0u; i < count; i++) {
				list.add(this.parse_object(elem_gtype));
			}
			return list;
		}

		public void write_tag(string prop_name) throws GLib.Error
		{
			if (this.name_to_token.has_key(prop_name)) {
				this.out_stream.put_uint16(this.name_to_token.get(prop_name));
				return;
			}

			var local = (uint16) (this.is_server
				? this.server_names.length
				: this.client_names.length);
			var wire = this.is_server ? (uint16) (local * 2 + 1) : (uint16) (local * 2);
			this.out_stream.put_uint16(TOKEN_REG_KEY);
			this.out_stream.put_uint16(wire);

			var len = (uint8) uint.min(prop_name.length, 255);
			size_t written;
			this.out_stream.put_byte(len);
			this.out_stream.write_all(((uint8[]) prop_name)[0:len], out written);

			if (this.is_server) {
				this.server_names += prop_name;
			} else {
				this.client_names += prop_name;
			}
			this.name_to_token.set(prop_name, wire);
			this.out_stream.put_uint16(wire);
		}

		internal uint16 read_tag(out string prop_name) throws GLib.Error
		{
			var t = this.in_stream.read_uint16();

			if (t == TOKEN_END) {
				prop_name = "";
				return t;
			}

			if (t != TOKEN_REG_KEY) {
				var server = (t & 1) != 0;
				var local = (uint16) (t / 2);
				var table = server ? this.server_names : this.client_names;
				if (local >= table.length) {
					throw new StreamError.PROTOCOL(
						"unknown wire name token %u",
						t
					);
				}
				prop_name = table[local];
				return t;
			}

			var assigned_id = this.in_stream.read_uint16();
			var len = this.in_stream.read_byte();

			var buffer = new uint8[len + 1];
			size_t read_bytes;
			this.in_stream.read_all(buffer[0:len], out read_bytes);
			buffer[len] = 0;
			prop_name = (string) buffer;

			var server = (assigned_id & 1) != 0;
			var local = (uint16) (assigned_id / 2);
			var table = server ? this.server_names : this.client_names;
			if (local > table.length) {
				throw new StreamError.PROTOCOL(
					"wire name token %u out of sequence",
					assigned_id
				);
			}
			if (local < table.length && table[local] != prop_name) {
				throw new StreamError.PROTOCOL(
					"wire name token %u alias mismatch",
					assigned_id
				);
			}
			if (local == table.length) {
				if (server) {
					this.server_names += prop_name;
				} else {
					this.client_names += prop_name;
				}
			}
			this.name_to_token.set(prop_name, assigned_id);
			return this.read_tag(out prop_name);
		}

		public void write_gtype(
			GLib.Type object_type,
			uint8 type_byte = (uint8) GLib.Type.OBJECT
		) throws GLib.Error
		{
			if ((type_byte & 0x7F) != (uint8) GLib.Type.OBJECT) {
				throw new StreamError.PROTOCOL(
					"write_gtype type_byte 0x%02X is not object",
					type_byte
				);
			}

			this.write_reg_gtype(object_type);

			this.out_stream.put_byte(type_byte);
			var reg_id = (uint) this.name_to_token.get(
				gtype_to_alias.get(object_type)
			);
			if (reg_id < 128) {
				this.out_stream.put_byte((uint8) reg_id);
				return;
			}

			this.out_stream.put_byte((uint8) (0x80 | ((reg_id >> 8) & 0x7F)));
			this.out_stream.put_byte((uint8) (reg_id & 0xFF));
		}

		/**
		 * Introduce a type alias on the wire ({@link TOKEN_REG_TYPE}).
		 */
		internal void write_reg_gtype(GLib.Type object_type) throws GLib.Error
		{
			if (!gtype_to_alias.has_key(object_type)) {
				throw new StreamError.REGISTRATION(
					"Unregistered class type schema: %s",
					object_type.name()
				);
			}

			var alias = gtype_to_alias.get(object_type);
			if (this.name_to_token.has_key(alias)) {
				return;
			}

			var local = (uint) (this.is_server
				? this.server_names.length
				: this.client_names.length);
			var wire = this.is_server
				? (uint16) (local * 2 + 1)
				: (uint16) (local * 2);

			this.out_stream.put_byte(0xFF);
			this.out_stream.put_byte(0xFE);
			if (wire < 128) {
				this.out_stream.put_byte((uint8) wire);
			} else {
				this.out_stream.put_byte((uint8) (0x80 | ((wire >> 8) & 0x7F)));
				this.out_stream.put_byte((uint8) (wire & 0xFF));
			}

			this.out_stream.put_byte(
				(uint8) uint.min(alias.length, 255)
			);
			size_t written;
			this.out_stream.write_all(
				((uint8[]) alias)[0:uint.min(alias.length, 255)],
				out written
			);

			if (this.is_server) {
				this.server_names += alias;
			} else {
				this.client_names += alias;
			}
			this.name_to_token.set(alias, wire);
		}

		/**
		 * Read reg_id after an object type byte; return registered gtype.
		 */
		public GLib.Type read_gtype() throws GLib.Error
		{
			var reg_b = this.in_stream.read_byte();
			var reg_id = (uint) reg_b;
			if ((reg_b & 0x80) != 0) {
				reg_id = ((uint) (reg_b & 0x7F) << 8) | this.in_stream.read_byte();
			}

			var server = (reg_id & 1) != 0;
			var local = (uint16) (reg_id / 2);
			var table = server ? this.server_names : this.client_names;
			if (local >= table.length) {
				throw new StreamError.PROTOCOL(
					"unknown wire name token %u",
					reg_id
				);
			}
			if (!alias_to_gtype.has_key(table[local])) {
				throw new StreamError.REGISTRATION(
					"Unrecognized type alias: %s",
					table[local]
				);
			}

			return alias_to_gtype.get(table[local]);
		}

		internal void read_reg_gtype() throws GLib.Error
		{
			var b1 = this.in_stream.read_byte();
			if (b1 != 0xFE) {
				throw new StreamError.PROTOCOL(
					"unexpected byte 0x%02X after 0xFF",
					b1
				);
			}

			var reg_b = this.in_stream.read_byte();
			var assigned_id = (uint) reg_b;
			if ((reg_b & 0x80) != 0) {
				assigned_id = ((uint) (reg_b & 0x7F) << 8) | this.in_stream.read_byte();
			}

			var len = this.in_stream.read_byte();
			var buffer = new uint8[len + 1];
			size_t read_bytes;
			this.in_stream.read_all(buffer[0:len], out read_bytes);
			buffer[len] = 0;
			var alias = (string) buffer;

			if (!alias_to_gtype.has_key(alias)) {
				throw new StreamError.REGISTRATION(
					"Unrecognized type alias: %s",
					alias
				);
			}

			var server = (assigned_id & 1) != 0;
			var local = (uint16) (assigned_id / 2);
			var table = server ? this.server_names : this.client_names;
			if (local > table.length) {
				throw new StreamError.PROTOCOL(
					"wire name token %u out of sequence",
					assigned_id
				);
			}
			if (local < table.length && table[local] != alias) {
				throw new StreamError.PROTOCOL(
					"wire name token %u alias mismatch",
					assigned_id
				);
			}
			if (local == table.length) {
				if (server) {
					this.server_names += alias;
				} else {
					this.client_names += alias;
				}
			}
			this.name_to_token.set(alias, (uint16) assigned_id);
		}
	}
}
