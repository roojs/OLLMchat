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
 * {@link Request} carries ''method'', a typed {@link CallParam} on ''param'',
 * and optional ''result_type''. {@link Bin} serializes {@link Bin.Serializable}
 * GObjects on the wire. {@link Transport} is the daemon listen/connection side.
 * {@link Live} is opt-in live GObject handles (ref, unref, subscribe).
 *
 * == Architecture Benefits ==
 *
 *  * Typed params: CallParam subclasses, not ad-hoc JSON bags
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
 * OLLMfilesd.DaemonParams.rpc_register();
 * var rpc = new OLLMrpc.Client(
 *     GLib.Path.build_filename(
 *         GLib.Environment.get_user_data_dir(), "ollmchat"),
 *     "ollmfilesd.pid",
 *     "ollmfilesd.sock"
 * );
 * if (!yield rpc.connect(new OLLMrpc.Request() {
 *     method = "RPC-Daemon.hello",
 *     param = new OLLMfilesd.DaemonParams() {
 *         protocol = 1,
 *         client = "my-app"
 *     }
 * }, new OLLMrpc.ClientBoot())) {
 *     GLib.error("%s", rpc.connect_error);
 * }
 * var resp = yield rpc.call(new OLLMrpc.Request() {
 *     method = "RPC-ProjectManager.load_projects_from_db",
 *     param = new OLLMfilesd.ProjectParams()
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
 *     param = new OLLMhf.Param.Search() {
 *         search = "llama",
 *         filter = "gguf",
 *         limit = 10
 *     },
 *     result_type = typeof(OLLMhf.ModelArray)
 * });
 * }}}
 *
 * == Best Practices ==
 *
 *  1. Registration: call each wire type's ''rpc_register()'' before connect
 *  2. Params: use a CallParam subclass on Request.param, not raw maps
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
	 * Pack mixed RPC arguments into a {@link Gee.ArrayList} of
	 * {@link GLib.Value}.
	 *
	 * The first argument is a D-Bus type signature (GVariant string).
	 * Remaining arguments are Vala varargs, one value per complete type
	 * in that signature. Unknown or invalid types are fatal.
	 *
	 * ''s'' string, ''b'' bool, ''y'' byte, ''n'' int16, ''q'' uint16,
	 * ''i'' int32, ''u'' uint32, ''x'' int64, ''t'' uint64, ''d'' double,
	 * ''o'' {@link GLib.Object}, ''g'' signature, ''h'' unix fd,
	 * ''as'' ''string[]'', ''ay'' {@link GLib.Bytes},
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
			var rest_ptr = (char*) rest;
			var next = (char*) null;
			if (!GLib.VariantType.string_scan(rest, null, out next) || next == rest_ptr) {
				GLib.error("invalid D-Bus type signature %s", signature);
			}
			var n = (long) ((uint8*) next - (uint8*) rest_ptr);
			var tag = rest.substring(0, n);
			offset += (int) n;
			switch (tag) {
				case "s":
					var s_val = GLib.Value(typeof(string));
					s_val.set_string(l.arg<string>());
					packed.add(s_val);
					break;

				case "b":
					var b_val = GLib.Value(typeof(bool));
					b_val.set_boolean(l.arg<bool>());
					packed.add(b_val);
					break;

				case "y":
					var y_val = GLib.Value(typeof(uint8));
					y_val.set_uchar((uint8) l.arg<int>());
					packed.add(y_val);
					break;

				case "n":
					var n_val = GLib.Value(typeof(int));
					n_val.set_int(l.arg<int>());
					packed.add(n_val);
					break;

				case "q":
					var q_val = GLib.Value(typeof(uint));
					q_val.set_uint((uint) l.arg<int>());
					packed.add(q_val);
					break;

				case "i":
					var i_val = GLib.Value(typeof(int));
					i_val.set_int(l.arg<int>());
					packed.add(i_val);
					break;

				case "u":
					var u_val = GLib.Value(typeof(uint));
					u_val.set_uint(l.arg<uint>());
					packed.add(u_val);
					break;

				case "x":
					var x_val = GLib.Value(typeof(int64));
					x_val.set_int64(l.arg<int64>());
					packed.add(x_val);
					break;

				case "t":
					var t_val = GLib.Value(typeof(uint64));
					t_val.set_uint64(l.arg<uint64>());
					packed.add(t_val);
					break;

				case "d":
					var d_val = GLib.Value(typeof(double));
					d_val.set_double(l.arg<double>());
					packed.add(d_val);
					break;

				case "o":
					var o_val = GLib.Value(typeof(GLib.Object));
					o_val.set_object(l.arg<GLib.Object>());
					packed.add(o_val);
					break;

				case "g":
					var g_val = GLib.Value(typeof(string));
					g_val.set_string(l.arg<string>());
					packed.add(g_val);
					break;

				case "h":
					var h_val = GLib.Value(typeof(int));
					h_val.set_int(l.arg<int>());
					packed.add(h_val);
					break;

				case "as":
					var as_val = GLib.Value(typeof(string[]));
					as_val.set_boxed(l.arg<string[]>());
					packed.add(as_val);
					break;

				case "ay":
					var ay_val = GLib.Value(typeof(GLib.Bytes));
					ay_val.set_boxed(l.arg<GLib.Bytes>());
					packed.add(ay_val);
					break;

				case "v":
					var v_val = GLib.Value(typeof(GLib.Variant));
					v_val.set_variant(l.arg<GLib.Variant>());
					packed.add(v_val);
					break;

				default:
					GLib.error("unknown D-Bus type %s", tag);
			}
		}
		return packed;
	}
}
