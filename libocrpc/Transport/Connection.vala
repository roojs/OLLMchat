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

namespace OLLMrpc.Transport
{
	/** One RPC client channel — NDJSON read loop and reply (Unix socket). */
	public class Connection : GLib.Object
	{
		public GLib.SocketConnection? stream { get; construct; default = null; }

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
				this.channel.set_buffered(true);
				this.channel_open = true;
				this.input_watch_id = this.channel.add_watch(
					GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
					this.on_input_ready
				);
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

		public virtual void write_line(string line)
		{
			if (!this.channel_open || this.channel == null) {
				return;
			}
			size_t written;
			try {
				var payload = line;
				if (!payload.has_suffix("\n")) {
					payload += "\n";
				}
				this.channel.write_chars(payload.to_utf8(), out written);
				this.channel.flush();
			} catch (GLib.Error e) {
				GLib.warning("connection write error: %s", e.message);
				this.stop();
			}
		}

		public void reply(OLLMrpc.Request request, OLLMrpc.Response response)
		{
			response.id = request.id;
			size_t length;
			this.write_line(Json.gobject_to_data(response, out length));
		}

		public void reply_error(OLLMrpc.Request request, int error_code)
		{
			this.reply(request, OLLMrpc.RpcErrorCode.to_response(error_code));
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
			if ((condition & GLib.IOCondition.IN) == 0) {
				return this.running;
			}
			if (!this.channel_open) {
				return this.running;
			}

			string? line = null;
			size_t length = 0;
			GLib.IOStatus status;
			try {
				status = source.read_line(out line, out length, null);
			} catch (GLib.Error e) {
				GLib.warning("connection read error: %s", e.message);
				this.stop();
				return false;
			}
			if (status == GLib.IOStatus.EOF) {
				this.stop();
				return false;
			}
			if (status != GLib.IOStatus.NORMAL || line == null) {
				return this.running;
			}

			OLLMrpc.Request.dispatch_line(line.strip(), this);
			return this.running;
		}
	}
}
