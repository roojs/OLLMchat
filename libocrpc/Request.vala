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
	 * namespaces like ''RPC-Live-Remote.rpc_unref''; or a REST
	 * path for HTTP). Attach positional {@link GLib.Value}s on
	 * ''args'' via {@link args} (omit when empty). For typed
	 * HTTP results, set ''result_type'' before {@link Client.call}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var req = new OLLMrpc.Request() {
	 *     method = "RPC-Folder.fetch_files",
	 *     args = OLLMrpc.args(
	 *         "siisSb", "/home/user/project", 0, 50, "",
	 *         new string[] {}, false
	 *     ),
	 *     result_type = typeof(OLLMfilesd.FileArray)
	 * };
	 * var resp = yield rpc.call(req);
	 * if (resp.error != null) {
	 *     GLib.error("%s", resp.error.message);
	 * }
	 * }}}
	 *
	 * @see Client
	 * @see Response
	 */
	public class Request : GLib.Object, Bin.Serializable
	{
		/** Wire object prefix → handler singleton (server dispatch). */
		public static Gee.HashMap<string, GLib.Object> handlers;

		/** Wire object prefix → Vala GType (C symbol). */
		public static Gee.HashMap<string, GLib.Type> types;

		/** Wire object prefix → (method suffix → D-Bus signature). */
		public static Gee.HashMap<string, Gee.HashMap<string, string>> methods;

		/** Wire prefixes registered with {@link register_live}. */
		public static Gee.HashMap<string, bool> live;

		public int id { get; set; }
		public string method { get; set; default = ""; }

		/**
		 * Positional arguments (client → daemon), GIR / C order.
		 *
		 * Empty list is omitted on the bin socket. Direction is
		 * not on the wire — the handler or typelib knows the signature.
		 *
		 * {@link Gee.ArrayList} cannot store {@link GLib.Value} (a struct).
		 * valac requires a boxed element type. That is boxing, not
		 * optional or null arguments. An empty list means no positional
		 * args. Prefer {@link args} to pack mixed types.
		 *
		 * == Example ==
		 *
		 * {{{
		 * req.args = OLLMrpc.args("s", "hi");
		 * }}}
		 */
		public Gee.ArrayList<GLib.Value?> args { get; set; default = new Gee.ArrayList<GLib.Value?>(); }

		/**
		 * Row in {@link Transport.Connection.leases} for a typelib method
		 * or live-handle RPC.
		 *
		 * ''0'' means none (constructors, calls with no lease). Omitted
		 * on the bin socket when ''0''.
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
		 * Register a server dispatch handler.
		 *
		 * @param name wire object prefix (e.g. RPC-Folder)
		 * @param target handler singleton
		 */
		public static void register(
			string name,
			GLib.Object target
		) {
			if (handlers == null) {
				handlers = new Gee.HashMap<string, GLib.Object>();
			}
			handlers.set(name, target);
		}

		/**
		 * Register a live-handle handler.
		 *
		 * Same as {@link register}, and FFI keeps this singleton as
		 * ''this'' when {@link lease_id} is set. The id is the target
		 * (rpc_ref / rpc_unref / rpc_signal), not the calling object.
		 *
		 * == Example ==
		 *
		 * {{{
		 * OLLMrpc.Live.Remote.rpc_register();
		 * OLLMrpc.Request.register_live("RPC-Live-Remote", new OLLMrpc.Live.Remote());
		 * }}}
		 *
		 * @param name wire object prefix (e.g. RPC-Live-Remote)
		 * @param target handler singleton
		 */
		public static void register_live(string name, GLib.Object target)
		{
			register(name, target);
			if (live == null) {
				live = new Gee.HashMap<string, bool>();
			}
			live.set(name, true);
		}

		/**
		 * List FFI instance methods for a wire prefix.
		 *
		 * Pair method suffix with a D-Bus signature (same letters as
		 * {@link args}). ''""'' is (self, Request) only; the method
		 * may still read {@link Request.args}. ''S'' is one
		 * ''string[]'' value and two C args (pointer + Vala length).
		 * The live singleton is still {@link register}.
		 *
		 * == Example ==
		 *
		 * {{{
		 * OLLMrpc.Request.add_class(
		 *     "RPC-Daemon", typeof(Daemon), "hello", "is"
		 * );
		 * OLLMrpc.Request.register("RPC-Daemon", this.daemon);
		 * }}}
		 *
		 * @param name wire object prefix (e.g. RPC-Folder)
		 * @param type handler GType (C prefix)
		 * @param ... method, signature pairs
		 */
		public static void add_class(
			string name,
			GLib.Type type,
			...
		) {
			if (types == null) {
				types = new Gee.HashMap<string, GLib.Type>();
				methods = new Gee.HashMap<string, Gee.HashMap<string, string>>();
			}
			types.set(name, type);
			if (!methods.has_key(name)) {
				methods.set(name, new Gee.HashMap<string, string>());
			}
			var l = va_list();
			while (true) {
				var method = l.arg<string>();
				if (method == null) {
					break;
				}
				methods.get(name).set(method, l.arg<string>());
			}
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public override void bin_write_prop(
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

		public override void bin_read_prop(
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
					this.bin_default_read_prop(ctx, prop, type_byte);
					return;
			}
		}

		/**
		 * Route this request to a listed FFI method or {@link Gi}.
		 *
		 * @return true when a handler ran
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
				GLib.critical("RPC dispatch: method must be RPC-Object.method, got '%s'",
					this.method);
				return false;
			}

			if (new Ffi(this).dispatch()) {
				return true;
			}
			if (new Gi(this).dispatch()) {
				return true;
			}
			GLib.critical("RPC dispatch: no handler for '%s' (%s)",
				this.method[0:dot], this.method);
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
