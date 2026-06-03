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
	/** JSON-RPC 2.0 request line. Deserialize with Json.gobject_from_data. */
	public class Request : GLib.Object, Json.Serializable
	{
		public string jsonrpc { get; set; default = "2.0"; }
		public int id { get; set; }
		public string method { get; set; default = ""; }
		public CallParam param { get; set; default = new CallParam (); }
		public OLLMfilesd.Session session { get; set; }

		private bool has_id = false;

		public unowned ParamSpec? find_property (string name)
		{
			return this.get_class ().find_property (name);
		}

		public new void Json.Serializable.set_property (ParamSpec pspec, Value value)
		{
			if (pspec.get_name () == "id") {
				this.has_id = true;
			}
			base.set_property (pspec.get_name (), value);
		}

		public new Value Json.Serializable.get_property (ParamSpec pspec)
		{
			Value val = Value (pspec.value_type);
			base.get_property (pspec.get_name (), ref val);
			return val;
		}

		public override Json.Node serialize_property (
			string property_name,
			Value value,
			ParamSpec pspec
		) {
			switch (property_name) {
				case "session":
					return null;
				default:
					return default_serialize_property (property_name, value, pspec);
			}
		}

		public override bool deserialize_property (
			string property_name,
			out Value value,
			ParamSpec pspec,
			Json.Node property_node
		) {
			switch (property_name) {
				case "params":
					if (property_node.get_node_type () == Json.NodeType.OBJECT) {
						this.param = Json.gobject_deserialize (
							typeof (CallParam), property_node
						) as CallParam;
						value = Value (typeof (CallParam));
						value.set_object (this.param);
						return true;
					}
					if (property_node.get_node_type () != Json.NodeType.ARRAY) {
						this.param = new CallParam ();
						value = Value (typeof (CallParam));
						value.set_object (this.param);
						return true;
					}
					var array = property_node.get_array ();
					var items = new string[array.get_length ()];
					for (uint i = 0; i < array.get_length (); i++) {
						var el = array.get_element (i);
						if (el.get_node_type () != Json.NodeType.VALUE
						 || el.get_value_type () != typeof (string)) {
							value = Value (typeof (CallParam));
							return false;
						}
						items[i] = el.get_string ();
					}
					this.param = new CallParam () { args = items };
					value = Value (typeof (CallParam));
					value.set_object (this.param);
					return true;
				default:
					return default_deserialize_property (
						property_name, out value, pspec, property_node
					);
			}
		}

		public void dispatch ()
		{
			try {
				this.invoke ();
			} catch (RpcErrorCode e) {
				this.session.reply_error (this, e);
			} catch (GLib.Error e) {
				GLib.warning ("dispatch error: %s", e.message);
			}
		}

		private void invoke () throws RpcErrorCode
		{
			if (!this.has_id
				|| this.jsonrpc != "2.0"
				|| this.method.length == 0) {
				throw new RpcErrorCode.INVALID_REQUEST ("Invalid JSON-RPC request");
			}

			var dot = this.method.index_of_char ('.');
			if (dot < 1 || dot == this.method.length - 1) {
				throw new RpcErrorCode.INVALID_REQUEST (
					"Method must be kind.verb, got '" + this.method + "'"
				);
			}

			var kind = this.method[0:dot];
			var verb = this.method.substring (dot + 1);

			if (kind == "event") {
				throw new RpcErrorCode.INVALID_REQUEST (
					"Clients must not call event.* methods"
				);
			}

			var registry = this.session.listen;
			var pspec = registry.get_class ().find_property (kind);
			if (pspec == null) {
				throw new RpcErrorCode.METHOD_NOT_FOUND (
					"No RPC object for kind '" + kind + "'"
				);
			}

			var val = GLib.Value (pspec.value_type);
			registry.get_property (kind, ref val);
			var target = val.get_object ();
			if (target == null) {
				throw new RpcErrorCode.NOT_IMPLEMENTED (
					kind + " is not wired yet"
				);
			}

			var signal_name = "rpc_" + verb.replace (".", "_");
			var signal_id = GLib.Signal.lookup (signal_name, target.get_type ());
			if (signal_id == 0) {
				throw new RpcErrorCode.METHOD_NOT_FOUND (
					"No verb '" + verb + "' on " + kind
				);
			}

			GLib.Signal.emit_by_name (target, signal_name, this);
		}
	}
}
