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
	public class Daemon : OLLMrpc.Daemon, OLLMrpc.Bin.Serializable
	{
		public static new void rpc_register()
		{
			OLLMrpc.Bin.register("Daemon", typeof(Daemon));
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(Daemon),
				"hello", "iss",
				"shutdown", ""
			);
		}

		public OllmfilesdApplication app { get; construct; }

		public Daemon(OllmfilesdApplication app)
		{
			GLib.Object(app: app);
			this.server = "ollmfilesd";
			this.ready = true;
		}

		public void hello(OLLMrpc.Request request, int protocol, string client, string? version = null)
		{
			if (protocol > 0) {
				this.protocol = protocol;
			}
			var theirs = (version == null || version == "") ? "0.0.0" : version;
			GLib.debug("hello %s %d %s", client, protocol, theirs);
			this.version = OLLMchat.VERSION;
			if (this.compare(theirs, 2) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_PARAMS("The server is " + this.version +
						". This client is " + theirs + ".")
				});
				return;
			}
			var notice = "ok";
			if (this.compare(theirs, 2) > 0) {
				notice = "This client is " + theirs + ". The server is " + this.version + ".";
				GLib.warning("%s", notice);
			}
			request.reply(new OLLMrpc.Response() {
				msg = notice,
				retval = OLLMrpc.val("o", this)
			});
		}

		public void shutdown(OLLMrpc.Request request)
		{
			this.ready = false;
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
			this.app.quit();
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
	}
}
