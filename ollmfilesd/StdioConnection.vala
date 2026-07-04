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

		private int script_awaiting_id = -1;

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

		public override void write(GLib.Object gobject)
		{
			if (gobject is OLLMrpc.Response) {
				var response = gobject as OLLMrpc.Response;
				if (response.id == this.script_awaiting_id) {
					this.script_awaiting_id = -1;
				}
			}
			base.write(gobject);
		}

		private void drain_script_request(int request_id)
		{
			if (request_id == 0) {
				return;
			}
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
			var in_base = new GLib.MemoryInputStream.from_bytes(
				new GLib.Bytes((uint8[]) data.to_utf8())
			);
			var read_bin = new OLLMrpc.Bin.Stream(
				new GLib.DataInputStream(in_base),
				null
			);
			while (true) {
				OLLMrpc.Request? request = null;
				try {
					request = read_bin.parse() as OLLMrpc.Request;
				} catch (GLib.IOError e) {
					break;
				} catch (GLib.Error e) {
					GLib.warning("parse error: %s", e.message);
					break;
				}
				if (request == null) {
					break;
				}
				this.script_awaiting_id = request.id;
				request.connection = this;
				if (!request.dispatch(null)) {
					this.script_awaiting_id = -1;
					continue;
				}
				this.drain_script_request(request.id);
			}
		}
	}
}
