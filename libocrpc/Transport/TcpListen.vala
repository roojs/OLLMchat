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

namespace OLLMrpc.Transport
{
	/**
	 * TCP loopback {@link Listen} for platforms without Unix sockets.
	 *
	 * Defaults to loopback; remote access needs an authenticated transport
	 * before callers should bind a public address.
	 */
	public class TcpListen : Listen
	{
		public string host { get; construct; default = "127.0.0.1"; }
		public uint16 port { get; construct; default = 4141; }

		private GLib.SocketService service { get; set; default = new GLib.SocketService(); }
		private bool listening = false;
		private Gee.ArrayList<Connection> connections = new Gee.ArrayList<Connection>();

		public TcpListen(string host = "127.0.0.1", uint16 port = 4141)
		{
			GLib.Object(host: host, port: port);
		}

		public override bool start()
		{
			if (this.listening) {
				return true;
			}

			this.service = new GLib.SocketService();
			var effective = (GLib.SocketAddress) new GLib.InetSocketAddress.from_string(
				this.host,
				this.port
			);
			try {
				this.service.add_address(
					effective,
					GLib.SocketType.STREAM,
					GLib.SocketProtocol.TCP,
					null,
					out effective
				);
			} catch (GLib.Error e) {
				GLib.warning(
					"failed to bind TCP listener %s:%u: %s",
					this.host,
					this.port,
					e.message
				);
				return false;
			}
			this.service.incoming.connect((conn) => {
				var connection = new Connection(conn) {
					live_handles = this.live_handles
				};
				connection.start();
				this.connections.add(connection);
				return true;
			});
			this.service.start();
			this.listening = true;
			return true;
		}

		public override void broadcast(GLib.Object gobject)
		{
			foreach (var connection in this.connections) {
				connection.write(gobject);
			}
		}

		public override void stop()
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			this.service.stop();
			this.service = new GLib.SocketService();
			foreach (var connection in this.connections) {
				connection.stop();
			}
			this.connections.clear();
		}

		/**
		 * Up non-loopback IPv4 addresses on this machine.
		 *
		 * Skips ''0.0.0.0'', ''127.0.0.1'', and duplicates.
		 * The SSL **All** choice is not an entry. The dropdown
		 * adds that label itself.
		 *
		 * @return One string per address. Empty when this
		 * platform has no ''getifaddrs'' or the call fails.
		 */
		public static string[] ifaces()
		{
#if ANDROID || G_OS_WIN32
			string[] none = {};
			return none;
#else
			Linux.Network.IfAddrs addrs;
			if (Linux.Network.getifaddrs(out addrs) != 0) {
				string[] none = {};
				return none;
			}
			string[] found = {};
			for (unowned var iface = addrs; iface != null; iface = iface.ifa_next) {
				if (iface.ifa_addr == null) {
					continue;
				}
				if (iface.ifa_addr.sa_family != Posix.AF_INET) {
					continue;
				}
				if ((iface.ifa_flags & Linux.Network.IfFlag.UP) == 0) {
					continue;
				}
				var sin = (Posix.SockAddrIn*) iface.ifa_addr;
				var buf = new uint8[Posix.INET_ADDRSTRLEN];
				var ip = Posix.inet_ntop(Posix.AF_INET, &sin.sin_addr, buf);
				if (ip == null || ip == "" || ip == "0.0.0.0" || ip == "127.0.0.1") {
					continue;
				}
				var seen = false;
				foreach (var existing in found) {
					if (existing != ip) {
						continue;
					}
					seen = true;
					break;
				}
				if (seen) {
					continue;
				}
				found += ip;
			}
			return found;
#endif
		}
	}
}
