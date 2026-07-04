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

		private Gee.HashMap<string, uint16> key_to_token =
			new Gee.HashMap<string, uint16> ();
		private Gee.HashMap<uint16, string> token_to_key =
			new Gee.HashMap<uint16, string> ();

		private Gee.HashMap<string, uint16> alias_to_token =
			new Gee.HashMap<string, uint16> ();
		private Gee.HashMap<uint16, string> token_to_alias =
			new Gee.HashMap<uint16, string> ();

		private uint16 next_key_id = 0;
		private uint16 next_type_id = 0;

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
		 * @param alias wire type name
		 * @param gtype GObject type for that alias
		 */
		public void register (string alias, GLib.Type gtype)
		{
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
			this.write_type (obj.get_type ());
			obj.bin_write (this);
		}

		public Serializable parse () throws GLib.Error
		{
			GLib.Type root_type = this.read_type ();
			var obj = (Serializable) GLib.Object.new (root_type);
			obj.bin_read (this);
			return obj;
		}

		public void write_tag (string prop_name) throws GLib.Error
		{
			if (this.key_to_token.has_key (prop_name)) {
				this.out_stream.put_uint16 (this.key_to_token.get (prop_name));
				return;
			}

			uint16 id = this.next_key_id++;
			this.out_stream.put_uint16 (TOKEN_REG_KEY);
			this.out_stream.put_uint16 (id);

			uint8 len = (uint8) uint.min (prop_name.length, 255);
			this.out_stream.put_byte (len);
			size_t written;
			this.out_stream.write_all (((uint8[]) prop_name)[0:len], out written);

			this.key_to_token.set (prop_name, id);
			this.token_to_key.set (id, prop_name);
			this.out_stream.put_uint16 (id);
		}

		internal uint16 read_tag (out string prop_name) throws GLib.Error
		{
			uint16 t = this.in_stream.read_uint16 ();

			if (t == TOKEN_END) {
				prop_name = "";
				return t;
			}

			if (t != TOKEN_REG_KEY) {
				prop_name = this.token_to_key.get (t);
				return t;
			}

			uint16 assigned_id = this.in_stream.read_uint16 ();
			uint8 len = this.in_stream.read_byte ();

			uint8[] buffer = new uint8[len + 1];
			size_t read_bytes;
			this.in_stream.read_all (buffer[0:len], out read_bytes);
			buffer[len] = 0;
			string name = (string) buffer;

			this.key_to_token.set (name, assigned_id);
			this.token_to_key.set (assigned_id, name);
			return this.read_tag (out prop_name);
		}

		public void write_type (GLib.Type object_type) throws GLib.Error
		{
			string alias = this.gtype_to_alias.get (object_type);
			if (alias == null) {
				GLib.error (
					"Unregistered class type schema: %s",
					object_type.name ()
				);
			}

			if (this.alias_to_token.has_key (alias)) {
				this.out_stream.put_uint16 (this.alias_to_token.get (alias));
				return;
			}

			uint16 id = this.next_type_id++;
			this.out_stream.put_uint16 (TOKEN_REG_TYPE);
			this.out_stream.put_uint16 (id);

			uint8 len = (uint8) uint.min (alias.length, 255);
			this.out_stream.put_byte (len);
			size_t written;
			this.out_stream.write_all (((uint8[]) alias)[0:len], out written);

			this.alias_to_token.set (alias, id);
			this.token_to_alias.set (id, alias);
			this.out_stream.put_uint16 (id);
		}

		public GLib.Type read_type () throws GLib.Error
		{
			uint16 t = this.in_stream.read_uint16 ();

			if (t != TOKEN_REG_TYPE) {
				string active_alias = this.token_to_alias.get (t);
				return this.alias_to_gtype.get (active_alias);
			}

			uint16 assigned_id = this.in_stream.read_uint16 ();
			uint8 len = this.in_stream.read_byte ();

			uint8[] buffer = new uint8[len + 1];
			size_t read_bytes;
			this.in_stream.read_all (buffer[0:len], out read_bytes);
			buffer[len] = 0;
			string alias = (string) buffer;

			GLib.Type gtype = this.alias_to_gtype.get (alias);
			if (gtype == 0) {
				GLib.error ("Unrecognized type alias: %s", alias);
			}

			this.alias_to_token.set (alias, assigned_id);
			this.token_to_alias.set (assigned_id, alias);
			return this.read_type ();
		}
	}
}
