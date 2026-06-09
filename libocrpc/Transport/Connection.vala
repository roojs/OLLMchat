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
		private GLib.DataInputStream? input;
		private GLib.DataOutputStream? output;

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
			this.input = new GLib.DataInputStream(this.stream.get_input_stream());
			this.input.set_newline_type(GLib.DataStreamNewlineType.LF);
			this.output = new GLib.DataOutputStream(this.stream.get_output_stream());
			this.read_loop.begin();
		}

		public virtual void stop()
		{
			if (!this.running) {
				return;
			}
			this.running = false;
			this.channel_open = false;
			this.input = null;
			this.output = null;
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

		public virtual void write(GLib.Object gobject)
		{
			if (this.output == null) {
				return;
			}
			var generator = new Json.Generator();
			generator.set_pretty(false);
			generator.set_root(Json.gobject_serialize(gobject));
			try {
				this.output.put_string(generator.to_data(null) + "\n");
				this.output.flush();
			} catch (GLib.Error e) {
				GLib.warning("connection write error: %s", e.message);
				this.stop();
			}
		}

		public void reply(OLLMrpc.Request request, OLLMrpc.Response response)
		{
			response.id = request.id;
			this.write(response);
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

			line = line.strip();
			this.dispatch_line(line);
			return this.running;
		}

		private async void read_loop()
		{
			while (this.running && this.input != null) {
				try {
					var line = yield this.input.read_line_async(
						GLib.Priority.DEFAULT,
						null
					);
					if (line == null) {
						this.stop();
						return;
					}
					this.dispatch_line(line.strip());
				} catch (GLib.Error e) {
					GLib.warning("connection read error: %s", e.message);
					this.stop();
					return;
				}
			}
		}

		private void dispatch_line(string line)
		{
			if (line == "") {
				return;
			}
			OLLMrpc.Request? request = null;
			try {
				request = Json.gobject_from_data(
					typeof(OLLMrpc.Request),
					line,
					-1
				) as OLLMrpc.Request;
			} catch (GLib.Error e) {
				GLib.warning("parse error: %s", e.message);
				return;
			}
			if (request == null) {
				return;
			}

			request.connection = this;
			request.dispatch();
		}
	}
}
