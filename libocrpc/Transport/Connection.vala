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
	 * One RPC client channel — bin read/write loop (Unix socket).
	 *
	 * Each message is one root bin object ({@link OLLMrpc.Request} inbound,
	 * {@link OLLMrpc.Response} or {@link OLLMrpc.Notification} outbound).
	 */
	public class Connection : GLib.Object
	{
		public GLib.SocketConnection? stream { get; construct; default = null; }

		public Bin.Stream? bin { get; protected set; }

		public bool live_handles { get; set; default = false; }

		public Gee.HashMap<int, GLib.Object> leases {
			get; set; default = new Gee.HashMap<int, GLib.Object>();
		}

		public Gee.HashMap<int, uint> floors { get; set; default = new Gee.HashMap<int, uint>(); }

		public Gee.HashMap<int, uint> extras { get; set; default = new Gee.HashMap<int, uint>(); }

		/**
		 * Instance pointer → lease id.
		 *
		 * Outer key is the high 32 bits of the pointer, inner
		 * key the low 32 bits, both as ''int'' bit patterns
		 * (Gee has no ''uint64'' key hash).
		 */
		public Gee.HashMap<int, Gee.HashMap<int, int>> lease_ids {
			get; set; default = new Gee.HashMap<int, Gee.HashMap<int, int>>();
		}

		/**
		 * Subscribed GObject handler ids for this connection.
		 *
		 * Outer key is the lease id. Inner map is signal or
		 * ''notify::'' name → handler id from connect.
		 */
		public Gee.HashMap<int, Gee.HashMap<string, OLLMrpc.Live.Subscription>> signal_subs {
			get; set; default = new Gee.HashMap<int, Gee.HashMap<string, OLLMrpc.Live.Subscription>>();
		}

		/**
		 * GI callback rows for this connection (id → {@link Live.Hook}).
		 */
		public Gee.HashMap<int, OLLMrpc.Live.Hook> callbacks {
			get; set; default = new Gee.HashMap<int, OLLMrpc.Live.Hook>();
		}

		public Live.BufferStream? buffer_stream { get; set; default = null; }

		/**
		 * Next lease, callback, and reply id (never 0).
		 */
		public int next_handle { get; set; default = 1; }

		protected GLib.IOChannel? channel;
		protected bool channel_open = false;
		protected uint input_watch_id = 0;
		protected bool running = false;

		public Connection(GLib.SocketConnection? stream = null)
		{
			GLib.Object(stream: stream);
		}

		/**
		 * Pin a live GObject on this connection and return its handle.
		 *
		 * Reuses the same id while the object is still leased. Records
		 * {@link GLib.Object.ref_count} as the unref floor, then takes one
		 * table ref above that floor.
		 *
		 * @param gobject instance to lease
		 * @return connection-local handle (never 0)
		 */
		public uint64 export(GLib.Object gobject)
		{
			var ptr = (uint64) (void*) gobject;
			var hi = (int) (ptr >> 32);
			var lo = (int) ptr;
			if (!this.lease_ids.has_key(hi)) {
				this.lease_ids.set(hi, new Gee.HashMap<int, int>());
			}
			if (this.lease_ids.get(hi).has_key(lo)) {
				return (uint64) this.lease_ids.get(hi).get(lo);
			}
			var id = this.next_handle;
			this.next_handle++;
			this.floors.set(id, gobject.ref_count);
			this.leases.set(id, gobject);
			this.lease_ids.get(hi).set(lo, id);
			this.extras.set(id, 0);
			return (uint64) id;
		}

		public virtual void start()
		{
			if (this.running || this.stream == null) {
				return;
			}
			this.running = true;
			try {
				var fd = this.stream.get_socket().get_fd();
				this.channel = new GLib.IOChannel.unix_new(fd);
				this.channel.set_encoding(null);
				this.channel.set_buffered(false);
				this.channel_open = true;
				this.input_watch_id = this.channel.add_watch(
					GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
					this.on_input_ready
				);
				var in_stream = new GLib.DataInputStream(
					this.stream.get_input_stream()
				);
				var out_stream = new GLib.DataOutputStream(
					this.stream.get_output_stream()
				);
				this.bin = new Bin.Stream(in_stream, out_stream, true) {
					connection = this
				};
			} catch (GLib.Error e) {
				GLib.warning("connection setup failed: %s", e.message);
				this.stop();
			}
		}

		public virtual void stop()
		{
			foreach (var id in this.signal_subs.keys) {
				foreach (var name in this.signal_subs.get(id).keys) {
					GLib.SignalHandler.disconnect(this.leases.get(id), this.signal_subs.get(id).get(name).hid);
				}
			}
			this.signal_subs.clear();
			foreach (var id in this.callbacks.keys) {
				this.callbacks.get(id).replied = true;
			}
			this.callbacks.clear();
			foreach (var id in this.leases.keys) {
				for (var i = 0u; i < this.extras.get(id); i++) {
					this.leases.get(id).unref();
				}
			}
			this.leases.clear();
			this.floors.clear();
			this.extras.clear();
			this.lease_ids.clear();
			if (this.buffer_stream != null) {
				this.buffer_stream.close();
			}
			if (!this.running) {
				return;
			}
			this.running = false;
			this.channel_open = false;
			this.bin = null;
			if (this.input_watch_id != 0) {
				GLib.Source.remove(this.input_watch_id);
				this.input_watch_id = 0;
			}
			this.channel = null;
			if (this.stream != null) {
				try {
					this.stream.close();
				} catch (GLib.Error e) {
				}
			}
		}

		public virtual void write(
			GLib.Object gobject,
			Live.Buffer? buffer = null
		)
		{
			if (!this.channel_open || this.bin == null) {
				return;
			}
			var serializable = gobject as Bin.Serializable;
			if (serializable == null) {
				GLib.warning("connection write: not bin Serializable");
				return;
			}
			try {
				if (this.buffer_stream != null) {
					this.buffer_stream.write_with(buffer, serializable, this.bin);
				} else {
					this.bin.write(serializable);
					this.bin.out_stream.flush();
				}
			} catch (GLib.Error e) {
				GLib.warning("connection write error: %s", e.message);
				this.stop();
			}
		}

		public void reply(
			OLLMrpc.Request request, 
			OLLMrpc.Response response, 
			Live.Buffer? buffer = null)
		{
			response.id = request.id;
			this.write(response, buffer);
		}

		/**
		 * Reply with a JSON-RPC error.
		 *
		 * {@link OLLMrpc.Error.code} is ''error_code''. When ''e'' is
		 * passed, message, domain, and
		 * {@link OLLMrpc.Error.gerror_code} are copied from it.
		 * Otherwise {@link OLLMrpc.RpcErrorCode.to_response} is used.
		 *
		 * @param request the request being answered
		 * @param error_code JSON-RPC number ({@link OLLMrpc.RpcErrorCode})
		 * @param e thrown {@link GLib.Error} to send, or ''null'' for a
		 *   protocol error
		 */
		public void reply_error(
			OLLMrpc.Request request,
			int error_code,
			GLib.Error? e = null
		)
		{
			if (e == null) {
				this.reply(
					request,
					OLLMrpc.RpcErrorCode.to_response(error_code)
				);
				return;
			}
			var err = OLLMrpc.RpcErrorCode.to_error(error_code);
			err.message = e.message;
			err.domain = e.domain.to_string();
			err.gerror_code = e.code;
			this.reply(request, new Response() {
				error = err
			});
		}

		protected virtual bool on_input_ready(
			GLib.IOChannel source,
			GLib.IOCondition condition
		)
		{
			if ((condition & GLib.IOCondition.HUP) != 0
			 || (condition & GLib.IOCondition.ERR) != 0) {
				this.stop();
				return false;
			}
			if (!this.channel_open || this.bin == null) {
				return this.running;
			}
			if ((condition & GLib.IOCondition.IN) == 0) {
				return this.running;
			}

			do {
				if (!this.channel_open || this.bin == null) {
					break;
				}
				OLLMrpc.Request? request = null;
				try {
					request = this.bin.parse() as OLLMrpc.Request;
				} catch (GLib.Error e) {
					GLib.error("%s", e.message);
				}
				if (request == null) {
					GLib.warning("connection read: expected Request");
					break;
				}
				GLib.debug(
					"recv id=%d method=%s conn=%p",
					request.id,
					request.method,
					this
				);
				request.connection = this;
				if (!request.dispatch()) {
					this.reply_error(
						request,
						(int) OLLMrpc.RpcErrorCode.METHOD_NOT_FOUND
					);
				}
			} while (
				(source.get_buffer_condition() & GLib.IOCondition.IN) != 0
			);
			return this.running;
		}
	}
}
