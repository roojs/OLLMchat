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

	public class RemoteParams : CallParam {
		public uint64 object_id { get; set; default = 0; }
		public static void rpc_register() {}
	}

	public class Remote : GLib.Object {
		public signal void call_ref(Request request);
		public signal void call_unref(Request request);
	}

	public class SubscribeParams : CallParam {
		public uint64 object_id { get; set; default = 0; }
		public string name { get; set; default = ""; }
		public static void rpc_register() {}
	}

	public class Subscription : GLib.Object {
		public Transport.Connection connection { get; set; }
		public string method { get; set; default = ""; }
		public int id { get; set; default = 0; }
		public ulong hid { get; set; default = 0; }
		public void emit() {}
	}

	public class Subscribe : GLib.Object {
		public signal void call_signal(Request request);
		public signal void call_unsubscribe(Request request);
	}

	public class Buffer : GLib.Object {
		public int fd { get; set; default = -1; }
		public void send(GLib.Socket socket) throws GLib.Error {}
		public void receive(GLib.Socket socket) throws GLib.Error {}
	}

#endif
}
