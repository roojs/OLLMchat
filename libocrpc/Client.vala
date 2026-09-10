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

		/**
		 * Set by {@link Client.complete_pending} for {@link Client.call_sync}.
		 */
		public Response done_response { get; set; }

		public PendingWrite(Request request)
		{
			Object(
				request: request,
				promise: new Gee.Promise<Response>()
			);
		}
	}

	/**
	 * Bin RPC client for ollmfilesd, compositor sockets, and HTTPS JSON APIs.
	 *
	 * Socket mode exchanges bin {@link Request}/{@link Response} pairs.
	 * Pass a {@link ClientBoot} to {@link connect} to spawn ollmfilesd; omit it
	 * to attach to an already-listening socket. HTTP mode (''socket_name'' is
	 * an https URL, empty ''data_dir'') sends JSON REST calls — used by
	 * libochf for Hugging Face Hub. Register wire types before {@link connect}.
	 *
	 * == Basic Usage ==
	 *
	 * {{{
	 * OLLMrpc.Daemon.rpc_register();
	 * var rpc = new OLLMrpc.Client(
	 *     GLib.Path.build_filename(
	 *         GLib.Environment.get_user_data_dir(), "ollmchat"),
	 *     "ollmfilesd.pid",
	 *     "ollmfilesd.sock"
	 * );
	 * if (!yield rpc.connect(new OLLMrpc.Request() {
	 *     method = "RPC-Daemon.hello",
	 *     args = OLLMrpc.args("is", 1, "my-app")
	 * }, new OLLMrpc.ClientBoot())) {
	 *     GLib.error("%s", rpc.connect_error);
	 * }
	 * var resp = yield rpc.call(new OLLMrpc.Request() {
	 *     method = "RPC-ProjectManager.rpc_load_projects_from_db"
	 * });
	 * }}}
	 *
	 * == HTTPS ==
	 *
	 * {{{
	 * OLLMhf.rpc_register();
	 * var rpc = new OLLMrpc.Client("", "", "https://huggingface.co");
	 * yield rpc.connect(new OLLMrpc.Request());
	 * var resp = yield rpc.call(new OLLMrpc.Request() {
	 *     method = "/api/models",
	 *     args = OLLMrpc.args("o", new OLLMhf.Param.Search() {
	 *         search = "llama",
	 *         filter = "gguf",
	 *         limit = 10
	 *     }),
	 *     result_type = typeof(OLLMhf.ModelArray)
	 * });
	 * }}}
	 *
	 * @see Request
	 * @see Response
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
		 * Copied onto a blank {@link ClientBoot} in {@link connect}. When true
		 * (default), spawn passes ''--debug'' to ollmfilesd.
		 */
		public bool debug { get; set; default = true; }

		/**
		 * When true, spawn passes ''--data-dir=data_dir''; vector test CLIs only.
		 * Set in the object initializer when needed.
		 */
		public bool pass_data_dir { get; set; default = false; }

		public bool live_handles { get; set; default = false; }

		/**
		 * Handle id → local proxy when {@link live_handles} is on.
		 *
		 * The app inserts after it constructs the proxy
		 * ({@link Gee.HashMap.set}) and removes on closed
		 * ({@link Gee.HashMap.unset}). Inbound ''notify::'' notifications
		 * call {@link GLib.Object.set_property} from
		 * {@link Notification.message}. Unbound ids still emit
		 * {@link notification}.
		 *
		 * {@link Bin.Stream.parse_object} also inserts the decoded
		 * proxy here. The wire lease is {@link Live.Handle.rpc_lid}
		 * on the object (construct property ''rpc-lid''). This map
		 * stays the notify table.
		 *
		 * == Example ==
		 *
		 * {{{
		 * rpc.proxies.set(notif.id, win);
		 * rpc.proxies.unset(notif.id);
		 * }}}
		 */
		public Gee.HashMap<int, GLib.Object> proxies {
			get; set; default = new Gee.HashMap<int, GLib.Object>();
		}

		/** Seconds to wait for a matching {@link Response} id. */
		public uint call_timeout_seconds { get; set; default = 120; }

		public bool connected { get; private set; default = false; }

		public Bin.Stream? bin { get; private set; }

		public Live.BufferStream? buffer_stream { get; private set; default = null; }

		/**
		 * Last {@link connect} failure (boot, socket, or hello).
		 * Empty when {@link connected} is true. UI reads this from {@link Client}.
		 */
		public string connect_error { get; private set; default = ""; }

		public signal void notification(Notification notif);

		/**
		 * Server → client GI callback invoke (not a {@link Notification}).
		 *
		 * @param call packed callback id, reply id, and arguments
		 */
		public signal void invoke(Live.Invoke call);

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
			get; private set; default = new Gee.ArrayList<PendingWrite>();
		}
		private bool sending { get; set; default = false; }
		private GLib.IOChannel? read_channel;
		private uint read_watch_id = 0;
		/** Private context shared across outer and nested {@link call_sync} frames. */
		private GLib.MainContext? sync_context;
		/** Innermost {@link GLib.MainLoop} while {@link call_sync} waits. */
		private GLib.MainLoop? sync_loop;
		/** Nesting depth of {@link call_sync} on {@link sync_context} (0 = idle). */
		private int sync_depth = 0;
		/** Nesting depth of {@link call_poll} (0 = idle). */
		private int poll_depth = 0;
		private Soup.Session? http_session;
		private Bin.Json http_json = new Bin.Json(
			Bin.Mode.AUTO | Bin.Mode.AUTO_STR | Bin.Mode.IGNORE_UNKNOWN
		);

		static construct
		{
			Error.rpc_register();
			Notification.rpc_register();
			OLLMrpc.Live.Invoke.rpc_register();
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
		 * Open the channel and send {@link hello_request}
		 * (e.g. Daemon.hello — built by the caller, not libocrpc).
		 *
		 * When ''boot'' is set, empty path and flag fields are copied from
		 * this client, then {@link ClientBoot.ensure_daemon} runs before the
		 * socket opens. When ''boot'' is ''null'', connect to
		 * {@link socket_path} only — no spawn.
		 *
		 * @param hello_request first request on the channel
		 * @param boot ollmfilesd spawn/probe, or ''null'' to attach only
		 * @return false when the client cannot talk to the server (see {@link connect_error})
		 */
		public async bool connect(Request hello_request, ClientBoot? boot = null)
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

			if (boot != null) {
				var blank = boot.data_dir == "" && boot.pid == "" && boot.socket_path == "";
				if (boot.data_dir == "") {
					boot.data_dir = this.data_dir;
				}
				if (boot.pid == "") {
					boot.pid = this.pid;
				}
				if (boot.socket_path == "") {
					boot.socket_path = this.socket_path;
				}
				if (blank) {
					boot.debug = this.debug;
					boot.pass_data_dir = this.pass_data_dir;
				}
				try {
					yield boot.ensure_daemon();
					this.socket = yield boot.connect();
				} catch (GLib.Error e) {
					this.connect_error = e.message != ""
						? e.message
						: "could not start or reach the filesystem daemon (ollmfilesd)";
					GLib.critical("connect %s: %s",
						this.socket_path, this.connect_error);
					return false;
				}
			} else {
				var client = new GLib.SocketClient();
				switch (this.protocol) {
					case Protocol.TCP:
						var endpoint = this.socket_path.substring(6);
						var host = endpoint;
						var port = 4141;
						var colon = endpoint.last_index_of(":");
						if (colon > 0) {
							host = endpoint[0:colon];
							int.try_parse(endpoint.substring(colon + 1), out port);
						}
						try {
							this.socket = yield client.connect_to_host_async(
								host, port, null);
						} catch (GLib.Error e) {
							this.connect_error = e.message;
							GLib.critical("connect %s: %s",
								this.socket_path, this.connect_error);
							return false;
						}
						break;

					default:
#if G_OS_WIN32 || ANDROID
						this.connect_error = "unix sockets are not available";
						GLib.critical("connect %s: %s",
							this.socket_path, this.connect_error);
						return false;
#else
						try {
							this.socket = yield client.connect_async(
								new GLib.UnixSocketAddress(this.socket_path),
								null
							);
						} catch (GLib.Error e) {
							this.connect_error = e.message;
							GLib.critical("connect %s: %s",
								this.socket_path, this.connect_error);
							return false;
						}
#endif
						break;
				}
			}

			this.input = new GLib.DataInputStream(this.socket.get_input_stream());
			this.output = new GLib.DataOutputStream(this.socket.get_output_stream());
			this.bin = new Bin.Stream(this.input, this.output) {
				client = this
			};
			if (this.live_handles && !this.socket_path.has_prefix("tcp://")) {
				this.buffer_stream = new Live.BufferStream();
				yield this.buffer_stream.connect_client(this.socket_path);
			}
			this.connected = true;
#if ANDROID
			this.connect_error = "unix IO watch is not available";
			GLib.critical("connect %s: %s",
				this.socket_path, this.connect_error);
			this.disconnect();
			return false;
#else
			var fd = this.socket.get_socket().get_fd();
			this.read_channel = new GLib.IOChannel.unix_new(fd);
			this.read_channel.set_encoding(null);
			this.read_channel.set_buffered(false);
			this.read_watch_id = this.read_channel.add_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
				this.on_read
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
#endif
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
				GLib.warning("disconnect abort %s id=%d socket_path=%s",
					entry.request.method, entry.request.id, this.socket_path);
				entry.done_response = new Response() {
					id = entry.request.id,
					error = new Error((int) RpcErrorCode.INTERNAL_ERROR, "Client: disconnected")
				};
				entry.promise.set_value(entry.done_response);
			}
			this.pending.clear();
			this.proxies.clear();
			this.bin = null;
			this.input = null;
			this.output = null;
			if (this.buffer_stream != null) {
				this.buffer_stream.close();
				this.buffer_stream = null;
			}
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
			var query_obj = head.request.args.get(0).get_object();
			GLib.debug(
				"id=%d send path=%s param=%s result_type=%s",
				head.request.id,
				head.request.method,
				query_obj.get_type().name(),
				head.request.result_type.name()
			);
			var qs = "";
			foreach (var pspec in query_obj.get_class().list_properties()) {
				var val = Value(pspec.value_type);
				query_obj.get_property(pspec.name, ref val);
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
				throw new GLib.IOError.FAILED("HTTP %u for %s: %s",
					message.status_code, url, body.strip());
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
				retval = OLLMrpc.val("o", obj)
			};
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
					GLib.critical("RPC failed %s id=%d: %s",
						entry.request.method, id, error.message);
					entry.done_response = new Response() {
						id = entry.request.id,
						error = new Error((int) RpcErrorCode.INTERNAL_ERROR, error.message)
					};
					entry.promise.set_value(entry.done_response);
				} else {
					entry.done_response = response;
					entry.promise.set_value(response);
				}
				if (this.sync_loop != null) {
					this.sync_loop.quit();
				} else if (this.poll_depth == 0) {
					this.send_head.begin();
				}
				return;
			}
		}

		/**
		 * Parse and dispatch buffered socket messages recursively.
		 *
		 * @param source RPC socket channel
		 * @return {@code true} when the buffer has no more readable data
		 */
		private bool poll_drain_readable(GLib.IOChannel source)
		{
			if (!this.connected || this.bin == null) {
				return true;
			}
			try {
				var msg = this.bin.parse();
				this.dispatch_message(msg);
			} catch (GLib.IOError e) {
				GLib.error("%s", e.message);
			} catch (GLib.Error e) {
				GLib.error("%s", e.message);
			}
			if ((source.get_buffer_condition() & GLib.IOCondition.IN) != 0) {
				return this.poll_drain_readable(source);
			}
			return true;
		}

		/**
		 * Socket read watch for {@link connect} and {@link call_sync}.
		 *
		 * @param source RPC socket channel
		 * @param condition readiness bits from the main loop
		 * @return whether to keep the watch
		 */
		private bool on_read(GLib.IOChannel source, GLib.IOCondition condition)
		{
			if ((condition & GLib.IOCondition.HUP) != 0 || (condition & GLib.IOCondition.ERR) != 0) {
				GLib.warning("socket closed socket_path=%s pending=%u hup=%s err=%s",
					this.socket_path, this.pending.size,
					((condition & GLib.IOCondition.HUP) != 0).to_string(),
					((condition & GLib.IOCondition.ERR) != 0).to_string());
				this.disconnect();
				return false;
			}
			if ((condition & GLib.IOCondition.IN) == 0) {
				return this.connected;
			}
			if (!this.connected || this.bin == null) {
				return this.connected;
			}
			this.poll_drain_readable(source);
			return this.connected;
		}

		/**
		 * Send a request (caller must {@link connect} first).
		 *
		 * Assign positional {@link Request.args} (via {@link args}) before
		 * calling; see {@link Request} for wire serialize rules.
		 *
		 * @param request wire request; {@link Request.id} is set here
		 * @return wire response on success
		 * @throws GLib.Error the error from the function or {@link RpcErrorCode};
		 *   the transport error on disconnect / timeout
		 */
		public async Response call(Request request) throws GLib.Error
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
				transport_error.domain = e.domain.to_string();
				transport_error.gerror_code = e.code;
				this.failed(request, transport_error);
				throw e;
			}
			if (response.error == null) {
				return response;
			}
			GLib.warning("%s id=%d: %s",
				request.method, request.id, response.error.message);
			this.failed(request, response.error);
			var quark = GLib.Quark.from_string(response.error.domain);
			var code = response.error.gerror_code;
			if (response.error.domain == "") {
				quark = new RpcErrorCode.INTERNAL_ERROR("").domain;
				code = response.error.code;
			}
			throw new GLib.Error.literal(quark, code, response.error.message);
		}

		/**
		 * Blocking {@link call} that does not iterate the default
		 * {@link GLib.MainContext}.
		 *
		 * Attaches a per-frame read watch (and call timeout) to a private
		 * {@link sync_context} and runs only that loop until this request
		 * completes. Does not {@link GLib.MainContext.push_thread_default}
		 * — that would steal Clutter/GJS idles onto the private context and
		 * drop them on teardown. Sends with a blocking flush so
		 * {@link send_head} is not required mid-call. Socket / TCP only.
		 *
		 * While an outer wait is open, a nested {@link call_sync} (e.g.
		 * {@link Live.Invoke} handler → ''RPC-Live-Callback.reply'' or a
		 * child GI request) reuses the same private context with its own
		 * IO watch and {@link GLib.MainLoop}; it must not iterate the
		 * default context. Handlers run on that private context.
		 *
		 * @param request wire request; {@link Request.id} is set here
		 * @return wire response on success
		 * @throws GLib.Error same as {@link call}
		 */
		public Response call_sync(Request request) throws GLib.Error
		{
#if ANDROID
			throw new GLib.IOError.FAILED("call_sync is not available");
#else
			if (this.protocol != Protocol.SOCKET && this.protocol != Protocol.TCP) {
				throw new GLib.IOError.FAILED("call_sync requires a socket protocol");
			}
			request.id = this.next_id++;
			if (!this.connected) {
				GLib.error("%s id=%d: not connected", request.method, request.id);
			}

			var entry = new PendingWrite(request);
			this.pending.add(entry);

			var outer = (this.sync_context == null);
			if (outer) {
				if (this.read_watch_id != 0) {
					GLib.Source.remove(this.read_watch_id);
					this.read_watch_id = 0;
				}
				this.sync_context = new GLib.MainContext();
			}

			var saved_loop = this.sync_loop;
			var my_loop = new GLib.MainLoop(this.sync_context, false);
			this.sync_loop = my_loop;

			var sync_watch = this.read_channel.create_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR
			);
			sync_watch.set_callback(this.on_read);
			sync_watch.attach(this.sync_context);

			GLib.Source? timeout_source = null;
			if (this.call_timeout_seconds > 0) {
				timeout_source = new GLib.TimeoutSource.seconds(this.call_timeout_seconds);
				timeout_source.set_callback(() => {
					GLib.warning("call timed out %s id=%d after %u s",
						entry.request.method, entry.request.id, this.call_timeout_seconds);
					this.complete_pending(
						entry.request.id, null, new GLib.IOError.TIMED_OUT("call timed out"));
					return false;
				});
				timeout_source.attach(this.sync_context);
			}

			this.sync_depth++;
			try {
				while (entry.done_response == null) {
					if (!this.sending && this.pending.size > 0) {
						var sent_one = false;
						for (var i = 0; i < this.pending.size; i++) {
							var p = this.pending.get(i);
							if (p.sent) {
								continue;
							}
							this.sending = true;
							GLib.debug("id=%d method=%s", p.request.id, p.request.method);
							this.bin.write(p.request);
							this.output.flush(null);
							p.sent = true;
							this.sending = false;
							sent_one = true;
							break;
						}
						if (sent_one) {
							continue;
						}
					}
					if (entry.done_response != null) {
						break;
					}
					my_loop.run();
				}
			} catch (GLib.Error e) {
				this.sending = false;
				this.complete_pending(
					this.pending.size > 0 ? this.pending.get(0).request.id : entry.request.id,
					null, e);
			} finally {
				this.sync_depth--;
				if (timeout_source != null) {
					timeout_source.destroy();
				}
				sync_watch.destroy();
				this.sync_loop = saved_loop;
				if (outer) {
					this.sync_context = null;
					if (this.connected && this.read_channel != null) {
						this.read_watch_id = this.read_channel.add_watch(
							GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
							this.on_read
						);
						if (this.pending.size > 0 && !this.pending.get(0).sent) {
							this.send_head.begin();
						}
					}
				}
			}

			if (entry.done_response.error == null) {
				return entry.done_response;
			}
			GLib.warning("%s id=%d: %s",
				request.method, request.id, entry.done_response.error.message);
			this.failed(request, entry.done_response.error);
			var quark = GLib.Quark.from_string(entry.done_response.error.domain);
			var code = entry.done_response.error.gerror_code;
			if (entry.done_response.error.domain == "") {
				quark = new RpcErrorCode.INTERNAL_ERROR("").domain;
				code = entry.done_response.error.code;
			}
			throw new GLib.Error.literal(quark, code, entry.done_response.error.message);
#endif
		}

		/**
		 * Leave one {@link call_poll} frame and return its
		 * response.
		 *
		 * Depth--, outer restores async read watch, then same
		 * return/throw tail as {@link call_sync}.
		 */
		private Response poll_close(Request request, PendingWrite entry) throws GLib.Error
		{
			this.poll_depth--;
			if (this.poll_depth == 0 && this.connected && this.read_channel != null) {
				this.read_watch_id = this.read_channel.add_watch(
					GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
					this.on_read
				);
				if (this.pending.size > 0 && !this.pending.get(0).sent) {
					this.send_head.begin();
				}
			}
			if (entry.done_response == null) {
				throw new GLib.IOError.FAILED("call ended without response");
			}
			if (entry.done_response.error == null) {
				return entry.done_response;
			}
			GLib.warning("%s id=%d: %s",
				request.method, request.id, entry.done_response.error.message);
			this.failed(request, entry.done_response.error);
			var quark = GLib.Quark.from_string(entry.done_response.error.domain);
			var code = entry.done_response.error.gerror_code;
			if (entry.done_response.error.domain == "") {
				quark = new RpcErrorCode.INTERNAL_ERROR("").domain;
				code = entry.done_response.error.code;
			}
			throw new GLib.Error.literal(quark, code, entry.done_response.error.message);
		}

		/**
		 * Blocking {@link call} using a manual socket poll loop.
		 *
		 * Same contract as {@link call_sync}: does not iterate the
		 * default {@link GLib.MainContext}; demuxes {@link Live.Invoke}
		 * and {@link Notification} while waiting; supports nested
		 * {@link call_poll} (e.g. invoke handler →
		 * ''RPC-Live-Callback.reply''). Socket / TCP only. Linux
		 * gnome-shell-rpc; not Windows or Android.
		 *
		 * Unlike {@link call_sync}, does not attach a private
		 * {@link GLib.MainLoop} or per-frame IO watch — nested waits
		 * recurse on the call stack and read with {@link GLib.poll}.
		 * Ends with {{{ return this.poll_close(request, entry); }}} (no
		 * {{{ try }}} / {{{ finally }}}).
		 *
		 * @param request wire request; {@link Request.id} is set here
		 * @return wire response on success
		 * @throws GLib.Error same as {@link call_sync}
		 */
		public Response call_poll(Request request) throws GLib.Error
		{
#if ANDROID
			throw new GLib.IOError.FAILED("call_poll is not available");
#else
			if (this.protocol != Protocol.SOCKET && this.protocol != Protocol.TCP) {
				throw new GLib.IOError.FAILED("call_poll requires a socket protocol");
			}
			request.id = this.next_id++;
			if (!this.connected) {
				GLib.error("%s id=%d: not connected", request.method, request.id);
			}

			var entry = new PendingWrite(request);
			this.pending.add(entry);

			if (this.poll_depth == 0 && this.read_watch_id != 0) {
				GLib.Source.remove(this.read_watch_id);
				this.read_watch_id = 0;
			}
			this.poll_depth++;

			try {
				this.sending = true;
				GLib.debug("id=%d method=%s", entry.request.id, entry.request.method);
				this.bin.write(entry.request);
				this.output.flush(null);
				entry.sent = true;
				this.sending = false;
			} catch (GLib.Error e) {
				this.sending = false;
				this.complete_pending(entry.request.id, null, e);
			}

			var poll_fd = -1;
			var poll_source = GLib.PollFD();
			if (this.read_channel != null) {
				poll_fd = this.read_channel.unix_get_fd();
				poll_source.fd = poll_fd;
				poll_source.events = GLib.IOCondition.IN | GLib.IOCondition.ERR | GLib.IOCondition.HUP;
			}

			var deadline_us = (int64) 0;
			if (this.call_timeout_seconds > 0) {
				deadline_us = GLib.get_monotonic_time()
					+ (int64) this.call_timeout_seconds * 1000000;
			}

			while (entry.done_response == null) {
				if (deadline_us > 0 && GLib.get_monotonic_time() >= deadline_us) {
					GLib.warning("call timed out %s id=%d after %u s",
						entry.request.method, entry.request.id, this.call_timeout_seconds);
					this.complete_pending(
						entry.request.id, null, new GLib.IOError.TIMED_OUT("call timed out"));
					break;
				}
				if (this.read_channel != null && (this.read_channel.get_buffer_condition() & GLib.IOCondition.IN) != 0) {
					this.poll_drain_readable(this.read_channel);
				}
				if (entry.done_response != null) {
					break;
				}
				if (poll_fd < 0) {
					GLib.error("%s id=%d: poll socket fd missing", entry.request.method, entry.request.id);
				}
				var timeout_ms = -1;
				if (deadline_us > 0) {
					var remain_us = deadline_us - GLib.get_monotonic_time();
					if (remain_us <= 0) {
						continue;
					}
					timeout_ms = (int) (remain_us / 1000);
					if (timeout_ms == 0) {
						timeout_ms = 1;
					}
				}
				var poll_fds = new GLib.PollFD[] { poll_source };
				if (GLib.poll(poll_fds, timeout_ms) <= 0) {
					continue;
				}
				if ((poll_fds[0].revents & GLib.IOCondition.ERR) != 0
					|| (poll_fds[0].revents & GLib.IOCondition.HUP) != 0) {
					GLib.warning("socket closed socket_path=%s pending=%u",
						this.socket_path, this.pending.size);
					this.disconnect();
					break;
				}
				if ((poll_fds[0].revents & GLib.IOCondition.IN) == 0) {
					continue;
				}
				this.poll_drain_readable(this.read_channel);
				if (entry.done_response != null) {
					break;
				}
			}

			return this.poll_close(request, entry);
#endif
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
				if (this.buffer_stream != null) {
					response.buffer = this.buffer_stream.take_pending();
				}
				if (response.error != null) {
					GLib.debug(
						"replied id=%d error=%s",
						response.id,
						response.error.message
					);
				}
				if (response.error == null) {
					GLib.debug("replied id=%d", response.id);
				}
				this.complete_pending(response.id, response, null);
				return;
			}

			var call = msg as Live.Invoke;
			if (call != null) {
				this.invoke(call);
				return;
			}

			var notif = msg as Notification;
			if (notif != null) {
				GLib.debug(
					"notification method=%s object_type=%s",
					notif.method,
					notif.object_type
				);
				if (this.buffer_stream != null) {
					this.buffer_stream.attach(notif);
				}
				if (this.live_handles && notif.method.has_prefix("notify::")
					&& this.proxies.has_key(notif.id)) 
				{
					var current = GLib.Value(typeof(string));
					current.set_string(notif.message);
					this.proxies.get(notif.id).set_property(
						notif.method.substring(8),
						current
					);
				}
				this.notification(notif);
				return;
			}

			GLib.error("unexpected wire message type");
		}
	}
}
