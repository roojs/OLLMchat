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
	public class Daemon : GLib.Object, Json.Serializable, OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.Stream.register("Daemon", typeof(Daemon));
		}

		public OllmfilesdApplication app { get; construct; }

		public Daemon(OllmfilesdApplication app)
		{
			GLib.Object(app: app);
		}

		public int protocol { get; set; default = 1; }
		public string server { get; set; default = "ollmfilesd"; }
		public bool ready { get; set; default = true; }

		public signal void call_hello(OLLMrpc.Request request);
		public signal void call_shutdown(OLLMrpc.Request request);

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

		public override Json.Node serialize_property(
			string property_name,
			Value value,
			ParamSpec pspec
		) {
			if (property_name == "app") {
				return null;
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			if (prop.name == "app") {
				return;
			}
			bin_default_write_prop(ctx, prop);
		}

		public override void bin_read_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			if (prop.name == "app") {
				return;
			}
			bin_default_read_prop(ctx, prop, type_byte);
		}

		construct
		{
			this.call_hello.connect((request) => {
				var p = (DaemonParams) request.param;
				if (p.protocol > 0) {
					this.protocol = p.protocol;
				}
				request.reply(new OLLMrpc.Response() {
					result = this,
					result_type = "Daemon"
				});
			});
			this.call_shutdown.connect((request) => {
				this.ready = false;
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				this.app.quit();
			});
		}
	}
}
