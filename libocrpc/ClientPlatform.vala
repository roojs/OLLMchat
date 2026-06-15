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

namespace OLLMrpc
{
	internal string default_client_endpoint()
	{
		return GLib.Path.build_filename(
			GLib.Environment.get_user_data_dir(),
			"ollmchat",
			"ollmfilesd.sock"
		);
	}

	internal bool client_boot_required(bool tcp)
	{
		return !tcp;
	}

	internal async GLib.SocketConnection connect_unix_socket(
		string socket
	) throws GLib.Error
	{
		var client = new GLib.SocketClient();
		return yield client.connect_async(
			new GLib.UnixSocketAddress(socket),
			null
		);
	}
}
