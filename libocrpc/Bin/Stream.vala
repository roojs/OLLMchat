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

		private Gee.HashMap<string, uint16> name_to_token =
			new Gee.HashMap<string, uint16> ();
		private Gee.HashMap<uint16, string> token_to_name =
			new Gee.HashMap<uint16, string> ();

		private uint16 next_token_id = 0;

		private Gee.HashMap<string, GLib.Type> alias_to_gtype =
			new Gee.HashMap<string, GLib.Type> ();
		private Gee.HashMap<GLib.Type, string> gtype_to_alias =
			new Gee.HashMap<GLib.Type, string> ();

		private int pending_byte = -1;

		public const uint16 TOKEN_REG_KEY = 0xFFFF;
		public const uint16 TOKEN_END = 0xFFFD;

		/**
		 * Register a wire alias on this connection's stream.
		 *
		 * Maps {@param alias} to {@param gtype} for instantiation on decode.
		 * The alias string shares the connection's wire-name token table with
		 * property keys; tokens are learned on the wire via {@link TOKEN_REG_KEY}.
		 * Registration order is not significant.
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
			while (this.try_consume_name_intro ()) {
			}

			var b = this.read_byte_or_pending ();
			if ((b & 0x80) != 0) {
				GLib.error ("root parse does not accept object arrays");
			}
			if (b != (uint8) GLib.Type.OBJECT) {
				GLib.error (
					"expected object type byte, got 0x%02X",
					b
				);
			}
			return this.parse_object_after_type_byte ();
		}

		/**
		 * Read one object body after its {@link GLib.Type.OBJECT} type byte.
		 *
		 * The {@code 0x50} type byte must already have been consumed by the caller
		 * (e.g. {@link bin_read_prop} on a nested object property).
		 */
		public Serializable parse_object () throws GLib.Error
		{
			return this.parse_object_after_type_byte ();
		}

		public void write_tag (string prop_name) throws GLib.Error
		{
			if (this.name_to_token.has_key (prop_name)) {
				this.out_stream.put_uint16 (this.name_to_token.get (prop_name));
				return;
			}

			this.write_name_intro (prop_name);
			this.out_stream.put_uint16 (this.name_to_token.get (prop_name));
		}

		internal uint16 read_tag (out string prop_name) throws GLib.Error
		{
			var t = this.in_stream.read_uint16 ();

			if (t == TOKEN_END) {
				prop_name = "";
				return t;
			}

			if (t != TOKEN_REG_KEY) {
				prop_name = this.token_to_name.get (t);
				return t;
			}

			var assigned_id = this.in_stream.read_uint16 ();
			var len = this.in_stream.read_byte ();

			var buffer = new uint8[len + 1];
			size_t read_bytes;
			this.in_stream.read_all (buffer[0:len], out read_bytes);
			buffer[len] = 0;
			prop_name = (string) buffer;

			this.name_to_token.set (prop_name, assigned_id);
			this.token_to_name.set (assigned_id, prop_name);
			return this.read_tag (out prop_name);
		}

		public void write_gtype (GLib.Type object_type) throws GLib.Error
		{
			var alias = this.gtype_to_alias.get (object_type);
			if (alias == null) {
				GLib.error (
					"Unregistered class type schema: %s",
					object_type.name ()
				);
			}

			if (!this.name_to_token.has_key (alias)) {
				this.write_name_intro (alias);
				this.out_stream.put_uint16 (this.name_to_token.get (alias));
			}

			this.out_stream.put_byte ((uint8) GLib.Type.OBJECT);
			this.out_stream.put_uint16 (this.name_to_token.get (alias));
		}

		internal void write_name_intro (string name) throws GLib.Error
		{
			var id = this.next_token_id++;
			this.out_stream.put_uint16 (TOKEN_REG_KEY);
			this.out_stream.put_uint16 (id);

			var len = (uint8) uint.min (name.length, 255);
			this.out_stream.put_byte (len);
			size_t written;
			this.out_stream.write_all (((uint8[]) name)[0:len], out written);

			this.name_to_token.set (name, id);
			this.token_to_name.set (id, name);
		}

		internal bool try_consume_name_intro () throws GLib.Error
		{
			var b1 = this.read_byte_or_pending ();
			if (b1 != 0xFF) {
				this.pending_byte = b1;
				return false;
			}

			var b2 = this.in_stream.read_byte ();
			if (b2 != 0xFF) {
				this.pending_byte = b2;
				return false;
			}

			this.read_name_intro_payload ();
			return true;
		}

		internal void read_name_intro_payload () throws GLib.Error
		{
			var assigned_id = this.in_stream.read_uint16 ();
			var len = this.in_stream.read_byte ();

			var buffer = new uint8[len + 1];
			size_t read_bytes;
			this.in_stream.read_all (buffer[0:len], out read_bytes);
			buffer[len] = 0;
			var name = (string) buffer;

			this.in_stream.read_uint16 ();

			this.name_to_token.set (name, assigned_id);
			this.token_to_name.set (assigned_id, name);
		}

		private Serializable parse_object_after_type_byte () throws GLib.Error
		{
			var token = this.in_stream.read_uint16 ();
			var alias = this.token_to_name.get (token);
			if (alias == null) {
				GLib.error ("unknown wire name token %u", token);
			}
			var gtype = this.alias_to_gtype.get (alias);
			if (gtype == 0) {
				GLib.error ("Unrecognized type alias: %s", alias);
			}

			var obj = (Serializable) GLib.Object.new (gtype);
			obj.bin_read (this);
			return obj;
		}

		internal uint8 read_byte () throws GLib.Error
		{
			return this.read_byte_or_pending ();
		}

		private uint8 read_byte_or_pending () throws GLib.Error
		{
			if (this.pending_byte >= 0) {
				var b = (uint8) this.pending_byte;
				this.pending_byte = -1;
				return b;
			}

			return this.in_stream.read_byte ();
		}
	}
}
