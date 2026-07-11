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

		protected GLib.IOChannel? channel;
		protected bool channel_open = false;
		protected uint input_watch_id = 0;
		protected bool running = false;

		public Connection(GLib.SocketConnection? stream = null)
		{
			GLib.Object(stream: stream);
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
				this.bin = new Bin.Stream(in_stream, out_stream);
			} catch (GLib.Error e) {
				GLib.warning("connection setup failed: %s", e.message);
				this.stop();
			}
		}

		public virtual void stop()
		{
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

		public virtual async void write(GLib.Object gobject)
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
				this.bin.write(serializable);
				this.bin.out_stream.flush();
			} catch (GLib.Error e) {
				GLib.warning("connection write error: %s", e.message);
				this.stop();
			}
		}

		public async void reply(OLLMrpc.Request request, OLLMrpc.Response response)
		{
			response.id = request.id;
			GLib.debug(
				"reply id=%d method=%s conn=%p",
				request.id,
				request.method,
				this
			);
			yield this.write(response);
		}

		public async void reply_error(
			OLLMrpc.Request request,
			int error_code
		)
		{
			yield this.reply(
				request,
				OLLMrpc.RpcErrorCode.to_response(error_code)
			);
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
				request.dispatch();
			} while (
				(source.get_buffer_condition() & GLib.IOCondition.IN) != 0
			);
			return this.running;
		}
	}
}
