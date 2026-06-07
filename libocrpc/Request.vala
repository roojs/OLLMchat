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

namespace OLLMrpc
{
	/**
	 * JSON-RPC 2.0 request line. Deserialize with Json.gobject_from_data.
	 *
	 * On the client, pass to {@link RpcClient.call}. On the server,
	 * {@link dispatch} routes {@code Object.method} to a registered handler's
	 * {@code rpc_*} signal. Set {@link session} before {@link dispatch}; handlers
	 * reply via {@link reply}.
	 */
	public class Request : GLib.Object, Json.Serializable
	{
		/** Wire object prefix → handler singleton (server dispatch). */
		public static Gee.HashMap<string, GLib.Object> handlers;

		/** Wire object prefix → {@code params} GObject type. */
		public static Gee.HashMap<GLib.Type, GLib.Type> param_types;

		public string jsonrpc { get; set; default = "2.0"; }
		public int id { get; set; }
		public string method { get; set; default = ""; }
		public CallParam param { get; set; default = new CallParam(); }

		/** Set by the server before {@link dispatch}. */
		public Session session { get; set; }

		/**
		 * Register a server dispatch handler and its {@code params} type.
		 *
		 * @param name wire object prefix (e.g. {@code "Daemon"})
		 * @param target live singleton with {@code rpc_*} signals
		 * @param param_type GObject type for {@code params} objects
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

		public override bool deserialize_property(
			string property_name,
			out Value value,
			ParamSpec pspec,
			Json.Node property_node
		) {
			switch (property_name) {
				case "params":
					// Server typed deserialize: {@link dispatch}.
					this.param = new CallParam();
					value = Value(typeof(CallParam));
					value.set_object(this.param);
					return true;
				default:
					return default_deserialize_property(
						property_name, out value, pspec, property_node
					);
			}
		}

		/** Route this request to the matching {@code rpc_*} signal. */
		public void dispatch(Json.Node? params_node = null)
		{
			if (this.session == null) {
				GLib.critical("RPC dispatch: session not set");
				return;
			}
			if (this.jsonrpc != "2.0"
				|| this.method.length == 0) {
				GLib.critical("RPC dispatch: invalid JSON-RPC request");
				return;
			}

			var dot = this.method.index_of_char('.');
			if (dot < 1 || dot == this.method.length - 1) {
				GLib.critical(
					"RPC dispatch: method must be Object.method, got '%s'",
					this.method
				);
				return;
			}

			var object_name = this.method[0:dot];
			var method_name = this.method.substring(dot + 1);

			if (!handlers.has_key(object_name)) {
				GLib.critical(
					"RPC dispatch: no handler for '%s' (%s)",
					object_name,
					this.method
				);
				return;
			}
			var handler = handlers.get(object_name);
			if (params_node != null) {
				this.param = Json.gobject_deserialize(
					param_types.get(handler.get_type()),
					params_node
				) as CallParam;
			}
			if (GLib.Signal.lookup(
					"rpc_" + method_name.replace(".", "_"),
					handler.get_type()
				) == 0) {
				GLib.critical(
					"RPC dispatch: no signal rpc_%s on %s for %s",
					method_name.replace(".", "_"),
					object_name,
					this.method
				);
				return;
			}
			GLib.Signal.emit_by_name(
				handler,
				"rpc_" + method_name.replace(".", "_"),
				this
			);
		}

		/** Relay a {@link Response} to {@link session} (sets wire {@code id}). */
		public void reply(Response response)
		{
			this.session.reply(this, response);
		}
	}
}
