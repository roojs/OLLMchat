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

namespace OLLMfiles
{
	/**
	 * NDJSON JSON-RPC client for {@code ollmfilesd} on a Unix stream socket.
	 *
	 * A background read loop dispatches {@link OLLMfilesd.Rpc.Notification}
	 * lines and resolves pending {@link OLLMfilesd.Rpc.Response} entries by id.
	 * {@link call} sends a {@link OLLMfilesd.Rpc.Request} and yields until that
	 * id is filled in or {@link call_timeout_seconds} elapses.
	 */
	public class RpcClient : GLib.Object
	{
		public string socket_path { get; construct; }
		public int protocol { get; set; default = 1; }
		public string client_name { get; set; default = "ollmchat"; }

		/** Seconds to wait for a matching {@link OLLMfilesd.Rpc.Response} id. */
		public uint call_timeout_seconds { get; set; default = 120; }

		public bool connected { get; private set; default = false; }

		public signal void notification(OLLMfilesd.Rpc.Notification notif);

		private GLib.SocketConnection? connection;
		private GLib.DataInputStream? input;
		private GLib.DataOutputStream? output;
		private int next_id = 1;
		private Gee.HashMap<int, GLib.Promise<OLLMfilesd.Rpc.Response>> pending {
			get; private set;
			default = new Gee.HashMap<int, GLib.Promise<OLLMfilesd.Rpc.Response>>();
		}

		public RpcClient(string socket_path = "")
		{
			if (socket_path == "") {
				socket_path = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(),
					"ollmchat",
					"ollmfilesd.sock"
				);
			}
			GLib.Object(socket_path: socket_path);
		}

		public async void connect() throws GLib.IOError
		{
			if (this.connected) {
				return;
			}

			var client = new GLib.SocketClient();
			var addr = new GLib.UnixSocketAddress(this.socket_path);
			try {
				this.connection = yield client.connect_async(
					addr, null, GLib.Priority.DEFAULT, null
				);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED(
					"RpcClient: connect " + this.socket_path + ": " + e.message
				);
			}

			this.input = new GLib.DataInputStream(this.connection.get_input_stream());
			this.input.set_newline_type(GLib.DataStreamNewlineType.LF);
			this.output = new GLib.DataOutputStream(this.connection.get_output_stream());
			this.output.set_use_buffering(false);
			this.connected = true;
			this.read_loop.begin();

			yield this.call(new OLLMfilesd.Rpc.Request() {
				method = "Daemon.hello",
				param = new OLLMfilesd.Rpc.CallParam() {
					protocol = this.protocol,
					client = this.client_name
				}
			});
		}

		public void disconnect()
		{
			if (!this.connected) {
				return;
			}
			this.connected = false;
			foreach (var entry in this.pending.entries) {
				entry.value.reject(new GLib.IOError.FAILED("RpcClient: disconnected"));
			}
			this.pending.clear();
			this.input = null;
			this.output = null;
			if (this.connection != null) {
				try {
					this.connection.close();
				} catch (GLib.Error e) {
				}
				this.connection = null;
			}
		}

		/**
		 * @param request wire request; {@link OLLMfilesd.Rpc.Request.id} is set here
		 * @return wire response; check {@link OLLMfilesd.Rpc.Response.error}
		 */
		public async OLLMfilesd.Rpc.Response call(
			OLLMfilesd.Rpc.Request request
		) throws GLib.IOError
		{
			if (!this.connected || this.output == null) {
				throw new GLib.IOError.FAILED("RpcClient: not connected");
			}

			request.id = this.next_id++;
			var promise = new GLib.Promise<OLLMfilesd.Rpc.Response>();
			this.pending.set(request.id, promise);

			size_t length;
			var line = Json.gobject_to_data(request, out length) + "\n";
			try {
				this.output.put_string(line);
				yield this.output.flush_async(GLib.Priority.DEFAULT, null);
			} catch (GLib.Error e) {
				this.pending.unset(request.id);
				throw new GLib.IOError.FAILED("RpcClient: write: " + e.message);
			}

			return yield this.wait_response(request.id, promise);
		}

		private async OLLMfilesd.Rpc.Response wait_response(
			int id,
			GLib.Promise<OLLMfilesd.Rpc.Response> promise
		)
		{
			var cancellable = new GLib.Cancellable();
			uint timeout_id = 0;
			if (this.call_timeout_seconds > 0) {
				timeout_id = GLib.Timeout.add_seconds(this.call_timeout_seconds, () => {
					if (!this.pending.has_key(id)) {
						return false;
					}
					this.pending.unset(id);
					cancellable.cancel();
					return false;
				});
			}

			try {
				return yield promise.future.wait_async(cancellable);
			} catch (GLib.Error e) {
				if (cancellable.is_cancelled()) {
					return new OLLMfilesd.Rpc.Response(id) {
						error = new OLLMfilesd.Rpc.Error() {
							code = (int) OLLMfilesd.Rpc.RpcErrorCode.INTERNAL_ERROR,
							message = "RpcClient: call timed out"
						}
					};
				}
				return new OLLMfilesd.Rpc.Response(id) {
					error = new OLLMfilesd.Rpc.Error() {
						code = (int) OLLMfilesd.Rpc.RpcErrorCode.INTERNAL_ERROR,
						message = e.message
					}
				};
			} finally {
				if (timeout_id != 0) {
					GLib.Source.remove(timeout_id);
				}
			}
		}

		private async void read_loop()
		{
			while (this.connected && this.input != null) {
				try {
					var response_line = yield this.input.read_line_async(
						GLib.Priority.DEFAULT, null
					);
					if (response_line == null) {
						this.disconnect();
						return;
					}
					this.dispatch_line(response_line.strip());
				} catch (GLib.Error e) {
					GLib.warning("RpcClient read error: %s", e.message);
					this.disconnect();
					return;
				}
			}
		}

		private void dispatch_line(string data)
		{
			var parser = new Json.Parser();
			try {
				parser.load_from_data(data, -1);
			} catch (GLib.Error e) {
				GLib.warning("RpcClient invalid JSON: %s", e.message);
				return;
			}

			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				GLib.warning("RpcClient line not a JSON object");
				return;
			}
			var obj = root.get_object();

			if (!obj.has_member("id")) {
				var notif = Json.gobject_from_data(
					typeof(OLLMfilesd.Rpc.Notification), data
				) as OLLMfilesd.Rpc.Notification;
				if (notif != null) {
					this.notification(notif);
				}
				return;
			}

			var response = Json.gobject_from_data(
				typeof(OLLMfilesd.Rpc.Response), data
			) as OLLMfilesd.Rpc.Response;
			if (response == null) {
				return;
			}
			if (!this.pending.has_key(response.id)) {
				GLib.warning("RpcClient unexpected response id %d", response.id);
				return;
			}
			this.pending.get(response.id).resolve(response);
			this.pending.unset(response.id);
		}
	}
}
