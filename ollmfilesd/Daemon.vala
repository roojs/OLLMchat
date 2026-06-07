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
	/** Server {@code Daemon.*} — {@code hello} and {@code shutdown}. */
	public class Daemon : GLib.Object, Json.Serializable
	{
		public OllmfilesdApplication app { get; construct; }

		public Daemon(OllmfilesdApplication app)
		{
			GLib.Object(app: app);
		}

		public int protocol { get; set; default = 1; }
		public string server { get; set; default = "ollmfilesd"; }
		public bool ready { get; set; default = true; }

		public signal void rpc_hello(OLLMrpc.Request request);
		public signal void rpc_shutdown(OLLMrpc.Request request);

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		construct
		{
			this.rpc_hello.connect((request) => {
				var p = (DaemonParams) request.param;
				if (p.protocol > 0) {
					this.protocol = p.protocol;
				}
				request.reply(new OLLMrpc.Response() {
					result = this,
					result_type = "Daemon"
				});
			});
			this.rpc_shutdown.connect((request) => {
				this.ready = false;
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				this.app.cleanup();
				this.app.release();
				this.app.quit();
			});
		}
	}
}
