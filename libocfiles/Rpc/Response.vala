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
	/** JSON-RPC 2.0 response (has wire `id`, plus `result` or `error`). */
	public class Response : GLib.Object, Json.Serializable
	{
		public string jsonrpc { get; set; default = "2.0"; }
		public int id { get; construct set; }
		public Error? error { get; set; default = null; }
		public GLib.Object? result { get; set; default = null; }
		public string msg { get; set; default = ""; }
		/**
		 * On the wire with {@link result}: {@link Type.name} for typed deserialize
		 * ({@link OLLMfiles.RpcClient}).
		 */
		public string result_type { get; set; default = ""; }
		/** On the wire: {@link result} is a JSON array of {@link result_type} objects. */
		public bool is_array { get; set; default = false; }

		public Response(int id)
		{
			GLib.Object(id: id);
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
			// placeholder object
			if (property_name == "result") {
				value = Value(typeof(GLib.Object));
				return true;
			}
			return default_deserialize_property(
				property_name, out value, pspec, property_node
			);
		}

		public override Json.Node serialize_property(
			string property_name,
			Value value,
			ParamSpec pspec
		) {
			switch (property_name) {
				case "error":
					if (this.error == null) {
						return null;
					}
					return Json.gobject_serialize(this.error);
				case "result":
					if (this.result == null) {
						return null;
					}
					if (!this.is_array) {
						return Json.gobject_serialize(this.result);
					}
					var list = this.result as Gee.ArrayList<GLib.Object>;
					if (list == null) {
						GLib.error(
							"Response: is_array but result is not Gee.ArrayList"
						);
					}
					var arr = new Json.Array();
					foreach (var item in list) {
						arr.add_element(Json.gobject_serialize(item));
					}
					var node = new Json.Node(Json.NodeType.ARRAY);
					node.set_array(arr);
					return node;
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}
	}
}
