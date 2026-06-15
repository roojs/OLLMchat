namespace OLLMrpc
{
	/**
	 * NDJSON JSON-RPC client for {@code ollmfilesd} over TCP on Windows.
	 *
	 * Windows does not ship the Unix-socket transport used by Linux.
	 * The default endpoint is loopback TCP on port 4141; callers may pass
	 * either {{{host:port}}} or {{{tcp://host:port}}}.
	 */
	public class Client : GLib.Object
	{
		public string socket { get; construct; }

		public uint call_timeout_seconds { get; set; default = 120; }

		public bool connected { get; private set; default = false; }

		public string connect_error { get; private set; default = ""; }

		public signal void notification(Notification notif);

		public signal void failed(Request request, Error error);

		private GLib.SocketConnection? connection;
		private GLib.DataInputStream? input;
		private GLib.DataOutputStream? output;
		private int next_id = 1;
		private Gee.HashMap<int, Gee.Promise<Response>> pending {
			get; private set;
			default = new Gee.HashMap<int, Gee.Promise<Response>>();
		}

		static construct
		{
			Error.rpc_register();
			Notification.rpc_register();
		}

		public Client(string socket = "")
		{
			var endpoint = socket;
			if (endpoint == "") {
				endpoint = "127.0.0.1:4141";
			}
			if (endpoint.has_prefix("tcp://")) {
				endpoint = endpoint.substring(6);
			}
			GLib.Object(socket: endpoint);
		}

		public async bool connect(Request hello_request)
		{
			if (this.connected) {
				this.connect_error = "";
				return true;
			}

			hello_request.id = this.next_id++;

			var boot = new ClientBoot(this.socket);
			try {
				yield boot.ensure_daemon();
			} catch (GLib.IOError e) {
				this.connect_error = e.message != ""
					? e.message
					: "could not start or reach the filesystem daemon (ollmfilesd)";
				GLib.critical(
					"Client: ensure_daemon %s: %s",
					this.socket,
					this.connect_error
				);
				return false;
			}

			var client = new GLib.SocketClient();
			try {
				this.connection = yield client.connect_to_host_async(
					this.socket,
					4141,
					null
				);
			} catch (GLib.Error e) {
				this.connect_error = e.message;
				GLib.critical(
					"Client: connect %s: %s",
					this.socket,
					this.connect_error
				);
				return false;
			}

			this.input = new GLib.DataInputStream(
				this.connection.get_input_stream()
			);
			this.input.set_newline_type(GLib.DataStreamNewlineType.LF);
			this.output = new GLib.DataOutputStream(
				this.connection.get_output_stream()
			);
			this.connected = true;
			this.read_loop.begin();

			var hello_id = hello_request.id;
			var hello_promise = new Gee.Promise<Response>();
			this.pending.set(hello_id, hello_promise);

			try {
				yield this.write(hello_request);
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
			this.connect_error = "";
			foreach (var entry in this.pending.entries) {
				entry.value.set_exception(
					new GLib.IOError.FAILED("Client: disconnected")
				);
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

		private async void write(GLib.Object gobject) throws GLib.Error
		{
			var generator = new Json.Generator();
			generator.set_pretty(false);
			generator.set_root(Json.gobject_serialize(gobject));
			this.output.put_string(generator.to_data(null) + "\n");
			yield this.output.flush_async(GLib.Priority.DEFAULT, null);
		}

		public async Response call(Request request)
		{
			request.id = this.next_id++;
			if (!this.connected || this.output == null) {
				var error = new Error(
					RpcErrorCode.INTERNAL_ERROR,
					"not connected",
					request.method,
					request.id
				);
				GLib.warning(
					"Client: %s id=%d: %s",
					request.method,
					request.id,
					error.message
				);
				this.failed(request, error);
				return new Response() {
					id = request.id, error = error };
			}

			var promise = new Gee.Promise<Response>();
			this.pending.set(request.id, promise);

			try {
				yield this.write(request);
			} catch (GLib.Error e) {
				this.pending.unset(request.id);
				var error = new Error(
					RpcErrorCode.INTERNAL_ERROR,
					"write: " + e.message,
					request.method,
					request.id
				);
				GLib.warning(
					"Client: %s id=%d: %s",
					request.method,
					request.id,
					error.message
				);
				this.failed(request, error);
				return new Response() { id = request.id, error = error };
			}

			var response = yield this.wait_response(
				request.id,
				request.method,
				promise
			);
			if (response.error != null) {
				GLib.warning(
					"Client: %s id=%d: %s",
					request.method,
					request.id,
					response.error.message
				);
				this.failed(request, response.error);
			}
			return response;
		}

		private async Response wait_response(
			int id,
			string method,
			Gee.Promise<Response> promise
		)
		{
			var timeout_id = 0U;
			if (this.call_timeout_seconds > 0) {
				timeout_id = GLib.Timeout.add_seconds(this.call_timeout_seconds, () => {
					if (!this.pending.has_key(id)) {
						return false;
					}
					this.pending.get(id).set_exception(
						new GLib.IOError.TIMED_OUT("call timed out")
					);
					this.pending.unset(id);
					return false;
				});
			}

			try {
				return yield promise.future.wait_async();
			} catch (GLib.Error e) {
				return new Response() {
					id = id,
					error = new Error(
						RpcErrorCode.INTERNAL_ERROR,
						e.message,
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
					GLib.warning("Client read error: %s", e.message);
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
				GLib.warning("Client invalid JSON: %s", e.message);
				return;
			}

			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				GLib.warning("Client line not a JSON object");
				return;
			}
			var obj = root.get_object();

			if (!obj.has_member("id")) {
				var notif = Json.gobject_from_data(
					typeof(Notification), data
				) as Notification;
				if (notif != null) {
					this.notification(notif);
				}
				return;
			}

			var response = Json.gobject_from_data(
				typeof(Response), data
			) as Response;
			if (response == null) {
				return;
			}
			if (!this.pending.has_key(response.id)) {
				GLib.warning("Client unexpected response id %d", response.id);
				return;
			}

			if (response.result_type == "") {
				this.pending.get(response.id).set_value(response);
				this.pending.unset(response.id);
				return;
			}

			var result_node = obj.get_member("result");
			var t = types.get(response.result_type);
			if (!response.is_array) {
				response.result = Json.gobject_deserialize(t, result_node);
				this.pending.get(response.id).set_value(response);
				this.pending.unset(response.id);
				return;
			}

			var arr = result_node.get_array();
			var list = new Gee.ArrayList<GLib.Object>();
			for (var i = 0U; i < arr.get_length(); i++) {
				list.add(Json.gobject_deserialize(t, arr.get_element(i)));
			}
			response.result = list;
			this.pending.get(response.id).set_value(response);
			this.pending.unset(response.id);
		}
	}
}
