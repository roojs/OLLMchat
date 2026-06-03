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

namespace OLLMfilesd.Rpc
{
	/** Wire {@code Daemon.*} — {@code hello} and {@code shutdown}. */
	public class Daemon : GLib.Object, Json.Serializable
	{
		public int protocol { get; set; default = 1; }
		public string server { get; set; default = "ollmfilesd"; }
		public bool ready { get; set; default = true; }

		public signal void rpc_hello(Request request);
		public signal void rpc_shutdown(Request request);

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
				if (request.param.protocol > 0) {
					this.protocol = request.param.protocol;
				}
				request.session.reply(request, new Rpc.Response(request.id) {
					result = this
				});
			});
			this.rpc_shutdown.connect((request) => {
				this.ready = false;
				request.session.reply(request, new Rpc.Response(request.id) {
					msg = "ok"
				});
				request.session.listen.stop();
			});
		}
	}
}
