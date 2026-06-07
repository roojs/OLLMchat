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
	/** Stdin/stdout {@link OLLMrpc.Transport.Connection} ({@code --interactive}). */
	public class StdioConnection : OLLMrpc.Transport.Connection
	{
		public OllmfilesdApplication app { get; construct; }

		public StdioConnection(OllmfilesdApplication app)
		{
			Object(app: app);
		}

		public override void start()
		{
			if (this.running) {
				return;
			}
			this.running = true;
			GLib.stderr.printf(
				"ollmfilesd interactive (stdin/stdout JSON-RPC)\n"
					+ "  one JSON-RPC request per line on stdin\n"
					+ "  help — example request\n"
					+ "  quit — exit\n"
			);
			this.channel = new GLib.IOChannel.unix_new(Posix.STDIN_FILENO);
			this.channel.set_encoding(null);
			this.channel.set_buffered(true);
			this.channel_open = true;
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
			this.running = false;
			this.channel_open = false;
			if (this.input_watch_id != 0) {
				GLib.Source.remove(this.input_watch_id);
				this.input_watch_id = 0;
			}
			this.channel = null;
		}

		public override void write_line(string line)
		{
			var payload = line;
			if (!payload.has_suffix("\n")) {
				payload += "\n";
			}
			GLib.stdout.printf("%s", payload);
			GLib.stdout.flush();
		}

		protected override bool on_input_ready(
			GLib.IOChannel source,
			GLib.IOCondition condition
		)
		{
			if ((condition & GLib.IOCondition.HUP) != 0) {
				this.app.quit();
				return false;
			}

			string? line = null;
			size_t length = 0;
			GLib.IOStatus status;
			try {
				status = source.read_line(out line, out length, null);
			} catch (GLib.Error e) {
				GLib.stderr.printf("stdin read error: %s\n", e.message);
				return this.running;
			}
			if (status == GLib.IOStatus.EOF) {
				this.app.quit();
				return false;
			}
			if (status != GLib.IOStatus.NORMAL || line == null) {
				return this.running;
			}

			line = line.strip();
			if (line == "") {
				return this.running;
			}
			if (line == "help") {
				GLib.stderr.printf(
					"send one JSON-RPC line, e.g.\n"
						+ "  {\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"Daemon.hello\","
						+ "\"params\":{\"protocol\":1,\"client\":\"stdio\"}}\n"
				);
				return this.running;
			}
			if (line == "quit" || line == "exit") {
				this.app.quit();
				return false;
			}

			OLLMrpc.Request.dispatch_line(line, this);
			return this.running;
		}
	}
}
