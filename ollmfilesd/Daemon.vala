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
	public class Daemon : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Daemon", typeof(Daemon));
			DaemonParams.rpc_register();
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
				var result = new Gee.ArrayList<GLib.Object>();
				result.add(this);
				request.reply.begin(new OLLMrpc.Response() {
					result = result
				}, null);
			});
			this.call_shutdown.connect((request) => {
				this.ready = false;
				request.reply.begin(new OLLMrpc.Response() {
					msg = "ok"
				}, null);
				this.app.quit();
			});
		}
	}
}
