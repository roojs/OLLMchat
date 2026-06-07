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
	/**
	 * One connected client: NDJSON read loop and RPC dispatch.
	 */
	public class Connection : GLib.Object, Session
	{
		public GLib.SocketConnection connection { get; construct; }

		private GLib.IOChannel channel;
		private bool channel_open = false;
		private uint input_watch_id = 0;
		private bool running = false;

		public Connection(GLib.SocketConnection connection)
		{
			GLib.Object(connection: connection);
		}

		public void start()
		{
			if (this.running) {
				return;
			}
			this.running = true;
			try {
				var fd = this.connection.get_socket().get_fd();
				this.channel = new GLib.IOChannel.unix_new(fd);
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
				var payload = line;
				if (!payload.has_suffix("\n")) {
					payload += "\n";
				}
				this.channel.write_chars(payload.to_utf8(), out written);
				this.channel.flush();
			} catch (GLib.Error e) {
				GLib.warning("session write error: %s", e.message);
				this.stop();
			}
		}

		public void reply(Request request, Response response)
		{
			response.id = request.id;
			size_t length;
			this.write_line(Json.gobject_to_data(response, out length));
		}

		public void reply_error(Request request, RpcErrorCode error_code)
		{
			this.reply(request, RpcErrorCode.to_response(error_code));
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

			var data = line.strip();
			var parser = new Json.Parser();
			try {
				parser.load_from_data(data, -1);
			} catch (GLib.Error e) {
				GLib.warning("parse error: %s", e.message);
				return this.running;
			}
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				GLib.warning("parse error: not a JSON object");
				return this.running;
			}
			var obj = root.get_object();

			Request? request = null;
			try {
				request = Json.gobject_deserialize(
					typeof(Request), root
				) as Request;
			} catch (GLib.Error e) {
				GLib.warning("parse error: %s", e.message);
				return this.running;
			}
			if (request == null) {
				return this.running;
			}

			request.session = this;
			request.dispatch(obj.get_member("params"));
			return this.running;
		}
	}
}
