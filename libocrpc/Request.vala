/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMrpc
{
	/**
	 * Bin RPC request (one root object per call).
	 *
	 * On the client, build a {@link Request}, set {@link method}, assign a
	 * typed {@link CallParam} subclass to {@link param}, then pass to
	 * {@link Client.call}. On the server, set {@link connection}, then
	 * {@link dispatch} routes {{{Object.method}}} to the handler's
	 * {{{call_*}}} signal; handlers reply via {@link reply}.
	 *
	 * @see CallParam
	 * @see Client
	 * @see Transport.Connection
	 */
	public class Request : GLib.Object, Bin.Serializable
	{
		/** Wire object prefix → handler singleton (server dispatch). */
		public static Gee.HashMap<string, GLib.Object> handlers;

		/**
		 * Wire object prefix → {@link GLib.Type} of the handler's param bag
		 * (subclass of {@link CallParam}).
		 */
		public static Gee.HashMap<GLib.Type, GLib.Type> param_types;

		public int id { get; set; }
		public string method { get; set; default = ""; }

		/**
		 * Typed request arguments (client → daemon).
		 *
		 * Client: assign the registered param type for the target object.
		 * Server: populated by {@link Bin.Serializable} decode on the wire.
		 */
		public CallParam param { get; set; default = new CallParam(); }

		/** Set by the server before {@link dispatch}. */
		public Transport.Connection connection { get; set; }

		public static void rpc_register()
		{
			Bin.register("Request", typeof(Request));
		}

		/**
		 * Register a server dispatch handler and its params {@link GLib.Type}.
		 *
		 * @param name wire object prefix (e.g. {{{"Folder"}}})
		 * @param target live singleton with {{{call_*}}} signals
		 * @param param_type GObject type for wire params (extends {@link CallParam})
		 */
		public static void register(
			string name,
			GLib.Object target,
			GLib.Type param_type
		) {
			if (handlers == null) {
				handlers = new Gee.HashMap<string, GLib.Object>();
				param_types = new Gee.HashMap<GLib.Type, GLib.Type>();
			}
			handlers.set(name, target);
			param_types.set(target.get_type(), param_type);
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public override void bin_write_prop (
			Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "connection":
					return;
				default:
					this.bin_default_write_prop (ctx, prop);
					return;
			}
		}

		public override void bin_read_prop (
			Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			switch (prop.name) {
				case "connection":
					return;
				default:
					this.bin_default_read_prop (ctx, prop, type_byte);
					return;
			}
		}

		/**
		 * Route this request to the matching {{{call_*}}} signal.
		 *
		 * @return true when a handler signal was emitted
		 */
		public bool dispatch()
		{
			if (this.connection == null) {
				GLib.critical("RPC dispatch: connection not set");
				return false;
			}
			if (this.method.length == 0) {
				GLib.critical("RPC dispatch: method not set");
				return false;
			}

			var dot = this.method.index_of_char('.');
			if (dot < 1 || dot == this.method.length - 1) {
				GLib.critical(
					"RPC dispatch: method must be Object.method, got '%s'",
					this.method
				);
				return false;
			}

			var object_name = this.method[0:dot];
			var method_name = this.method.substring(dot + 1);

			if (!handlers.has_key(object_name)) {
				GLib.critical(
					"RPC dispatch: no handler for '%s' (%s)",
					object_name,
					this.method
				);
				return false;
			}
			var handler = handlers.get(object_name);
			var signal_name = "call_" + method_name.replace(".", "_");
			if (GLib.Signal.lookup(signal_name, handler.get_type()) == 0) {
				GLib.critical(
					"RPC dispatch: no signal call_%s on %s for %s",
					method_name.replace(".", "_"),
					object_name,
					this.method
				);
				return false;
			}
			GLib.debug("emit %s id=%d", signal_name, this.id);
			GLib.Signal.emit_by_name(handler, signal_name, this);
			GLib.debug("emit returned id=%d", this.id);
			return true;
		}

		/**
		 * Relay a {@link Response} to {@link connection} (sets wire {{{id}}}).
		 */
		public void reply(Response response)
		{
			this.connection.reply(this, response);
		}
	}
}
