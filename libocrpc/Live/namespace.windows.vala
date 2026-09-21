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

/**
 * Compile-only {@link OLLMrpc.Live} shells when subscribe is not built.
 *
 * Unix compiles ''Live/namespace.vala'' instead (meson, not ''#if'').
 */
namespace OLLMrpc.Live
{
	/**
	 * GI layout check for a registered boxed GType.
	 *
	 * Windows/Android stub: fatal. Unix: ''Live/namespace.vala''.
	 *
	 * @param gtype boxed GType already in {@link Bin.gtype_to_alias}
	 */
	public static void boxed_ok(GLib.Type gtype)
	{
		GLib.error("boxed type '%s' has no GI info", gtype.name());
	}

	public class Remote : GLib.Object {
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Live-Remote", typeof(Remote),
				"rpc_ref", "",
				"rpc_unref", ""
			);
		}

		public void rpc_ref(Request request)
		{
		}

		public void rpc_unref(Request request)
		{
		}
	}

	public class Subscription : GLib.Object {
		public Transport.Connection connection { get; set; }
		public string method { get; set; default = ""; }
		public int id { get; set; default = 0; }
		public ulong hid { get; set; default = 0; }
		public static void emit(
			GLib.Closure closure,
			[CCode (type = "GValue*")] GLib.Value? return_value,
			[CCode (array_length_cname = "n_param_values", array_length_pos = 2.5, array_length_type = "guint")]
			GLib.Value[] param_values,
			void* invocation_hint,
			void* marshal_data
		) {
		}
	}

	public class Subscribe : GLib.Object {
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Live-Subscribe", typeof(Subscribe),
				"rpc_signal", "s",
				"unsubscribe", "s"
			);
		}

		public void rpc_signal(Request request, string name)
		{
		}

		public void unsubscribe(Request request, string name)
		{
		}
	}

	public class Callback : GLib.Object {
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Live-Callback", typeof(Callback),
				"register", "",
				"unregister", "t",
				"reply", ""
			);
		}

		public void register(Request request)
		{
		}

		public void unregister(Request request, uint64 callback_id)
		{
		}

		public void reply(Request request)
		{
		}
	}

	public class Hook : GLib.Object {
		public Transport.Connection connection { get; set; }
		public int id { get; set; default = 0; }
		public int reply_id { get; set; default = 0; }
		public bool replied { get; set; default = false; }
		public Gee.ArrayList<GLib.Value?> reply_args {
			get; set; default = new Gee.ArrayList<GLib.Value?>();
		}

		public void emit(Gee.ArrayList<GLib.Value?> args)
		{
		}

		public static void drop(Hook user)
		{
		}
	}

	public class Invoke : GLib.Object {
		public int id { get; set; default = 0; }
		public int reply_id { get; set; default = 0; }
		public Gee.ArrayList<GLib.Value?> args {
			get; set; default = new Gee.ArrayList<GLib.Value?>();
		}

		public static void rpc_register()
		{
		}
	}

	public class Buffer : GLib.Object {
		public int fd { get; set; default = -1; }
		public void send(GLib.Socket socket) throws GLib.Error {}
		public void receive(GLib.Socket socket) throws GLib.Error {}
	}

	public class BufferStream : GLib.Object {
		public GLib.Socket? socket { get; set; default = null; }
		public BufferStream() { Object(); }
		public async void connect_client(string main_socket_path) throws GLib.Error {}
		public void write_with(Buffer? buffer, Bin.Serializable serializable, Bin.Stream bin) throws GLib.Error {}
		public void receive_one() throws GLib.Error {}
		public void read_fd() {}
		public void attach(Notification notif) {}
		public Buffer? take_pending() { return null; }
		public void close() {}
	}

	public class BufferListen : GLib.Object {
		public BufferListen(string main_socket_path) { Object(); }
		public bool start() { return true; }
		public void pair_connection(Transport.Connection connection) {}
		public void stop() {}
	}
}
