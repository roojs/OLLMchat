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

namespace OLLMrpc
{
	/**
	 * Inbound RPC envelope — matching {@link Request.id}, plus result or error.
	 *
	 * After {@link Client.call}, check {@link error} first. Successful
	 * calls put objects in {@link result} (never null; omit on the wire
	 * when empty) and optional scalars in {@link args} (same
	 * {@link Gee.ArrayList} of boxed {@link GLib.Value} as
	 * {@link Request.args}). File.read-style string payloads may use
	 * {@link msg} / {@link msg_encode}.
	 *
	 * == Usage Examples ==
	 *
	 * === Check error ===
	 *
	 * {{{
	 * var resp = yield rpc.call(req);
	 * if (resp.error != null)
	 *     GLib.warning("%s", resp.error.message);
	 * }}}
	 *
	 * === Object result ===
	 *
	 * {{{
	 * foreach (var obj in resp.result)
	 *     stdout.printf("%s\n", obj.get_type().name());
	 * }}}
	 *
	 * === Positional args ===
	 *
	 * {{{
	 * if (resp.args.size > 0)
	 *     stdout.printf("%d\n", resp.args.get(0).get_int());
	 * }}}
	 *
	 * @see Request
	 * @see Client
	 */
	public class Response : GLib.Object, Bin.Serializable
	{
		/**
		 * Matching {@link Request.id} for this reply.
		 */
		public int id { get; set; default = 0; }
		/**
		 * Failure when set. Check this before {@link result} or {@link args}.
		 *
		 * Null means success. {@link OLLMrpc.Error} is a wire object, not
		 * {@link GLib.Error}.
		 */
		public Error? error { get; set; default = null; }
		/**
		 * Object list on the wire (length 0, 1, or N).
		 *
		 * Never null. Single objects use one element. Omitted when empty.
		 * With {@link Transport.Connection.live_handles}, a non-Serializable
		 * instance is a lease id, not a property dump.
		 */
		public Gee.ArrayList<GLib.Object> result { get; set; default = new Gee.ArrayList<GLib.Object> (); }
		/**
		 * Positional returns (daemon → client), GIR order.
		 *
		 * Empty list is omitted on the bin socket. A returned GObject
		 * uses {@link result}, not this list. Do not put scalars in
		 * {@link msg}.
		 *
		 * {@link Gee.ArrayList} cannot store {@link GLib.Value} (a struct).
		 * valac requires a boxed element type. That is boxing, not
		 * optional or null returns.
		 *
		 * == Example ==
		 *
		 * {{{
		 * var n = GLib.Value(typeof(int));
		 * n.set_int(0);
		 * resp.args.add(n);
		 * }}}
		 */
		public Gee.ArrayList<GLib.Value?> args { get; set; default = new Gee.ArrayList<GLib.Value?>(); }
		/**
		 * Scalar string payload (e.g. File.read). Empty when unused.
		 *
		 * Typelib scalar returns use {@link args}, not this property.
		 */
		public string msg { get; set; default = ""; }
		/**
		 * Encoding of {@link msg} for File.read.
		 *
		 * ''0'' = plain UTF-8 (is_text). ''1'' = base64 (not is_text).
		 */
		public int msg_encode { get; set; default = 0; }

		/**
		 * Register the ''Response'' wire alias.
		 *
		 * Call before connect or listen. {@link Client} already registers
		 * the envelope types.
		 */
		public static void rpc_register()
		{
			Bin.register("Response", typeof(Response));
		}

		/**
		 * Look up a GObject property by name.
		 *
		 * Used by {@link Bin.Serializable} encode and decode.
		 *
		 * @param name property name (hyphenated on the wire)
		 * @return the param spec, or null if this type has no such property
		 */
		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		/**
		 * Encode one property.
		 *
		 * Omits empty {@link result} and {@link args}. Live GObjects
		 * write a lease id, not a property dump.
		 *
		 * @param ctx active bin session
		 * @param prop property being written
		 * @throws GLib.Error on encode failure
		 */
		public override void bin_write_prop (
			Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "result":
					if (this.result.size == 0) {
						return;
					}
					ctx.write_tag (prop.name);
					ctx.write_gtype (
						this.result.get (0).get_type (),
						(uint8) GLib.Type.OBJECT | 0x80
					);
					if (this.result.size < 128) {
						ctx.out_stream.put_byte ((uint8) this.result.size);
					} else {
						ctx.out_stream.put_byte (
							(uint8) (0x80 | ((this.result.size >> 8) & 0x7F))
						);
						ctx.out_stream.put_byte (
							(uint8) (this.result.size & 0xFF)
						);
					}
					foreach (var child in this.result) {
						if (!child.get_type().is_a(typeof(Bin.Serializable))
							&& ctx.connection.live_handles) {
							var ptr = (uint64) (void*) child;
							ctx.out_stream.put_uint64(
								(uint64) ctx.connection.lease_ids.get(
									(int) (ptr >> 32)).get((int) ptr));
							ctx.out_stream.put_uint16(Bin.Stream.TOKEN_END);
							continue;
						}
						((Bin.Serializable) child).bin_write (ctx);
					}
					return;
				case "args":
					if (this.args.size == 0) {
						return;
					}
					ctx.write_tag(prop.name);
					ctx.out_stream.put_byte((uint8) GLib.Type.INVALID | 0x80);
					if (this.args.size < 128) {
						ctx.out_stream.put_byte((uint8) this.args.size);
					} else {
						ctx.out_stream.put_byte(
							(uint8) (0x80 | ((this.args.size >> 8) & 0x7F))
						);
						ctx.out_stream.put_byte((uint8) (this.args.size & 0xFF));
					}
					foreach (var val in this.args) {
						Bin.StreamValue.write(ctx, val);
					}
					return;
				default:
					this.bin_default_write_prop (ctx, prop);
					return;
			}
		}

		/**
		 * Decode one property.
		 *
		 * {@link result} is an object array. {@link args} is ''ANY[]''
		 * (same encoding as {@link Request.args}).
		 *
		 * @param ctx active bin session
		 * @param prop property being read
		 * @param type_byte wire type byte already consumed
		 * @throws GLib.Error on decode failure
		 */
		public override void bin_read_prop (
			Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			switch (prop.name) {
				case "result":
					if ((type_byte & 0x80) == 0
						|| (type_byte & 0x7F) != GLib.Type.OBJECT) {
						this.bin_default_read_prop (ctx, prop, type_byte);
						return;
					}
					this.result = ctx.parse_object_array ();
					return;
				case "args":
					var n = ctx.in_stream.read_byte();
					var count = n & 0x7F;
					if ((n & 0x80) != 0) {
						count = (count << 8) | ctx.in_stream.read_byte();
					}
					for (var i = 0; i < count; i++) {
						var elem = ctx.in_stream.read_byte();
						this.args.add(Bin.StreamValue.read(ctx, elem));
					}
					return;
				default:
					this.bin_default_read_prop (ctx, prop, type_byte);
					return;
			}
		}
	}
}
