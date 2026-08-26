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
 * Opt-in live GObject handles for {@link OLLMrpc}.
 *
 * Unix builds compile {@link Remote}, {@link Subscribe}, {@link Buffer}, etc.
 * from separate ''Live/'' sources. Windows and Android compile this file
 * only — compile-only shells ({@link G_OS_WIN32} / {@link ANDROID}).
 *
 * {@link Buffer} — Unix: {@link Buffer}; Windows: shell in this file.
 */
namespace OLLMrpc.Live
{
	internal class NamespaceDoc {}

#if G_OS_WIN32 || ANDROID

	public class Remote : GLib.Object {
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Live-Remote", typeof(Remote),
				"rpc_ref", "",
				"rpc_unref", "",
				null
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
		public void emit() {}
	}

	public class Subscribe : GLib.Object {
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Live-Subscribe", typeof(Subscribe),
				"rpc_signal", "s",
				"unsubscribe", "s",
				null
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
				"reply", "",
				null
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
		public BufferStream() { Object(); }
		public async void connect_client(string main_socket_path) throws GLib.Error {}
		public void write_with(Buffer? buffer, Bin.Serializable serializable, Bin.Stream bin) throws GLib.Error {}
		public void attach(Notification notif) {}
		public void close() {}
	}

	public class BufferListen : GLib.Object {
		public BufferListen(string main_socket_path) { Object(); }
		public bool start() { return true; }
		public void pair_connection(Transport.Connection connection) {}
		public void stop() {}
	}

#endif
}
