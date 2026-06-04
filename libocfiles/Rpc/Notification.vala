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

namespace OLLMfiles.Rpc
{
	/** JSON-RPC 2.0 notification (no `id`). Wire key `params`, Vala {@link param}. */
	public class Notification : GLib.Object, Json.Serializable
	{
		public string jsonrpc { get; set; default = "2.0"; }
		public string method { get; set; default = ""; }
		public CallParam param { get; set; default = new CallParam(); }

		public static void rpc_register()
		{
			register(typeof(Notification));
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

		public override Json.Node serialize_property(
			string property_name,
			Value value,
			ParamSpec pspec
		) {
			switch (property_name) {
				case "param":
					return Json.gobject_serialize(this.param);
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(
			string property_name,
			out Value value,
			ParamSpec pspec,
			Json.Node property_node
		) {
			switch (property_name) {
				case "params":
					this.param = Json.gobject_deserialize(
						typeof(CallParam), property_node
					) as CallParam;
					value = Value(typeof(CallParam));
					value.set_object(this.param);
					return true;
				default:
					return default_deserialize_property(
						property_name, out value, pspec, property_node
					);
			}
		}
	}
}
