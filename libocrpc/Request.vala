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
	 * JSON-RPC 2.0 request line (one NDJSON object per call).
	 *
	 * On the client, build a {@link Request}, set {@link method}, assign a
	 * typed {@link CallParam} subclass to {@link param}, then pass to
	 * {@link Client.call}. On the server, set {@link connection}, then
	 * {@link dispatch} routes {{{Object.method}}} to the handler's
		 * {{{call_*}}} signal; handlers reply via {@link reply}.
	 *
	 * == Wire {{{params}}} (request arguments) ==
	 *
	 * JSON-RPC puts arguments in a flat object. Scripts and the API overview
	 * use wire key {{{"params"}}}; json-glib may emit {{{"param"}}} from the
	 * Vala property name {@link param}. Field names match GObject properties
	 * on the handler's registered param type (see {@link register}).
	 *
	 * Example:
	 *
	 * {{{
	 * {"method":"Folder.fetch_files","params":{"path":"/proj","offset":0,"limit":50}}
	 * }}}
	 *
	 * == Client serialize ==
	 *
	 *  * Assign the daemon param type for the target object (e.g.
	 *    {{{OLLMfilesd.FolderParams}}} for {{{Folder.*}}}) to {@link param}.
	 *  * {@link Client.call} serializes with {{{Json.gobject_serialize}}};
	 *    nested fields need no custom {@link Json.Serializable} overrides on
	 *    the param class.
	 *
	 * == Server deserialize ==
	 *
	 *  * {@link Json.gobject_from_data} on {@link Request} alone does ''not''
	 *    fully populate typed params when the wire key is {{{"params"}}} — see
	 *    {@link deserialize_property}.
	 *  * After parsing the line, pass the raw params object node to
	 *    {@link dispatch}; it runs
	 *    {{{Json.gobject_deserialize(param_types.get(handler), node)}}}.
	 *  * Server transports must pass that node (from {{{"params"}}} or
	 *    {{{"param"}}}); do not call {@link dispatch} with no node when the
	 *    handler expects typed fields.
	 *
	 * @see CallParam
	 * @see Client
	 * @see Transport.Connection
	 */
	public class Request : GLib.Object, Json.Serializable, Bin.Serializable
	{
		/** Wire object prefix → handler singleton (server dispatch). */
		public static Gee.HashMap<string, GLib.Object> handlers;

		/**
		 * Wire object prefix → {@link GLib.Type} of the handler's param bag
		 * (subclass of {@link CallParam}).
		 */
		public static Gee.HashMap<GLib.Type, GLib.Type> param_types;

		public string jsonrpc { get; set; default = "2.0"; }
		public int id { get; set; }
		public string method { get; set; default = ""; }

		/**
		 * Typed request arguments (client → daemon).
		 *
		 * Client: assign the registered param type for the target object.
		 * Server: filled by {@link dispatch} when the call site passes the
		 * wire params node; until then may be a placeholder {@link CallParam}.
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
					// Placeholder only — typed fill in {@link dispatch}.
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
		 * When @params_node is set, replaces {@link param} with
		 * {{{Json.gobject_deserialize}}} using the type registered in
		 * {@link register} for the handler object. Server call sites should
		 * always pass the wire params object node when the method reads typed
		 * fields off {@link param}.
		 *
		 * @param params_node raw JSON object for wire {{{"params"}}} or
		 *   {{{"param"}}}, or null to use {@link param} as already parsed
		 * @return true when a handler signal was emitted
		 */
		public bool dispatch(Json.Node? params_node = null)
		{
			if (this.connection == null) {
				GLib.critical("RPC dispatch: connection not set");
				return false;
			}
			if (this.jsonrpc != "2.0"
				|| this.method.length == 0) {
				GLib.critical("RPC dispatch: invalid JSON-RPC request");
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
			if (params_node != null) {
				this.param = Json.gobject_deserialize(
					param_types.get(handler.get_type()),
					params_node
				) as CallParam;
			}
			if (GLib.Signal.lookup(
					"call_" + method_name.replace(".", "_"),
					handler.get_type()
				) == 0) {
				GLib.critical(
					"RPC dispatch: no signal call_%s on %s for %s",
					method_name.replace(".", "_"),
					object_name,
					this.method
				);
				return false;
			}
			GLib.Signal.emit_by_name(
				handler,
				"call_" + method_name.replace(".", "_"),
				this
			);
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
