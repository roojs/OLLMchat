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
	 * {@link connect} runs {@link RpcClientBoot.ensure_daemon} first.
	 *
	 * A background read loop dispatches {@link OLLMrpc.Notification}
	 * lines and resolves pending {@link OLLMrpc.Response} entries by id.
	 * {@link call} sends a {@link OLLMrpc.Request} and yields until that
	 * id is filled in or {@link call_timeout_seconds} elapses.
	 * Transport and client faults return {@link OLLMrpc.Response.error}; they
	 * do not throw. {@link failed} is emitted for every failed {@link call};
	 * connect UI handlers there instead of per-caller logging.
	 */
	public class RpcClient : GLib.Object
	{
		public string socket { get; construct; }
		public int protocol { get; set; default = 1; }
		public string client_name { get; set; default = "ollmchat"; }

		/** Seconds to wait for a matching {@link OLLMrpc.Response} id. */
		public uint call_timeout_seconds { get; set; default = 120; }

		public bool connected { get; private set; default = false; }

		/**
		 * Last {@link connect} failure (boot, socket, or hello).
		 * Empty when {@link connected} is true. UI reads this from {@link RpcClient}.
		 */
		public string connect_error { get; private set; default = ""; }

		public signal void notification(OLLMrpc.Notification notif);

		/**
		 * Emitted when {@link call} completes with {@link OLLMrpc.Response.error} set.
		 * Transport faults, timeouts, and daemon JSON-RPC errors all use this path.
		 * {@link call} still returns the response; callers may ignore errors when
		 * the UI connects here (e.g. toast / dialog).
		 */
		public signal void failed(OLLMrpc.Request request, OLLMrpc.Error error);

		private GLib.SocketConnection? connection;
		private GLib.DataInputStream? input;
		private GLib.DataOutputStream? output;
		private int next_id = 1;
		private Gee.HashMap<int, GLib.Promise<OLLMrpc.Response>> pending {
			get; private set;
			default = new Gee.HashMap<int, GLib.Promise<OLLMrpc.Response>>();
		}

		static construct
		{
			Daemon.rpc_register();
			Folder.rpc_register();
			File.rpc_register();
			FileAlias.rpc_register();
			FileWithHistory.rpc_register();
			SQT.VectorMetadata.rpc_register();
		}

		public RpcClient(string socket = "")
		{
			if (socket == "") {
				socket = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(),
					"ollmchat",
					"ollmfilesd.sock"
				);
			}
			GLib.Object(socket: socket);
		}

		/**
		 * Boot {@code ollmfilesd}, open the socket, and run {@code Daemon.hello}.
		 * @return false when the client cannot talk to the daemon (see {@link connect_error})
		 */
		public async bool connect()
		{
			if (this.connected) {
				this.connect_error = "";
				return true;
			}

			var boot = new RpcClientBoot(socket: this.socket);
			try {
				yield boot.ensure_daemon();
			} catch (GLib.IOError e) {
				this.connect_error = e.message != ""
					? e.message
					: "could not start or reach the filesystem daemon (ollmfilesd)";
				GLib.critical(
					"RpcClient: ensure_daemon %s: %s",
					this.socket,
					this.connect_error
				);
				return false;
			}

			var client = new GLib.SocketClient();
			var addr = new GLib.UnixSocketAddress(this.socket);
			try {
				this.connection = yield client.connect_async(
					addr, null, GLib.Priority.DEFAULT, null
				);
			} catch (GLib.Error e) {
				this.connect_error = e.message;
				GLib.critical(
					"RpcClient: connect %s: %s",
					this.socket,
					this.connect_error
				);
				return false;
			}

			this.input = new GLib.DataInputStream(this.connection.get_input_stream());
			this.input.set_newline_type(GLib.DataStreamNewlineType.LF);
			this.output = new GLib.DataOutputStream(this.connection.get_output_stream());
			this.output.set_use_buffering(false);
			this.connected = true;
			this.read_loop.begin();

			var hello_id = this.next_id++;
			var hello_request = new OLLMrpc.Request() {
				id = hello_id,
				method = "Daemon.hello",
				param = new OLLMrpc.CallParam() {
					protocol = this.protocol,
					client = this.client_name
				}
			};
			var hello_promise = new GLib.Promise<OLLMrpc.Response>();
			this.pending.set(hello_id, hello_promise);

			size_t hello_length;
			var hello_line = Json.gobject_to_data(hello_request, out hello_length) + "\n";
			try {
				this.output.put_string(hello_line);
				yield this.output.flush_async(GLib.Priority.DEFAULT, null);
			} catch (GLib.Error e) {
				this.pending.unset(hello_id);
				this.connect_error = "write: " + e.message;
				this.disconnect();
				return false;
			}

			var hello = yield this.wait_response(
				hello_id,
				hello_request.method,
				hello_promise
			);
			if (hello.error != null) {
				this.connect_error = hello.error.message != ""
					? hello.error.message
					: "could not start or reach the filesystem daemon (ollmfilesd)";
				this.disconnect();
				return false;
			}

			this.connect_error = "";
			return true;
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
		 * Runs {@link connect} then sends the request.
		 * @param request wire request; {@link OLLMrpc.Request.id} is set here
		 * @return wire response; check {@link OLLMrpc.Response.error}, or connect
		 *   to {@link failed} for user-visible handling
		 */
		public async OLLMrpc.Response call(OLLMrpc.Request request)
		{
			yield this.connect();
			request.id = this.next_id++;
			if (!this.connected || this.output == null) {
				var error = new OLLMrpc.Error(
					OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
					"not connected",
					request.method,
					request.id
				);
				GLib.warning(
					"RpcClient: %s id=%d: %s",
					request.method,
					request.id,
					error.message
				);
				this.failed(request, error);
				return new OLLMrpc.Response(request.id) { error = error };
			}

			var promise = new GLib.Promise<OLLMrpc.Response>();
			this.pending.set(request.id, promise);

			size_t length;
			var line = Json.gobject_to_data(request, out length) + "\n";
			try {
				this.output.put_string(line);
				yield this.output.flush_async(GLib.Priority.DEFAULT, null);
			} catch (GLib.Error e) {
				this.pending.unset(request.id);
				var error = new OLLMrpc.Error(
					OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
					"write: " + e.message,
					request.method,
					request.id
				);
				GLib.warning(
					"RpcClient: %s id=%d: %s",
					request.method,
					request.id,
					error.message
				);
				this.failed(request, error);
				return new OLLMrpc.Response(request.id) { error = error };
			}

			var response = yield this.wait_response(
				request.id,
				request.method,
				promise
			);
			if (response.error != null) {
				GLib.warning(
					"RpcClient: %s id=%d: %s",
					request.method,
					request.id,
					response.error.message
				);
				this.failed(request, response.error);
			}
			return response;
		}

		private async OLLMrpc.Response wait_response(
			int id,
			string method,
			GLib.Promise<OLLMrpc.Response> promise
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
				string msg = cancellable.is_cancelled()
					? "call timed out"
					: e.message;
				return new OLLMrpc.Response(id) {
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						msg,
						method,
						id
					)
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
					typeof(OLLMrpc.Notification), data
				) as OLLMrpc.Notification;
				if (notif != null) {
					this.notification(notif);
				}
				return;
			}

			var response = Json.gobject_from_data(
				typeof(OLLMrpc.Response), data
			) as OLLMrpc.Response;
			if (response == null) {
				return;
			}
			if (!this.pending.has_key(response.id)) {
				GLib.warning("RpcClient unexpected response id %d", response.id);
				return;
			}

			if (response.result_type == "") {
				this.pending.get(response.id).resolve(response);
				this.pending.unset(response.id);
				return;
			}

			var result_node = obj.get_member("result");
			var t = OLLMrpc.types.get(response.result_type);
			if (!response.is_array) {
				response.result = Json.gobject_deserialize(t, result_node);
				this.pending.get(response.id).resolve(response);
				this.pending.unset(response.id);
				return;
			}

			var arr = result_node.get_array();
			var list = new Gee.ArrayList<GLib.Object>();
			for (uint i = 0; i < arr.get_length(); i++) {
				list.add(Json.gobject_deserialize(t, arr.get_element(i)));
			}
			response.result = list;
			this.pending.get(response.id).resolve(response);
			this.pending.unset(response.id);
		}
	}
}
