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
	private class PendingWrite : GLib.Object
	{
		public GLib.Object payload { get; construct; }
		public Gee.Promise<bool> done { get; construct; }

		public PendingWrite(GLib.Object payload)
		{
			Object(
				payload: payload,
				done: new Gee.Promise<bool>()
			);
		}
	}

	/**
	 * Bin RPC client for {@code ollmfilesd}.
	 * {@link connect} runs {@link ClientBoot.ensure_daemon} when the
	 * platform transport needs a local daemon starter.
	 *
	 * A socket {@link GLib.IOChannel} watch dispatches inbound
	 * {@link Notification} lines and resolves pending {@link Response}
	 * entries by id.
	 * {@link call} sends a {@link Request} and yields until that
	 * id is filled in or {@link call_timeout_seconds} elapses.
	 * Outgoing lines are queued — one {@code flush_async} at a time on
	 * the shared output stream; many requests may still be in flight.
	 * Transport and client faults return {@link Response.error}; they
	 * do not throw. {@link failed} is emitted for every failed {@link call};
	 * connect UI handlers there instead of per-caller logging.
	 */
	public class Client : GLib.Object
	{
		public string socket { get; construct; }
		public bool tcp { get; construct; default = false; }

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
		 * Emitted when {@link call} completes with {@link Response.error} set.
		 * Transport faults, timeouts, and daemon JSON-RPC errors all use this path.
		 * {@link call} still returns the response; callers may ignore errors when
		 * the UI connects here (e.g. toast / dialog).
		 */
		public signal void failed(Request request, Error error);

		private GLib.SocketConnection? connection;
		private GLib.DataInputStream? input;
		private GLib.DataOutputStream? output;
		private int next_id = 1;
		private Gee.HashMap<int, Gee.Promise<Response>> pending {
			get; private set;
			default = new Gee.HashMap<int, Gee.Promise<Response>>();
		}
		private Gee.ArrayList<PendingWrite> write_queue {
			get; private set;
			default = new Gee.ArrayList<PendingWrite>();
		}
		private bool write_draining { get; set; default = false; }
		private GLib.IOChannel? read_channel;
		private uint read_watch_id = 0;

		static construct
		{
			Error.rpc_register();
			Notification.rpc_register();
			Request.rpc_register();
			Response.rpc_register();
		}

		public Client(string socket = "")
		{
			var path = socket;
			var use_tcp = false;
			if (path == "") {
				path = default_client_endpoint();
			}
			if (path.has_prefix("tcp://")) {
				use_tcp = true;
				path = path.substring(6);
			}
			GLib.Object(socket: path, tcp: use_tcp);
		}

		/**
		 * Boot {@code ollmfilesd}, open the socket, and send {@link hello_request}
		 * (e.g. {@code Daemon.hello} — built by the caller, not libocrpc).
		 * @return false when the client cannot talk to the daemon (see {@link connect_error})
		 */
		public async bool connect(Request hello_request)
		{
			if (this.connected) {
				this.connect_error = "";
				return true;
			}

			hello_request.id = this.next_id++;

			GLib.debug(
				"connect begin socket=%s tcp=%s",
				this.socket,
				this.tcp ? "true" : "false"
			);

			if (client_boot_required(this.tcp)) {
				var boot = new ClientBoot(this.socket);
				try {
					yield boot.ensure_daemon();
				} catch (GLib.IOError e) {
					this.connect_error = e.message != ""
						? e.message
						: "could not start or reach the filesystem daemon (ollmfilesd)";
					GLib.critical(
						"ensure_daemon %s: %s",
						this.socket,
						this.connect_error
					);
					return false;
				}
			}

			var client = new GLib.SocketClient();
			if (this.tcp) {
				try {
					this.connection = yield client.connect_to_host_async(
						this.socket,
						4141,
						null
					);
				} catch (GLib.Error e) {
					this.connect_error = e.message;
					GLib.critical(
						"connect %s: %s",
						this.socket,
						this.connect_error
					);
					return false;
				}
			}

			if (!this.tcp) {
				try {
					this.connection = yield connect_unix_socket(this.socket);
				} catch (GLib.Error e) {
					this.connect_error = e.message;
					GLib.critical(
						"connect %s: %s",
						this.socket,
						this.connect_error
					);
					return false;
				}
			}

			this.input = new GLib.DataInputStream(this.connection.get_input_stream());
			this.output = new GLib.DataOutputStream(this.connection.get_output_stream());
			this.bin = new Bin.Stream(this.input, this.output);
			this.connected = true;
			GLib.debug("socket open tcp=%s", this.tcp ? "true" : "false");
			var fd = this.connection.get_socket().get_fd();
			this.read_channel = new GLib.IOChannel.unix_new(fd);
			this.read_channel.set_encoding(null);
			this.read_channel.set_buffered(false);
			this.read_watch_id = this.read_channel.add_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
				(source, condition) => {
					if ((condition & GLib.IOCondition.HUP) != 0
						|| (condition & GLib.IOCondition.ERR) != 0) {
						GLib.debug("read watch hup or err");
						this.disconnect();
						return false;
					}
					if ((condition & GLib.IOCondition.IN) == 0) {
						return this.connected;
					}
					if (!this.connected || this.bin == null) {
						return this.connected;
					}
					try {
						var msg = this.bin.parse();
						this.dispatch_message(msg);
					} catch (GLib.IOError e) {
						GLib.debug("read io error: %s", e.message);
						this.disconnect();
						return false;
					} catch (GLib.Error e) {
						GLib.warning("read error: %s", e.message);
						this.disconnect();
						return false;
					}
					return this.connected;
				}
			);
			GLib.debug("read watch started");

			var hello_id = hello_request.id;
			var hello_promise = new Gee.Promise<Response>();
			this.pending.set(hello_id, hello_promise);
			GLib.debug(
				"hello send id=%d method=%s",
				hello_id,
				hello_request.method
			);

			try {
				yield this.write(hello_request);
			} catch (GLib.Error e) {
				this.pending.unset(hello_id);
				this.connect_error = "write: " + e.message;
				GLib.debug("hello write failed: %s", e.message);
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
				GLib.debug(
					"hello failed id=%d: %s",
					hello_id,
					this.connect_error
				);
				this.disconnect();
				return false;
			}

			GLib.debug("connect ok hello id=%d", hello_id);
			this.connect_error = "";
			return true;
		}

		public void disconnect()
		{
			if (!this.connected) {
				return;
			}
			GLib.debug(
				"disconnect socket=%s pending=%u",
				this.socket,
				this.pending.size
			);
			foreach (var job in this.write_queue) {
				job.done.set_exception(
					new GLib.IOError.FAILED("Client: disconnected")
				);
			}
			this.write_queue.clear();
			this.write_draining = false;
			this.connected = false;
			if (this.read_watch_id != 0) {
				GLib.Source.remove(this.read_watch_id);
				this.read_watch_id = 0;
			}
			this.read_channel = null;
			foreach (var entry in this.pending.entries) {
				entry.value.set_exception(
					new GLib.IOError.FAILED("Client: disconnected")
				);
			}
			this.pending.clear();
			this.bin = null;
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
			var job = new PendingWrite(gobject);
			this.write_queue.add(job);
			if (!this.write_draining) {
				this.write_draining = true;
				this.drain_writes.begin();
			}
			yield job.done.future.wait_async();
		}

		private async void drain_writes()
		{
			while (this.write_queue.size > 0) {
				var job = this.write_queue.get(0);
				this.write_queue.remove_at(0);
				if (!this.connected || this.output == null) {
					job.done.set_exception(
						new GLib.IOError.FAILED("Client: disconnected")
					);
					continue;
				}
				try {
					var serializable = job.payload as Bin.Serializable;
					if (serializable == null) {
						throw new GLib.IOError.FAILED(
							"Client: payload is not bin Serializable"
						);
					}
					var request = job.payload as Request;
					if (request != null) {
						GLib.debug(
							"send id=%d method=%s",
							request.id,
							request.method
						);
					}
					this.bin.write(serializable);
					yield this.output.flush_async(
						GLib.Priority.DEFAULT,
						null
					);
					job.done.set_value(true);
				} catch (GLib.Error e) {
					job.done.set_exception(e);
				}
			}
			this.write_draining = false;
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
			if (!this.connected || this.output == null) {
				var error = new Error(
					RpcErrorCode.INTERNAL_ERROR,
					"not connected",
					request.method,
					request.id
				);
				GLib.warning(
					"%s id=%d: %s",
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
					"%s id=%d: %s",
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

		private void dispatch_message(Bin.Serializable msg)
		{
			var response = msg as Response;
			if (response != null) {
				if (!this.pending.has_key(response.id)) {
					GLib.warning(
						"unexpected response id %d",
						response.id
					);
					return;
				}
				if (response.error != null) {
					GLib.debug(
						"replied id=%d error=%s",
						response.id,
						response.error.message
					);
				}
				if (response.error == null) {
					GLib.debug(
						"replied id=%d result_type=%s array=%s",
						response.id,
						response.result_type,
						response.is_array ? "true" : "false"
					);
				}
				var promise = this.pending.get(response.id);
				this.pending.unset(response.id);
				promise.set_value(response);
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

			GLib.warning("unexpected wire message type");
		}
	}
}
