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

namespace OLLMrpc
{
	private class PendingWrite : GLib.Object
	{
		public Request request { get; construct; }
		public Gee.Promise<Response> promise { get; construct; }
		public bool sent { get; set; default = false; }

		public PendingWrite(Request request)
		{
			Object(
				request: request,
				promise: new Gee.Promise<Response>()
			);
		}
	}

	/**
	 * Bin RPC client for ollmfilesd and HTTP JSON APIs.
	 *
	 * Socket mode spawns or connects to ollmfilesd, then exchanges bin
	 * Request/Response pairs. HTTP mode (socket_path is an https URL) sends
	 * JSON REST calls — used by libochf for Hugging Face Hub.
	 *
	 * == ollmfilesd (Unix socket) ==
	 *
	 * {{{
	 * OLLMrpc.Daemon.rpc_register();
	 * OLLMfilesd.DaemonParams.rpc_register();
	 * var rpc = new OLLMrpc.Client(
	 *     GLib.Path.build_filename(
	 *         GLib.Environment.get_user_data_dir(), "ollmchat"),
	 *     "ollmfilesd.pid",
	 *     "ollmfilesd.sock"
	 * );
	 * if (!yield rpc.connect(new OLLMrpc.Request() {
	 *     method = "Daemon.hello",
	 *     param = new OLLMfilesd.DaemonParams() {
	 *         protocol = 1,
	 *         client = "my-app"
	 *     }
	 * })) {
	 *     GLib.error("%s", rpc.connect_error);
	 * }
	 * var resp = yield rpc.call(new OLLMrpc.Request() {
	 *     method = "ProjectManager.load_projects_from_db",
	 *     param = new OLLMfilesd.ProjectParams()
	 * });
	 * }}}
	 *
	 * == Hugging Face Hub (HTTPS) ==
	 *
	 * {{{
	 * OLLMhf.rpc_register();
	 * var rpc = new OLLMrpc.Client("", "", "https://huggingface.co");
	 * yield rpc.connect(new OLLMrpc.Request());
	 * var resp = yield rpc.call(new OLLMrpc.Request() {
	 *     method = "/api/models",
	 *     param = new OLLMhf.Param.Search() {
	 *         search = "llama",
	 *         filter = "gguf",
	 *         limit = 10
	 *     },
	 *     result_type = typeof(OLLMhf.ModelArray)
	 * });
	 * }}}
	 */
	public class Client : GLib.Object
	{
		public enum Protocol {
			SOCKET,
			STDIO,
			TCP,
			HTTP,
		}

		public string socket_path { get; construct; }

		public Protocol protocol { get; private set; }

		public string data_dir { get; construct; }

		public string pid { get; construct; }

		/**
		 * When true (default), {@link connect} forwards to {@link ClientBoot} and
		 * spawn passes ''--debug'' to ollmfilesd. Set in the object
		 * initializer when not using the default.
		 */
		public bool debug { get; set; default = true; }

		/**
		 * When true, spawn passes ''--data-dir=data_dir''; vector test CLIs only.
		 * Set in the object initializer when needed.
		 */
		public bool pass_data_dir { get; set; default = false; }

		/** Seconds to wait for a matching {@link Response} id. */
		public uint call_timeout_seconds { get; set; default = 120; }

		public bool connected { get; private set; default = false; }

		public Bin.Stream? bin { get; private set; }

		/**
		 * Last {@link connect} failure (boot, socket, or hello).
		 * Empty when {@link connected} is true. UI reads this from {@link Client}.
		 */
		public string connect_error { get; private set; default = ""; }

		public signal void notification(Notification notif);

		/**
		 * Emitted when {@link call} completes with a daemon
		 * {@link Response.error}. Transport timeouts and disconnects surface as
		 * {@link Response.error} and this signal; wire/protocol faults abort.
		 * {@link call} still returns the response; callers may ignore errors when
		 * the UI connects here (e.g. toast / dialog).
		 */
		public signal void failed(Request request, Error error);

		private GLib.SocketConnection? socket;
		private GLib.DataInputStream? input;
		private GLib.DataOutputStream? output;
		private int next_id = 1;
		private Gee.ArrayList<PendingWrite> pending {
			get; private set;
			default = new Gee.ArrayList<PendingWrite>();
		}
		private bool sending { get; set; default = false; }
		private GLib.IOChannel? read_channel;
		private uint read_watch_id = 0;
		private Soup.Session? http_session;
		private Bin.Json http_json = new Bin.Json(
			Bin.Mode.AUTO | Bin.Mode.AUTO_STR | Bin.Mode.IGNORE_UNKNOWN
		);

		static construct
		{
			Error.rpc_register();
			Notification.rpc_register();
			Request.rpc_register();
			Response.rpc_register();
		}

		/**
		 * @param data_dir Root directory for daemon DB, socket, and pid file.
		 *   When empty, {@link pid} and {@link socket_path} are set from {@link pid}
		 *   and {@link socket_name} verbatim (e.g. a full path or
		 *   TCP endpoint ''127.0.0.1:4141'' with the tcp URL prefix)
		 * @param pid Basename of the pid file within {@link data_dir}, or the full
		 *   pid path when {@link data_dir} is empty
		 * @param socket_name Basename of the Unix socket within {@link data_dir},
		 *   or the full connect path when {@link data_dir} is empty
		 */
		public Client(
			string data_dir,
			string pid,
			string socket_name
		)
		{
			var full_pid = pid;
			var full_socket = socket_name;
			if (data_dir != "") {
				full_pid = GLib.Path.build_filename(data_dir, pid);
				full_socket = GLib.Path.build_filename(data_dir, socket_name);
			}
			GLib.Object(
				data_dir: data_dir,
				pid: full_pid,
				socket_path: full_socket
			);
			if (this.socket_path.has_prefix("http://")
				|| this.socket_path.has_prefix("https://")) {
				this.protocol = Protocol.HTTP;
				return;
			}
			if (this.socket_path.has_prefix("tcp://")) {
				this.protocol = Protocol.TCP;
				return;
			}
			if (this.socket_path == "stdio") {
				this.protocol = Protocol.STDIO;
				return;
			}
			this.protocol = Protocol.SOCKET;
		}

		/**
		 * Boot ollmfilesd, open the socket, and send {@link hello_request}
		 * (e.g. Daemon.hello — built by the caller, not libocrpc).
		 * @return false when the client cannot talk to the daemon (see {@link connect_error})
		 */
		public async bool connect(Request hello_request)
		{
			if (this.connected) {
				this.connect_error = "";
				return true;
			}

			if (this.protocol == Protocol.HTTP) {
				this.http_session = new Soup.Session();
				this.connected = true;
				this.connect_error = "";
				return true;
			}

			hello_request.id = this.next_id++;

			var boot_pid = this.pid;
			if (this.data_dir != "") {
				boot_pid = GLib.Path.get_basename(this.pid);
			}
			var boot_socket = this.socket_path;
			if (this.data_dir != "") {
				if (!this.socket_path.has_prefix("tcp://")) {
					boot_socket = GLib.Path.get_basename(this.socket_path);
				}
			}
			var boot = new ClientBoot(
				this.data_dir,
				boot_pid,
				boot_socket,
				this.debug,
				this.pass_data_dir
			);
			try {
				yield boot.ensure_daemon();
			} catch (GLib.IOError e) {
				this.connect_error = e.message != ""
					? e.message
					: "could not start or reach the filesystem daemon (ollmfilesd)";
				GLib.critical(
					"ensure_daemon %s: %s",
					this.socket_path,
					this.connect_error
				);
				return false;
			}

			try {
				this.socket = yield boot.connect();
			} catch (GLib.Error e) {
				this.connect_error = e.message;
				GLib.critical(
					"connect %s: %s",
					this.socket_path,
					this.connect_error
				);
				return false;
			}

			this.input = new GLib.DataInputStream(this.socket.get_input_stream());
			this.output = new GLib.DataOutputStream(this.socket.get_output_stream());
			this.bin = new Bin.Stream(this.input, this.output);
			this.connected = true;
			var fd = this.socket.get_socket().get_fd();
			this.read_channel = new GLib.IOChannel.unix_new(fd);
			this.read_channel.set_encoding(null);
			this.read_channel.set_buffered(false);
			this.read_watch_id = this.read_channel.add_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
				(source, condition) => {
					if ((condition & GLib.IOCondition.HUP) != 0
						|| (condition & GLib.IOCondition.ERR) != 0) {
						GLib.warning(
							"socket closed socket_path=%s pending=%u hup=%s err=%s",
							this.socket_path,
							this.pending.size,
							((condition & GLib.IOCondition.HUP) != 0).to_string(),
							((condition & GLib.IOCondition.ERR) != 0).to_string()
						);
						this.disconnect();
						return false;
					}
					if ((condition & GLib.IOCondition.IN) == 0) {
						return this.connected;
					}
					if (!this.connected || this.bin == null) {
						return this.connected;
					}
					do {
						if (!this.connected || this.bin == null) {
							break;
						}
						try {
							var msg = this.bin.parse();
							this.dispatch_message(msg);
						} catch (GLib.IOError e) {
							GLib.error("%s", e.message);
						} catch (GLib.Error e) {
							GLib.error("%s", e.message);
						}
					} while (
						(source.get_buffer_condition() & GLib.IOCondition.IN) != 0
					);
					return this.connected;
				}
			);
			GLib.debug("read watch started");

			var entry = new PendingWrite(hello_request);
			this.pending.add(entry);
			this.send_head.begin();

			Response hello;
			try {
				hello = yield this.wait_response(
					entry,
					hello_request.method
				);
			} catch (GLib.Error e) {
				this.connect_error = e.message != ""
					? e.message
					: "could not start or reach the filesystem daemon (ollmfilesd)";
				GLib.critical(
					"connect hello %s id=%d: %s",
					hello_request.method,
					hello_request.id,
					this.connect_error
				);
				this.disconnect();
				return false;
			}
			if (hello.error != null) {
				this.connect_error = hello.error.message != ""
					? hello.error.message
					: "could not start or reach the filesystem daemon (ollmfilesd)";
				GLib.critical(
					"hello failed id=%d: %s",
					hello_request.id,
					this.connect_error
				);
				this.disconnect();
				return false;
			}

			GLib.debug("connect ok hello id=%d", hello_request.id);
			this.connect_error = "";
			return true;
		}

		public void disconnect()
		{
			if (!this.connected) {
				return;
			}
			if (this.pending.size > 0) {
				GLib.error(
					"disconnected with %u pending RPC call(s)",
					this.pending.size
				);
			}
			GLib.debug(
				"disconnect socket_path=%s pending=%u",
				this.socket_path,
				this.pending.size
			);
			this.sending = false;
			this.connected = false;
			if (this.read_watch_id != 0) {
				GLib.Source.remove(this.read_watch_id);
				this.read_watch_id = 0;
			}
			this.read_channel = null;
			foreach (var entry in this.pending) {
				GLib.warning(
					"disconnect abort %s id=%d socket_path=%s",
					entry.request.method,
					entry.request.id,
					this.socket_path
				);
				entry.promise.set_exception(
					new GLib.IOError.FAILED("Client: disconnected")
				);
			}
			this.pending.clear();
			this.bin = null;
			this.input = null;
			this.output = null;
			if (this.socket != null) {
				try {
					this.socket.close();
				} catch (GLib.Error e) {
				}
				this.socket = null;
			}
		}

		private async void send_http(PendingWrite head) throws GLib.Error
		{
			GLib.debug(
				"id=%d send path=%s param=%s result_type=%s",
				head.request.id,
				head.request.method,
				head.request.param.get_type().name(),
				head.request.result_type.name()
			);
			var qs = "";
			foreach (var pspec in head.request.param.get_class().list_properties()) {
				if (pspec.name == "args") {
					continue;
				}
				var val = Value(pspec.value_type);
				head.request.param.get_property(pspec.name, ref val);
				switch (val.type()) {
					case GLib.Type.STRING:
						var s = val.get_string();
						if (s == "") {
							continue;
						}
						qs += (qs == "" ? "?" : "&")
							+ GLib.Uri.escape_string(pspec.name, null)
							+ "=" + GLib.Uri.escape_string(s, null);
						break;
					case GLib.Type.INT:
						qs += (qs == "" ? "?" : "&")
							+ GLib.Uri.escape_string(pspec.name, null)
							+ "=" + val.get_int().to_string();
						break;
					case GLib.Type.BOOLEAN:
						if (!val.get_boolean()) {
							continue;
						}
						qs += (qs == "" ? "?" : "&")
							+ GLib.Uri.escape_string(pspec.name, null)
							+ "=true";
						break;
				}
			}
			var url = this.socket_path + head.request.method + qs;
			GLib.debug("id=%d send url=%s", head.request.id, url);
			var message = new Soup.Message("GET", url);
			var bytes = yield this.http_session.send_and_read_async(
				message, GLib.Priority.DEFAULT, null);
			var body = (string) bytes.get_data();
			GLib.debug(
				"id=%d recv status=%u bytes=%zu",
				head.request.id,
				message.status_code,
				bytes.get_size()
			);
			GLib.debug("id=%d recv body=%s", head.request.id, body);
			if (message.status_code < 200 || message.status_code >= 300) {
				throw new GLib.IOError.FAILED("HTTP %u for %s", message.status_code, url);
			}
			if (head.request.result_type == GLib.Type.INVALID) {
				throw new Bin.StreamError.PROTOCOL("HTTP call missing result_type");
			}
			var parser = new Json.Parser();
			parser.load_from_data((string) bytes.get_data());
			var root = parser.get_root();
			if (root.get_node_type() == Json.NodeType.ARRAY) {
				var wrap = new Json.Object();
				wrap.set_array_member("items", root.get_array());
				root = new Json.Node(Json.NodeType.OBJECT);
				root.set_object(wrap);
			}
			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new Bin.StreamError.PROTOCOL("HTTP JSON root must be object or array");
			}
			var mem = new GLib.MemoryOutputStream.resizable();
			var encode_ctx = new Bin.Stream(null, new GLib.DataOutputStream(mem));
			this.http_json.json_to_bin(root.get_object(), encode_ctx, head.request.result_type);
			encode_ctx.out_stream.close();
			var read_ctx = new Bin.Stream(new GLib.DataInputStream(
				new GLib.MemoryInputStream.from_bytes(mem.steal_as_bytes())), null);
			read_ctx.mode = this.http_json.mode;
			var obj = read_ctx.parse();
			var response = new Response() {
				id = head.request.id,
			};
			response.result.add(obj);
			this.complete_pending(head.request.id, response, null);
		}

		private async void send_head()
		{
			if (this.sending) {
				return;
			}
			if (this.pending.size == 0) {
				return;
			}
			var head = this.pending.get(0);
			if (head.sent) {
				return;
			}
			if (!this.connected) {
				return;
			}
			this.sending = true;
			if (this.protocol == Protocol.HTTP) {
				try {
					yield this.send_http(head);
					head.sent = true;
				} catch (GLib.Error e) {
					this.complete_pending(head.request.id, null, e);
				}
				this.sending = false;
				if (this.pending.size > 0
					&& !this.pending.get(0).sent) {
					this.send_head.begin();
				}
				return;
			}
			try {
				GLib.debug("id=%d method=%s", head.request.id, head.request.method);
				this.bin.write(head.request);
				yield this.output.flush_async(GLib.Priority.DEFAULT, null);
				head.sent = true;
			} catch (GLib.Error e) {
				this.complete_pending(head.request.id, null, e);
			}
			this.sending = false;
			if (this.pending.size > 0
				&& !this.pending.get(0).sent) {
				this.send_head.begin();
			}
		}

		private void complete_pending(
			int id,
			Response? response,
			GLib.Error? error
		)
		{
			for (var i = 0; i < this.pending.size; i++) {
				if (this.pending.get(i).request.id != id) {
					continue;
				}
				var entry = this.pending.get(i);
				this.pending.remove_at(i);
				if (error != null) {
					GLib.critical(
						"RPC failed %s id=%d: %s",
						entry.request.method,
						id,
						error.message
					);
					entry.promise.set_exception(error);
				} else {
					entry.promise.set_value(response);
				}
				this.send_head.begin();
				return;
			}
		}

		/**
		 * Send a request (caller must {@link connect} first).
		 *
		 * Assign a typed {@link CallParam} subclass to {@link Request.param}
		 * before calling; see {@link Request} for wire serialize rules.
		 *
		 * @param request wire request; {@link Request.id} is set here
		 * @return wire response; check {@link Response.error}, or connect
		 *   to {@link failed} for user-visible handling
		 */
		public async Response call(Request request)
		{
			request.id = this.next_id++;
			if (!this.connected) {
				GLib.error(
					"%s id=%d: not connected",
					request.method,
					request.id
				);
			}

			var entry = new PendingWrite(request);
			this.pending.add(entry);
			this.send_head.begin();

			Response response;
			try {
				response = yield this.wait_response(entry, request.method);
			} catch (GLib.Error e) {
				var transport_error = new Error(
					(int) RpcErrorCode.INTERNAL_ERROR,
					e.message
				);
				this.failed(request, transport_error);
				return new Response() {
					id = request.id,
					error = transport_error
				};
			}
			if (response.error != null) {
				GLib.warning(
					"%s id=%d: %s",
					request.method,
					request.id,
					response.error.message
				);
				this.failed(request, response.error);
			}
			return response;
		}

		private async Response wait_response(
			PendingWrite entry,
			string method
		) throws GLib.Error
		{
			var timeout_id = 0U;
			if (this.call_timeout_seconds > 0) {
				timeout_id = GLib.Timeout.add_seconds(
					this.call_timeout_seconds,
					() => {
						GLib.warning(
							"call timed out %s id=%d after %u s",
							entry.request.method,
							entry.request.id,
							this.call_timeout_seconds
						);
						this.complete_pending(
							entry.request.id,
							null,
							new GLib.IOError.TIMED_OUT("call timed out")
						);
						return false;
					}
				);
			}

			try {
				return yield entry.promise.future.wait_async();
			} finally {
				if (timeout_id != 0) {
					GLib.Source.remove(timeout_id);
				}
			}
		}

		private void dispatch_message(Bin.Serializable msg)
		{
			var response = msg as Response;
			if (response != null) {
				var found = false;
				foreach (var entry in this.pending) {
					if (entry.request.id != response.id) {
						continue;
					}
					found = true;
					break;
				}
				if (!found) {
					GLib.error(
						"unexpected response id %d",
						response.id
					);
				}
				if (response.error != null) {
					GLib.debug(
						"replied id=%d error=%s",
						response.id,
						response.error.message
					);
				}
				if (response.error == null) {
					GLib.debug ("replied id=%d", response.id);
				}
				this.complete_pending(response.id, response, null);
				return;
			}

			var notif = msg as Notification;
			if (notif != null) {
				GLib.debug(
					"notification method=%s object_type=%s",
					notif.method,
					notif.object_type
				);
				this.notification(notif);
				return;
			}

			GLib.error("unexpected wire message type");
		}
	}
}
