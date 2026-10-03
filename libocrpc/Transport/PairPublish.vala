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

namespace OLLMrpc.Transport
{
	/**
	 * mDNS publish for the pairing window.
	 *
	 * {@link start} sends PTR, SRV, and one A record per address
	 * for ''_rpc._tcp'' in ''.local''. {@link stop} withdraws them.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var pub = new OLLMrpc.Transport.PairPublish();
	 * pub.start(OLLMrpc.Transport.TcpListen.ifaces(), 8422);
	 * pub.stop();
	 * }}}
	 */
	public class PairPublish : GLib.Object
	{
		private string[] addresses = {};
		private uint16 port = 0;
		private bool up = false;
		private Avahi.Client? client = null;
		private Avahi.EntryGroup? group = null;

		/**
		 * Avahi failed after {@link start} had already returned.
		 *
		 * The dialog toasts. {@link start} itself returns false
		 * for a failure that happens before it returns.
		 */
		public signal void failed();

		/**
		 * Publish ''addresses'' on ''_rpc._tcp'' at ''port''.
		 *
		 * Returns false when the list is empty, the port is
		 * outside 1024–65535, or Avahi rejects the records now.
		 * A later failure emits {@link failed}.
		 *
		 * @param addresses Listen-choice IPv4 addresses
		 * @param port TLS bin listen port
		 * @return false when the publish did not succeed
		 */
		public bool start(string[] addresses, uint16 port)
		{
			this.stop();
			if (addresses.length == 0 || port < 1024) {
				this.failed();
				return false;
			}
			this.addresses = addresses;
			this.port = port;
			var fresh = this.client == null;
			if (fresh) {
				var client = new Avahi.Client(Avahi.ClientFlags.NO_FAIL);
				var group = new Avahi.EntryGroup();
				client.state_changed.connect((state) => {
					if (state == Avahi.ClientState.FAILURE) {
						this.failed();
						return;
					}
					if (state != Avahi.ClientState.S_RUNNING) {
						return;
					}
					if (this.commit()) {
						return;
					}
					this.failed();
				});
				try {
					group.attach(client);
				} catch (Avahi.Error e) {
					this.failed();
					return false;
				}
				try {
					client.start();
				} catch (Avahi.Error e) {
					this.failed();
					return false;
				}
				this.client = client;
				this.group = group;
			}
			if (this.client.state == Avahi.ClientState.FAILURE) {
				return false;
			}
			if (fresh || this.client.state != Avahi.ClientState.S_RUNNING) {
				return true;
			}
			if (this.commit()) {
				return true;
			}
			this.failed();
			return false;
		}

		/**
		 * Withdraw the pairing service.
		 */
		public void stop()
		{
			if (!this.up || this.group == null) {
				return;
			}
			this.up = false;
			try {
				this.group.reset();
			} catch (Avahi.Error e) {
				return;
			}
		}

		/**
		 * Commit PTR, SRV, and one A record per address.
		 *
		 * DNS class and type are both 1 (IN, A). The A record
		 * holds the address only.
		 *
		 * @return false when Avahi rejects the records
		 */
		private bool commit()
		{
			if (this.addresses.length == 0 || this.group == null) {
				return false;
			}
			var name = GLib.Environment.get_host_name();
			var dot = name.index_of(".");
			if (dot > 0) {
				name = name.substring(0, dot);
			}
			var host = name + ".local";
			if (this.up) {
				try {
					this.group.reset();
				} catch (Avahi.Error e) {
					return false;
				}
				this.up = false;
			}
			try {
				this.group.add_service_full(Avahi.Interface.UNSPEC,
					Avahi.Protocol.INET, Avahi.PublishFlags.NO_COOKIE,
					name, "_rpc._tcp", "local", host, this.port);
			} catch (Avahi.Error e) {
				return false;
			}
			foreach (var ip in this.addresses) {
				var packed = new char[4];
				if (Posix.inet_pton(Posix.AF_INET, ip, packed) != 1) {
					continue;
				}
				try {
					this.group.add_record_full(Avahi.Interface.UNSPEC,
						Avahi.Protocol.INET, (Avahi.PublishFlags) 0,
						host, 1, 1, 120, packed);
				} catch (Avahi.Error e) {
					return false;
				}
			}
			try {
				this.group.commit();
			} catch (Avahi.Error e) {
				return false;
			}
			this.up = true;
			return true;
		}
	}
}
