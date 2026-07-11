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
	 * Stdin/stdout {@link OLLMrpc.Transport.Connection} for debugging and tests.
	 *
	 * NDJSON on stdin/stdout; {@link OLLMrpc.Bin.Json} bridges each line to
	 * the internal bin codec.
	 */
	public class StdioConnection : OLLMrpc.Transport.Connection
	{
		public OllmfilesdApplication app { get; construct; }
		public string script_path { get; construct; default = ""; }

		private int script_awaiting_id = -1;
		private OLLMrpc.Bin.Json json = new OLLMrpc.Bin.Json ();

		public StdioConnection(
			OllmfilesdApplication app,
			string script_path = ""
		) {
			Object(app: app, script_path: script_path);
		}

		public override void start()
		{
			if (this.running) {
				return;
			}
			this.running = true;

			this.channel = new GLib.IOChannel.unix_new(Posix.STDIN_FILENO);
			this.channel.set_encoding(null);
			this.channel.set_buffered(true);
			this.channel_open = true;
			var in_stream = new GLib.DataInputStream(
				new GLib.UnixInputStream(Posix.STDIN_FILENO, false)
			);
			var out_stream = new GLib.DataOutputStream(
				new GLib.UnixOutputStream(Posix.STDOUT_FILENO, false)
			);
			this.bin = new OLLMrpc.Bin.Stream(in_stream, out_stream);

			this.write.begin(new OLLMrpc.Notification() {
				method = "Daemon.ready",
				object_type = "Daemon",
			}, null);

			if (this.script_path != "") {
				try {
					this.run_script(this.script_path);
				} catch (GLib.Error e) {
					GLib.error("%s", e.message);
				}
				return;
			}

			this.input_watch_id = this.channel.add_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP,
				this.on_input_ready
			);
		}

		public override void stop()
		{
			if (!this.running) {
				return;
			}
			base.stop();
			this.app.quit();
		}

		public override async void write(GLib.Object gobject)
		{
			if (gobject is OLLMrpc.Response) {
				var response = gobject as OLLMrpc.Response;
				if (response.id == this.script_awaiting_id) {
					this.script_awaiting_id = -1;
				}
			}
			var serializable = gobject as OLLMrpc.Bin.Serializable;
			if (serializable == null) {
				GLib.warning("stdio write: not bin Serializable");
				return;
			}
			try {
				var node = yield this.json.from_gobject(serializable);
				var gen = new Json.Generator();
				gen.set_pretty(false);
				gen.set_root(node);
				var line = gen.to_data(null);
				this.bin.out_stream.put_string(line);
				this.bin.out_stream.put_byte((uint8) '\n');
				this.bin.out_stream.flush();
			} catch (GLib.Error e) {
				GLib.error("stdio write: %s", e.message);
			}
		}

		protected override bool on_input_ready(
			GLib.IOChannel source,
			GLib.IOCondition condition
		) {
			if ((condition & GLib.IOCondition.HUP) != 0
				|| (condition & GLib.IOCondition.ERR) != 0) {
				this.stop();
				return false;
			}
			if ((condition & GLib.IOCondition.IN) == 0) {
				return this.running;
			}

			string? line = this.bin.in_stream.read_line(null);
			if (line == null) {
				this.stop();
				return false;
			}
			line = line.strip();
			if (line == "" || line.has_prefix("#")) {
				return this.running;
			}

			try {
				var request = this.request_from_json_line(line);
				request.connection = this;
				request.dispatch();
			} catch (GLib.Error e) {
				GLib.error("%s", e.message);
			}
			return this.running;
		}

		private void drain_script_request(int request_id)
		{
			while (this.script_awaiting_id == request_id) {
				if (!GLib.MainContext.default().iteration(true)) {
					break;
				}
			}
		}

		private void run_script(string path) throws GLib.Error
		{
			var data = "";
			GLib.FileUtils.get_contents(path, out data);

			foreach (var raw_line in data.split("\n")) {
				var line = raw_line.strip();
				if (line == "" || line.has_prefix("#")) {
					continue;
				}
				var request = this.request_from_json_line(line);
				this.script_awaiting_id = request.id;
				request.connection = this;
				if (!request.dispatch()) {
					this.script_awaiting_id = -1;
					continue;
				}
				this.drain_script_request(request.id);
			}
		}

		private OLLMrpc.Request request_from_json_line (
			string line
		) throws GLib.Error
		{
			var parser = new Json.Parser();
			parser.load_from_data(line);
			var root = parser.get_root().get_object();

			var mem = new GLib.MemoryOutputStream.resizable();
			var out_stream = new GLib.DataOutputStream(mem);
			var encode_ctx = new OLLMrpc.Bin.Stream(null, out_stream);
			this.json.json_to_bin(root, encode_ctx);
			out_stream.close();

			var in_base = new GLib.MemoryInputStream.from_bytes(
				mem.steal_as_bytes()
			);
			var read_ctx = new OLLMrpc.Bin.Stream(
				new GLib.DataInputStream(in_base),
				null
			);
			return (OLLMrpc.Request) read_ctx.parse();
		}
	}
}
