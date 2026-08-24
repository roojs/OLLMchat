/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMrpc
{
	/**
	 * Outbound RPC envelope (one root object per call).
	 *
	 * Set ''method'' to the wire handler name
	 * (''RPC-Object.method'' for daemons; hyphen nested
	 * namespaces like ''RPC-Live-Remote.ref''; or a REST
	 * path for HTTP). Attach a {@link CallParam} subclass on
	 * ''param'', or positional {@link GLib.Value}s on ''args''
	 * (omit when empty). For typed HTTP results, set
	 * ''result_type'' before {@link Client.call}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var req = new OLLMrpc.Request() {
	 *     method = "RPC-Folder.fetch_files",
	 *     param = new OLLMfilesd.FolderParams() {
	 *         path = "/home/user/project"
	 *     },
	 *     result_type = typeof(OLLMfilesd.FileArray)
	 * };
	 * var resp = yield rpc.call(req);
	 * if (resp.error != null) {
	 *     GLib.error("%s", resp.error.message);
	 * }
	 * }}}
	 *
	 * @see Client
	 * @see CallParam
	 * @see Response
	 */
	public class Request : GLib.Object, Bin.Serializable
	{
		/** Wire object prefix → handler singleton (server dispatch). */
		public static Gee.HashMap<string, GLib.Object> handlers;

		/**
		 * Wire object prefix → {@link GLib.Type} of the handler's param bag
		 * (subclass of {@link CallParam}).
		 */
		public static Gee.HashMap<GLib.Type, GLib.Type> param_types;

		public int id { get; set; }
		public string method { get; set; default = ""; }

		/**
		 * Typed request arguments (client → daemon).
		 *
		 * Client: assign the registered param type for the target object.
		 * Server: populated by {@link Bin.Serializable} decode on the wire.
		 */
		public CallParam param { get; set; default = new CallParam(); }

		/**
		 * Positional arguments (client → daemon), GIR / C order.
		 *
		 * Empty list is omitted on the bin socket. Current callers that
		 * only set {@link param} never send this property. Direction is
		 * not on the wire — the handler or typelib knows the signature.
		 *
		 * {@link Gee.ArrayList} cannot store {@link GLib.Value} (a struct).
		 * valac requires a boxed element type. That is boxing, not
		 * optional or null arguments. An empty list means no positional
		 * args.
		 *
		 * == Example ==
		 *
		 * {{{
		 * var text = GLib.Value(typeof(string));
		 * text.set_string("hi");
		 * req.args.add(text);
		 * }}}
		 */
		public Gee.ArrayList<GLib.Value?> args { get; set; default = new Gee.ArrayList<GLib.Value?>(); }

		/**
		 * Row in {@link Transport.Connection.leases} for a typelib method.
		 *
		 * ''0'' means none (constructors, CallParam-only calls). Omitted
		 * on the bin socket when ''0''. Not {@link Live.RemoteParams.object_id}
		 * — that name stays on the CallParam bags.
		 */
		public uint64 lease_id { get; set; default = 0; }

		/**
		 * HTTP client only: root JSON object {@link GLib.Type} for
		 * {@link Response.result}. Not serialized on the bin socket.
		 */
		public GLib.Type result_type { get; set; default = GLib.Type.INVALID; }

		/** Set by the server before {@link dispatch}. */
		public Transport.Connection connection { get; set; }

		public static void rpc_register()
		{
			Bin.register("Request", typeof(Request));
		}

		/**
		 * Register a server dispatch handler and its params {@link GLib.Type}.
		 *
		 * @param name wire object prefix (e.g. RPC-Folder)
		 * @param target live singleton with call_* signals
		 * @param param_type GObject type for wire params (extends {@link CallParam})
		 */
		public static void register(
			string name,
			GLib.Object target,
			GLib.Type param_type
		) {
			if (handlers == null) {
				handlers = new Gee.HashMap<string, GLib.Object>();
				param_types = new Gee.HashMap<GLib.Type, GLib.Type>();
			}
			handlers.set(name, target);
			param_types.set(target.get_type(), param_type);
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public override void bin_write_prop (
			Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "connection":
				case "result-type":
					return;
				case "lease-id":
					if (this.lease_id == 0) {
						return;
					}
					this.bin_default_write_prop(ctx, prop);
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

		public override void bin_read_prop (
			Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			switch (prop.name) {
				case "connection":
				case "result-type":
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

		/**
		 * Route this request to the matching call_* signal.
		 *
		 * @return true when a handler signal was emitted
		 */
		public bool dispatch()
		{
			if (this.connection == null) {
				GLib.critical("RPC dispatch: connection not set");
				return false;
			}
			if (this.method.length == 0) {
				GLib.critical("RPC dispatch: method not set");
				return false;
			}

			var dot = this.method.index_of_char('.');
			if (dot < 1 || dot == this.method.length - 1) {
				GLib.critical(
					"RPC dispatch: method must be RPC-Object.method, got '%s'",
					this.method
				);
				return false;
			}

			var object_name = this.method[0:dot];
			var method_name = this.method.substring(dot + 1);

			if (handlers != null && handlers.has_key(object_name)) {
				var handler = handlers.get(object_name);
				var signal_name = "call_" + method_name.replace(".", "_");
				if (GLib.Signal.lookup(signal_name, handler.get_type()) == 0) {
					GLib.critical(
						"RPC dispatch: no signal call_%s on %s for %s",
						method_name.replace(".", "_"),
						object_name,
						this.method
					);
					return false;
				}
				GLib.debug("emit %s id=%d", signal_name, this.id);
				GLib.Signal.emit_by_name(handler, signal_name, this);
				GLib.debug("emit returned id=%d", this.id);
				return true;
			}
			if (new Gi(this).dispatch()) {
				return true;
			}
			GLib.critical(
				"RPC dispatch: no handler for '%s' (%s)",
				object_name,
				this.method
			);
			return false;
		}

		/**
		 * Relay a {@link Response} to {@link connection} (sets wire id).
		 */
		public void reply(Response response)
		{
			this.connection.reply(this, response);
		}
	}
}
