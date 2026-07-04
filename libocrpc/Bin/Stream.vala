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
	 * Per-connection bin codec: I/O streams, JIT key/type maps, {{{write}}} / {{{parse}}}.
	 *
	 * Owned by {@link OLLMrpc.Transport.Connection} and {@link OLLMrpc.Client} as {{{bin}}}.
	 */
	public class Stream : GLib.Object
	{
		public GLib.DataOutputStream? out_stream { get; construct; }
		public GLib.DataInputStream? in_stream { get; construct; }

		internal string[] names = {};
		internal Gee.HashMap<string, uint16> name_to_token =
			new Gee.HashMap<string, uint16> ();

		private Gee.HashMap<string, GLib.Type> alias_to_gtype =
			new Gee.HashMap<string, GLib.Type> ();
		private Gee.HashMap<GLib.Type, string> gtype_to_alias =
			new Gee.HashMap<GLib.Type, string> ();

		public const uint16 TOKEN_REG_KEY = 0xFFFF;
		public const uint16 TOKEN_REG_TYPE = 0xFFFE;
		public const uint16 TOKEN_END = 0xFFFD;

		/**
		 * Register a wire alias on this connection's stream.
		 *
		 * Maps {@param alias} to {@param gtype} for instantiation on decode.
		 * The alias string shares the connection wire-name table with property
		 * keys. Type aliases are introduced on the wire via {@link TOKEN_REG_TYPE};
		 * property keys via {@link TOKEN_REG_KEY}. Registration order is not
		 * significant.
		 *
		 * @param alias wire type name
		 * @param gtype GObject type for that alias
		 */
		public void register (string alias, GLib.Type gtype) throws GLib.Error
		{
			if (this.alias_to_gtype.has_key (alias)) {
				GLib.error ("duplicate register of alias '%s'", alias);
			}

			this.alias_to_gtype.set (alias, gtype);
			this.gtype_to_alias.set (gtype, alias);
		}

		public Stream (
			GLib.DataInputStream? in_stream,
			GLib.DataOutputStream? out_stream
		) {
			GLib.Object (in_stream: in_stream, out_stream: out_stream);
			if (this.out_stream != null) {
				this.out_stream.set_byte_order (
					GLib.DataStreamByteOrder.BIG_ENDIAN
				);
			}
			if (this.in_stream != null) {
				this.in_stream.set_byte_order (
					GLib.DataStreamByteOrder.BIG_ENDIAN
				);
			}
		}

		public void write (Serializable obj) throws GLib.Error
		{
			this.write_gtype (obj.get_type ());
			obj.bin_write (this);
		}

		public Serializable parse () throws GLib.Error
		{
			var b = this.in_stream.read_byte ();
			if (b == 0xFF) {
				this.read_reg_gtype ();
				b = this.in_stream.read_byte ();
			}
			if ((b & 0x80) != 0) {
				GLib.error ("root parse does not accept object arrays");
			}
			if (b != (uint8) GLib.Type.OBJECT) {
				GLib.error (
					"expected object type byte, got 0x%02X",
					b
				);
			}
			return this.parse_object ();
		}

		/**
		 * Read one object body after its {@link GLib.Type.OBJECT} type byte.
		 */
		public Serializable parse_object () throws GLib.Error
		{
			var reg_b = this.in_stream.read_byte ();
			var reg_id = (uint) reg_b;
			if ((reg_b & 0x80) != 0) {
				var reg_b2 = this.in_stream.read_byte ();
				reg_id = ((uint) (reg_b & 0x7F) << 8) | reg_b2;
			}

			if (reg_id >= this.names.length) {
				GLib.error ("unknown wire name token %u", reg_id);
			}
			var alias = this.names[reg_id];
			var gtype = this.alias_to_gtype[alias];
			if (gtype == 0) {
				GLib.error ("Unrecognized type alias: %s", alias);
			}

			var obj = (Serializable) GLib.Object.new (gtype);
			obj.bin_read (this);
			return obj;
		}

		public void write_tag (string prop_name) throws GLib.Error
		{
			if (this.name_to_token.has_key (prop_name)) {
				this.out_stream.put_uint16 (this.name_to_token[prop_name]);
				return;
			}

			var id = (uint16) this.names.length;
			this.out_stream.put_uint16 (TOKEN_REG_KEY);
			this.out_stream.put_uint16 (id);

			var len = (uint8) uint.min (prop_name.length, 255);
			this.out_stream.put_byte (len);
			size_t written;
			this.out_stream.write_all (
				((uint8[]) prop_name)[0:len],
				out written
			);

			this.names += prop_name;
			this.name_to_token.set (prop_name, id);
			this.out_stream.put_uint16 (id);
		}

		internal uint16 read_tag (out string prop_name) throws GLib.Error
		{
			var t = this.in_stream.read_uint16 ();

			if (t == TOKEN_END) {
				prop_name = "";
				return t;
			}

			if (t != TOKEN_REG_KEY) {
				if (t >= this.names.length) {
					GLib.error ("unknown wire name token %u", t);
				}
				prop_name = this.names[t];
				return t;
			}

			var assigned_id = this.in_stream.read_uint16 ();
			var len = this.in_stream.read_byte ();

			var buffer = new uint8[len + 1];
			size_t read_bytes;
			this.in_stream.read_all (buffer[0:len], out read_bytes);
			buffer[len] = 0;
			prop_name = (string) buffer;

			if (assigned_id > this.names.length) {
				GLib.error (
					"wire name token %u out of sequence",
					assigned_id
				);
			}
			if (assigned_id == this.names.length) {
				this.names += prop_name;
			} else if (this.names[assigned_id] != prop_name) {
				GLib.error (
					"wire name token %u alias mismatch",
					assigned_id
				);
			}
			this.name_to_token.set (prop_name, assigned_id);
			return this.read_tag (out prop_name);
		}

		public void write_gtype (GLib.Type object_type) throws GLib.Error
		{
			var alias = this.gtype_to_alias[object_type];
			if (alias == null) {
				GLib.error (
					"Unregistered class type schema: %s",
					object_type.name ()
				);
			}

			if (!this.name_to_token.has_key (alias)) {
				var new_reg_id = (uint) this.names.length;

				this.out_stream.put_byte (0xFF);
				this.out_stream.put_byte (0xFE);
				if (new_reg_id < 128) {
					this.out_stream.put_byte ((uint8) new_reg_id);
				} else {
					this.out_stream.put_byte (
						(uint8) (0x80 | ((new_reg_id >> 8) & 0x7F))
					);
					this.out_stream.put_byte ((uint8) (new_reg_id & 0xFF));
				}

				var alias_len = (uint8) uint.min (alias.length, 255);
				this.out_stream.put_byte (alias_len);
				size_t written;
				this.out_stream.write_all (
					((uint8[]) alias)[0:alias_len],
					out written
				);

				this.names += alias;
				this.name_to_token.set (alias, (uint16) new_reg_id);
			}

			this.out_stream.put_byte ((uint8) GLib.Type.OBJECT);
			var reg_id = (uint) this.name_to_token[alias];
			if (reg_id < 128) {
				this.out_stream.put_byte ((uint8) reg_id);
				return;
			}

			this.out_stream.put_byte (
				(uint8) (0x80 | ((reg_id >> 8) & 0x7F))
			);
			this.out_stream.put_byte ((uint8) (reg_id & 0xFF));
		}

		internal void read_reg_gtype () throws GLib.Error
		{
			var b1 = this.in_stream.read_byte ();
			if (b1 != 0xFE) {
				GLib.error (
					"unexpected byte 0x%02X after 0xFF",
					b1
				);
			}

			var reg_b = this.in_stream.read_byte ();
			var assigned_id = (uint) reg_b;
			if ((reg_b & 0x80) != 0) {
				var reg_b2 = this.in_stream.read_byte ();
				assigned_id = ((uint) (reg_b & 0x7F) << 8) | reg_b2;
			}

			var len = this.in_stream.read_byte ();
			var buffer = new uint8[len + 1];
			size_t read_bytes;
			this.in_stream.read_all (buffer[0:len], out read_bytes);
			buffer[len] = 0;
			var alias = (string) buffer;

			var gtype = this.alias_to_gtype[alias];
			if (gtype == 0) {
				GLib.error ("Unrecognized type alias: %s", alias);
			}

			if (assigned_id > this.names.length) {
				GLib.error (
					"wire name token %u out of sequence",
					assigned_id
				);
			}
			if (assigned_id == this.names.length) {
				this.names += alias;
			} else if (this.names[assigned_id] != alias) {
				GLib.error (
					"wire name token %u alias mismatch",
					assigned_id
				);
			}
			this.name_to_token.set (alias, (uint16) assigned_id);
		}
	}
}
