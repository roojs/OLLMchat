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
	 * Inbound RPC envelope — matching {@link Request.id}, plus retval or error.
	 *
	 * After {@link Client.call} returns, the call succeeded.
	 * {@link Client.call} throws on failure. Successful
	 * calls put the C return in {@link retval} (omit on the wire
	 * when unset or an empty {@link Gee.ArrayList}). OUT / INOUT
	 * scalars go in {@link args} (same
	 * {@link Gee.ArrayList} of boxed {@link GLib.Value} as
	 * {@link Request.args}). File.read-style string payloads may use
	 * {@link msg} / {@link msg_encode}.
	 *
	 * == Usage Examples ==
	 *
	 * === Call ===
	 *
	 * {{{
	 * var resp = yield rpc.call(req);
	 * }}}
	 *
	 * === Retval ===
	 *
	 * {{{
	 * stdout.printf("%d\n", resp.retval.get_int());
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
		 * Failure when set. {@link Client.call} throws this as
		 * {@link GLib.Error}; it is not returned to the caller.
		 *
		 * Null means success. {@link OLLMrpc.Error} is a wire object, not
		 * {@link GLib.Error}.
		 */
		public Error? error { get; set; default = null; }
		/**
		 * Typed return ({@link GLib.Value}).
		 *
		 * Unset ({@link GLib.Type.INVALID}) is omitted on the wire. A
		 * number or string uses the same {@link Bin.StreamValue}
		 * encoding as {@link args} elements. A GObject is one object.
		 * A {@link Gee.ArrayList} is an object array. Live GObjects
		 * write a lease id when {@link Transport.Connection.live_handles}
		 * is on.
		 *
		 * == Example ==
		 *
		 * {{{
		 * var n = GLib.Value(typeof(int));
		 * n.set_int(3);
		 * resp.retval = n;
		 * }}}
		 */
		public GLib.Value retval { get; set; }
		/**
		 * Positional returns (daemon → client), GIR order.
		 *
		 * Empty list is omitted on the bin socket. The C return uses
		 * {@link retval}, not this list. This list is OUT / INOUT only.
		 * Do not put scalars in {@link msg}.
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
		 * Typelib scalar returns use {@link retval}, not this property.
		 */
		public string msg { get; set; default = ""; }
		/**
		 * Encoding of {@link msg} for File.read.
		 *
		 * ''0'' = plain UTF-8 (is_text). ''1'' = base64 (not is_text).
		 */
		public int msg_encode { get; set; default = 0; }
		/** Filled by client {@link Live.BufferStream.take_pending}; null on send. */
		public Live.Buffer? buffer { get; internal set; default = null; }

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
		 * Omits unset {@link retval} and empty {@link args}. Live GObjects
		 * write a lease id, not a property dump.
		 *
		 * @param ctx active bin session
		 * @param prop property being written
		 * @throws GLib.Error on encode failure
		 */
		public override void bin_write_prop(
			Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "buffer":
					return;
				case "retval":
					if (this.retval.type() == GLib.Type.INVALID) {
						return;
					}
					if (this.retval.type().is_a(typeof(Gee.ArrayList))
						&& ((Gee.ArrayList<GLib.Object>) this.retval.get_object()).size == 0) {
						return;
					}
					ctx.write_tag(prop.name);
					Bin.StreamValue.write(ctx, this.retval);
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
							(uint8) (0x80 | ((this.args.size >> 8) & 0x7F)));
						ctx.out_stream.put_byte((uint8) (this.args.size & 0xFF));
					}
					foreach (var val in this.args) {
						Bin.StreamValue.write(ctx, val);
					}
					return;
				default:
					this.bin_default_write_prop(ctx, prop);
					return;
			}
		}

		/**
		 * Decode one property.
		 *
		 * {@link retval} uses {@link Bin.StreamValue}. {@link args} is
		 * ''ANY[]'' (same encoding as {@link Request.args}).
		 *
		 * @param ctx active bin session
		 * @param prop property being read
		 * @param type_byte wire type byte already consumed
		 * @throws GLib.Error on decode failure
		 */
		public override void bin_read_prop(
			Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			switch (prop.name) {
				case "buffer":
					return;
				case "retval":
					this.retval = Bin.StreamValue.read(ctx, type_byte);
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
					this.bin_default_read_prop(ctx, prop, type_byte);
					return;
			}
		}
	}
}
