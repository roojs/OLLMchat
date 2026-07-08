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

namespace OLLMrpcTests
{
	/**
	 * TCP client smoke test for {@link OLLMrpc.Client}.
	 *
	 * The test connects to an already-running daemon and uses
	 * {@code Daemon.shutdown} as the handshake request. That exercises the
	 * client TCP connection, request write, response read, and daemon shutdown.
	 */
	public class TcpClient : GLib.Object
	{
		/**
		 * Connect to the daemon endpoint and shut it down.
		 *
		 * @param endpoint TCP endpoint, usually {{{tcp://127.0.0.1:4141}}}
		 * @return zero on success, non-zero on connection failure
		 */
		public async int run(string endpoint)
		{
			var client = new OLLMrpc.Client.tcp(endpoint);
			client.call_timeout_seconds = 5;
			if (!yield client.connect(new OLLMrpc.Request() {
					method = "Daemon.shutdown",
					param = new OLLMrpc.CallParam()
				})) {
				GLib.printerr("connect failed: %s\n", client.connect_error);
				return 1;
			}
			client.disconnect();
			return 0;
		}
	}

	public static int main(string[] args)
	{
		var endpoint = args.length > 1
			? args[1]
			: "tcp://127.0.0.1:4141";
		var loop = new GLib.MainLoop();
		var tester = new TcpClient();
		var exit_code = 1;
		tester.run.begin(endpoint, (obj, res) => {
			exit_code = tester.run.end(res);
			loop.quit();
		});
		loop.run();
		return exit_code;
	}
}
