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
	 * Pairing publish stub. Android has no Avahi.
	 *
	 * The phone browses. The desktop publishes ''_rpc._tcp''.
	 */
	public class PairPublish : GLib.Object
	{
		/**
		 * Unused on Android. The desktop class emits this
		 * when Avahi fails after {@link start} returns.
		 */
		public signal void failed();

		/**
		 * Does not publish. Android is the browser.
		 *
		 * @param addresses Listen-choice IPv4 addresses
		 * @param port TLS bin listen port
		 * @return false
		 */
		public bool start(string[] addresses, uint16 port)
		{
			if (addresses.length == 0 || port < 1024) {
				return false;
			}
			return false;
		}

		/**
		 * Does not withdraw a service. Nothing was published.
		 */
		public void stop()
		{
		}
	}
}
