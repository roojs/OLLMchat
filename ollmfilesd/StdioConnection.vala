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
	 * Stdin/stdout {@link OLLMrpc.Transport.Connection}
	 * ({@code --interactive}, optional {@code --rpc-script}).
	 */
	public class StdioConnection : OLLMrpc.Transport.Connection
	{
		public OllmfilesdApplication app { get; construct; }
		public string script_path { get; construct; default = ""; }

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

			this.write(new OLLMrpc.Notification() {
				method = "Daemon.ready",
				object_type = "Daemon",
			});

			if (this.script_path != "") {
				try {
					this.run_script(this.script_path);
				} catch (GLib.Error e) {
					GLib.error("%s", e.message);
				}
				this.app.quit();
				return;
			}

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
			base.stop();
			this.app.quit();
		}

		public override void write(GLib.Object gobject)
		{
			var generator = new Json.Generator();
			generator.set_pretty(false);
			generator.set_root(Json.gobject_serialize(gobject));
			GLib.stdout.printf("%s\n", generator.to_data(null));
			GLib.stdout.flush();
		}

		private void run_script(string path) throws GLib.Error
		{
			string data;
			GLib.FileUtils.get_contents(path, out data);
			foreach (var raw in data.split("\n")) {
				var line = raw.strip();
				if (line == "") {
					continue;
				}
				if (line.has_prefix("#")) {
					continue;
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
					continue;
				}

				var parser = new Json.Parser();
				parser.load_from_data(line, -1);

				request.connection = this;
				request.dispatch(
					parser.get_root().get_object().get_member("params")
				);
			}
		}
	}
}
