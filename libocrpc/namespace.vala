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

/**
 * Binary RPC client and wire types shared by apps and ollmfilesd.
 *
 * The OLLMrpc namespace is the client library for talking to ollmfilesd over a
 * Unix socket (or stdio/TCP), and for calling HTTPS JSON APIs with the same
 * {@link Request} / {@link Response} shape. {@link Client} owns the channel.
 * {@link Request} carries ''method'', positional ''args'' via {@link args},
 * and optional ''result_type''. {@link Bin} serializes {@link Bin.Serializable}
 * GObjects on the wire. {@link Transport} is the daemon listen/connection side.
 * {@link Live} is opt-in live GObject handles (ref, unref, subscribe).
 *
 * == Architecture Benefits ==
 *
 *  * Positional args: D-Bus signature packing via {@link args}, not ad-hoc JSON bags
 *  * One client: Unix socket for ollmfilesd, HTTPS URL for Hub-style APIs
 *  * Bin codec: compact wire with JIT property keys ({@link Bin.Stream})
 *  * Shared types: same Request/Response on client and daemon
 *
 * == Usage Examples ==
 *
 * === ollmfilesd (Unix socket) ===
 *
 * {{{
 * OLLMrpc.Daemon.rpc_register();
 * var rpc = new OLLMrpc.Client(
 *     GLib.Path.build_filename(
 *         GLib.Environment.get_user_data_dir(), "ollmchat"),
 *     "ollmfilesd.pid",
 *     "ollmfilesd.sock"
 * );
 * if (!yield rpc.connect(new OLLMrpc.Request() {
 *     method = "RPC-Daemon.hello",
 *     args = OLLMrpc.args("is", 1, "my-app")
 * }, new OLLMrpc.ClientBoot())) {
 *     GLib.error("%s", rpc.connect_error);
 * }
 * var resp = yield rpc.call(new OLLMrpc.Request() {
 *     method = "RPC-ProjectManager.rpc_load_projects_from_db"
 * });
 * }}}
 *
 * === HTTPS JSON (e.g. Hugging Face Hub) ===
 *
 * {{{
 * OLLMhf.rpc_register();
 * var rpc = new OLLMrpc.Client("", "", "https://huggingface.co");
 * yield rpc.connect(new OLLMrpc.Request());
 * var resp = yield rpc.call(new OLLMrpc.Request() {
 *     method = "/api/models",
 *     args = OLLMrpc.args("o", new OLLMhf.Param.Search() {
 *         search = "llama",
 *         filter = "gguf",
 *         limit = 10
 *     }),
 *     result_type = typeof(OLLMhf.ModelArray)
 * });
 * }}}
 *
 * == Best Practices ==
 *
 *  1. Registration: call each wire type's ''rpc_register()'' before connect
 *  2. Args: pack with {@link args} onto {@link Request.args}, not raw maps
 *  3. Results: set result_type when the HTTP path should decode to a GType
 *  4. Errors: check Response.error after every call
 *  5. Bin round-trips: see {@link Bin} and docs/bin-rpc-protocol.md
 */
namespace OLLMrpc
{
	/**
	 * Namespace documentation marker.
	 * This file contains namespace-level documentation for OLLMrpc.
	 */
	internal class NamespaceDoc {}

	/**
	 * Pack one already-scanned D-Bus type from an open va_list.
	 *
	 * {@link val} and {@link args} call this once per letter.
	 *
	 * @param tag one complete type (''s'', ''o'', ''as'', …)
	 * @param l varargs cursor
	 * @return boxed value
	 */
	private GLib.Value to_value(string tag, va_list l)
	{
		switch (tag) {
			case "s":
				var s_val = GLib.Value(typeof(string));
				s_val.set_string(l.arg<string>());
				return s_val;

			case "b":
				var b_val = GLib.Value(typeof(bool));
				b_val.set_boolean(l.arg<bool>());
				return b_val;

			case "y":
				var y_val = GLib.Value(typeof(uint8));
				y_val.set_uchar((uint8) l.arg<int>());
				return y_val;

			case "n":
				var n_val = GLib.Value(typeof(int));
				n_val.set_int(l.arg<int>());
				return n_val;

			case "q":
				var q_val = GLib.Value(typeof(uint));
				q_val.set_uint((uint) l.arg<int>());
				return q_val;

			case "i":
				var i_val = GLib.Value(typeof(int));
				i_val.set_int(l.arg<int>());
				return i_val;

			case "u":
				var u_val = GLib.Value(typeof(uint));
				u_val.set_uint(l.arg<uint>());
				return u_val;

			case "x":
				var x_val = GLib.Value(typeof(int64));
				x_val.set_int64(l.arg<int64>());
				return x_val;

			case "t":
				var t_val = GLib.Value(typeof(uint64));
				t_val.set_uint64(l.arg<uint64>());
				return t_val;

			case "f":
				var f_val = GLib.Value(typeof(float));
				f_val.set_float((float) l.arg<double>());
				return f_val;

			case "d":
				var d_val = GLib.Value(typeof(double));
				d_val.set_double(l.arg<double>());
				return d_val;

			case "o":
				var obj = l.arg<GLib.Object>();
				if (obj == null) {
					var null_o = GLib.Value(typeof(GLib.Object));
					null_o.set_object(null);
					return null_o;
				}
				var o_val = GLib.Value(obj.get_type());
				o_val.set_object(obj);
				return o_val;

			case "g":
				var g_val = GLib.Value(typeof(string));
				g_val.set_string(l.arg<string>());
				return g_val;

			case "h":
				var h_val = GLib.Value(typeof(int));
				h_val.set_int(l.arg<int>());
				return h_val;

			case "S":
			case "as":
				var as_val = GLib.Value(typeof(string[]));
				as_val.set_boxed(l.arg<string[]>());
				return as_val;

			case "ay":
				var ay_val = GLib.Value(typeof(GLib.Bytes));
				ay_val.set_boxed(l.arg<GLib.Bytes>());
				return ay_val;

			case "v":
				var v_val = GLib.Value(typeof(GLib.Variant));
				v_val.set_variant(l.arg<GLib.Variant>());
				return v_val;

			default:
				GLib.error("unknown D-Bus type %s", tag);
		}
	}

	/**
	 * Pack one return into a {@link GLib.Value} for {@link Response.retval}.
	 *
	 * Same D-Bus letters as {@link args}. ''signature'' is **one**
	 * complete type. Two types belong on {@link args}. An empty
	 * {@link Gee.ArrayList} returns unset ({@link GLib.Type.INVALID})
	 * so the wire omits it. ''o'' uses the instance GType so a list
	 * stays an array on the wire.
	 *
	 * == Example ==
	 *
	 * {{{
	 * request.reply(new OLLMrpc.Response() {
	 *     id = request.id,
	 *     retval = OLLMrpc.val("o", row)
	 * });
	 * }}}
	 *
	 * @param signature one D-Bus complete type
	 * @return value to assign to {@link Response.retval}
	 */
	public GLib.Value val(string signature, ...)
	{
		if (signature == "") {
			return GLib.Value(GLib.Type.INVALID);
		}
		var l = va_list();
		var rest = signature;
		var tag = "";
		if (rest.has_prefix("f")) {
			tag = "f";
			rest = rest.substring(1);
		} else if (rest.has_prefix("S")) {
			tag = "S";
			rest = rest.substring(1);
		} else {
			var rest_ptr = (char*) rest;
			var next = (char*) null;
			if (!GLib.VariantType.string_scan(rest, null, out next) || next == rest_ptr) {
				GLib.error("invalid D-Bus type signature %s", signature);
			}
			var n = (long) ((uint8*) next - (uint8*) rest_ptr);
			tag = rest.substring(0, n);
			rest = rest.substring((int) n);
		}
		if (rest != "") {
			GLib.error("val() takes one complete type, got %s", signature);
		}
		var v = to_value(tag, l);
		if (!v.type().is_a(typeof(Gee.ArrayList))) {
			return v;
		}
		var list = (Gee.ArrayList<GLib.Object>) v.get_object();
		if (list.size == 0) {
			return GLib.Value(GLib.Type.INVALID);
		}
		return v;
	}

	/**
	 * Pack mixed RPC arguments into a {@link Gee.ArrayList} of
	 * {@link GLib.Value}.
	 *
	 * The first argument is a D-Bus type signature (GVariant string).
	 * Remaining arguments are Vala varargs, one value per complete type
	 * in that signature. Unknown or invalid types are fatal.
	 *
	 * ''s'' string, ''b'' bool, ''y'' byte, ''n'' int16, ''q'' uint16,
	 * ''i'' int32, ''u'' uint32, ''x'' int64, ''t'' uint64, ''f'' float,
	 * ''d'' double,
	 * ''o'' {@link GLib.Object}, ''g'' signature, ''h'' unix fd,
	 * ''as'' ''string[]'', ''S'' same value plus Vala array length
	 * at FFI call, ''ay'' {@link GLib.Bytes},
	 * ''v'' {@link GLib.Variant}.
	 *
	 * Lease ids and {@link Bin.Serializable} encoding happen when
	 * {@link Request} is written ({@link Bin.StreamValue}).
	 *
	 * == Example ==
	 *
	 * {{{
	 * var req = new OLLMrpc.Request() {
	 *     method = "RPC-File.read",
	 *     args = OLLMrpc.args("s", path)
	 * };
	 * }}}
	 *
	 * @param signature D-Bus type signature, concatenated complete types
	 * @return list to assign to {@link Request.args}
	 */
	public Gee.ArrayList<GLib.Value?> args(string signature, ...)
	{
		var packed = new Gee.ArrayList<GLib.Value?>();
		if (signature == "") {
			return packed;
		}
		var l = va_list();
		var offset = 0;
		while (offset < signature.length) {
			var rest = signature.substring(offset);
			var tag = "";
			if (rest.has_prefix("f")) {
				tag = "f";
				offset += 1;
			} else if (rest.has_prefix("S")) {
				tag = "S";
				offset += 1;
			} else {
				var rest_ptr = (char*) rest;
				var next = (char*) null;
				if (!GLib.VariantType.string_scan(rest, null, out next) || next == rest_ptr) {
					GLib.error("invalid D-Bus type signature %s", signature);
				}
				var n = (long) ((uint8*) next - (uint8*) rest_ptr);
				tag = rest.substring(0, n);
				offset += (int) n;
			}
			packed.add(to_value(tag, l));
		}
		return packed;
	}

	/**
	 * Register stock envelope types, and optionally the live stack.
	 *
	 * Always registers {@link Request}, {@link Response},
	 * {@link Notification}, and {@link Error}. When ''live'' is
	 * ''true'', also registers {@link Live.Invoke} and the live
	 * handler singletons ({@link Live.Remote},
	 * {@link Live.Subscribe}, {@link Live.Callback}).
	 *
	 * Call once before listen. Clients that construct
	 * {@link Client} already get envelope types plus
	 * {@link Live.Invoke}; they must not pass ''live''
	 * ''true''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.rpc_register();
	 * OLLMrpc.rpc_register(true);
	 * }}}
	 *
	 * @param live ''true'' to export live-handle handlers
	 */
	public void rpc_register(bool live = false)
	{
		Request.rpc_register();
		Response.rpc_register();
		Notification.rpc_register();
		Error.rpc_register();
		if (!live) {
			return;
		}
		Live.Remote.rpc_register();
		Live.Subscribe.rpc_register();
		Live.Invoke.rpc_register();
		Live.Callback.rpc_register();
		Request.register_live("RPC-Live-Remote", new Live.Remote());
		Request.register_live("RPC-Live-Subscribe", new Live.Subscribe());
		Request.register_live("RPC-Live-Callback", new Live.Callback());
	}
}
