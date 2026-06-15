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
	/** Stdin/stdout {@link OLLMrpc.Transport.Listen} ({@code --interactive}). */
	public class Stdio : OLLMrpc.Transport.Listen
	{
		public OllmfilesdApplication app { get; construct; }
		public string script_path { get; construct; default = ""; }

		private StdioConnection? connection;

		public Stdio(OllmfilesdApplication app, string script_path = "")
		{
			Object(app: app, script_path: script_path);
		}

		public override bool start()
		{
			this.connection = new StdioConnection(
				this.app,
				this.script_path
			);
			this.connection.start();
			return true;
		}

		public override void broadcast(GLib.Object gobject)
		{
			if (this.connection != null) {
				this.connection.write(gobject);
			}
		}

		public override void stop()
		{
			if (this.connection != null) {
				this.connection.stop();
				this.connection = null;
			}
		}
	}
}
