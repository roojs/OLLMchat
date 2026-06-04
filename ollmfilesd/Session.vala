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

namespace OLLMfilesd
{
	/**
	 * One connected client: NDJSON read loop and RPC dispatch.
	 */
	public class Session : GLib.Object
	{
		public Listen listen { get; construct; }
		public GLib.SocketConnection connection { get; construct; }

		private GLib.IOChannel channel;
		private bool channel_open = false;
		private uint input_watch_id = 0;
		private bool running = false;

		public Session(Listen listen, GLib.SocketConnection connection)
		{
			GLib.Object(listen: listen, connection: connection);
		}

		public void start()
		{
			if (this.running) {
				return;
			}
			this.running = true;
			try {
				var fd = this.connection.get_socket().get_fd();
				this.channel = GLib.IOChannel.unix_new(fd);
				this.channel.set_encoding(null);
				this.channel.set_buffered(true);
				this.channel_open = true;
				this.input_watch_id = this.channel.add_watch(
					GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
					this.on_input_ready
				);
			} catch (GLib.Error e) {
				GLib.warning("session setup failed: %s", e.message);
				this.stop();
			}
		}

		public void stop()
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
			try {
				this.connection.close();
			} catch (GLib.Error e) {
			}
		}

		public void write_line(string line)
		{
			if (!this.channel_open) {
				return;
			}
			size_t written;
			try {
				this.channel.write_chars(line + "\n", out written);
				this.channel.flush();
			} catch (GLib.Error e) {
				GLib.warning("session write error: %s", e.message);
				this.stop();
			}
		}

		public void reply(Rpc.Request request, OLLMfiles.Rpc.Response response)
		{
			response.id = request.id;
			size_t length;
			this.write_line(Json.gobject_to_data(response, out length));
		}

		public void reply_error(
			Rpc.Request request,
			OLLMfiles.Rpc.RpcErrorCode error_code
		)
		{
			this.reply(
				request,
				OLLMfiles.Rpc.RpcErrorCode.to_response(request, error_code)
			);
		}

		private bool on_input_ready(GLib.IOChannel source, GLib.IOCondition condition)
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
				status = this.channel.read_line(out line, out length, null);
			} catch (GLib.Error e) {
				GLib.warning("session read error: %s", e.message);
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

			Rpc.Request? request = null;
			try {
				request = Json.gobject_from_data(
					typeof(Rpc.Request), line.strip()
				) as Rpc.Request;
			} catch (GLib.Error e) {
				GLib.warning("parse error: %s", e.message);
				return this.running;
			}
			if (request == null) {
				return this.running;
			}

			request.session = this;
			request.dispatch();
			return this.running;
		}
	}
}
