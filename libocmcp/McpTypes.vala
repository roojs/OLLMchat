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
 * along with this library; if not, see <https://www.gnu.org/licenses/>.
 */

namespace OLLMmcp
{
	/** Client identity for MCP initialize (name + version). Defaults: ollmchat 1.0. */
	public class ClientInfo : Object, Json.Serializable
	{
		public string name { get; set; default = "ollmchat"; }
		public string version { get; set; default = "1.0"; }

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
	}

	/** MCP capabilities; empty object for now. */
	public class Capabilities : Object, Json.Serializable
	{
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
	}

	/**
	 * MCP initialize request params (client → server).
	 * Property names match MCP spec (camelCase). All values have defaults; use as-is.
	 */
	public class InitializeParams : Object, Json.Serializable
	{
		public string protocolVersion { get; set; default = "2024-11-05"; }
		public OLLMmcp.Capabilities capabilities { get; set; default = new OLLMmcp.Capabilities(); }
		public OLLMmcp.ClientInfo clientInfo { get; set; default = new OLLMmcp.ClientInfo(); }

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
	}

	/** Initialized notification (no id). Serialize with Json.gobject_serialize. */
	public class InitializedNotification : Object, Json.Serializable
	{
		public string jsonrpc { get; set; default = "2.0"; }
		public string method { get; set; default = "initialized"; }

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
	}

	/** JSON-RPC 2.0 request envelope. Set id, method, params; serialize with Json.gobject_serialize. */
	public class JsonRpcRequest : Object, Json.Serializable
	{
		public string jsonrpc { get; set; default = "2.0"; }
		public int id { get; set; }
		public string method { get; set; default = ""; }
		/**
		 * Request params: any Json.Serializable (e.g. InitializeParams, CallToolParams) or Json.Object for raw.
		 * Serialization maps to/from the "params" JSON key.
		 */
		public Object? params { get; set; default = null; }

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

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			if (property_name == "params") {
				if (this.params == null) {
					var empty = new Json.Node(Json.NodeType.OBJECT);
					empty.set_object(new Json.Object());
					return empty;
				}
				if (this.params is Json.Object) {
					var node = new Json.Node(Json.NodeType.OBJECT);
					node.set_object((Json.Object) this.params);
					return node;
				}
				return Json.gobject_serialize(this.params);
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name == "params") {
				this.params = (property_node.get_node_type() == Json.NodeType.OBJECT)
					? property_node.get_object()
				: new Json.Object();
				value = Value(typeof(Object));
				value.set_object(this.params);
				return true;
			}
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}

	/** Params for tools/call: name + arguments. Serialize with Json.gobject_serialize. */
	public class CallToolParams : Object, Json.Serializable
	{
		public string name { get; set; default = ""; }
		/** Tool call arguments as JSON object; serialization maps this to/from the "arguments" JSON key. */
		public Json.Object? arguments { get; set; }

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

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			if (property_name == "arguments") {
				var node = new Json.Node(Json.NodeType.OBJECT);
				node.set_object(this.arguments != null ? this.arguments : new Json.Object());
				return node;
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name == "arguments") {
				if (property_node.get_node_type() == Json.NodeType.OBJECT) {
					this.arguments = property_node.get_object();
				} else {
					this.arguments = new Json.Object();
				}
				value = Value(typeof(Json.Object));
				value.set_object(this.arguments);
				return true;
			}
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}

	/**
	 * MCP tools/list result: "result" object with "tools" array of Factory.
	 */
	public class ToolsListResult : Object, Json.Serializable
	{
		public Gee.ArrayList<Factory> tools { get; set; default = new Gee.ArrayList<Factory>(); }

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

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name != "tools") {
				return default_deserialize_property(property_name, out value, pspec, property_node);
			}
			if (property_node.get_node_type() == Json.NodeType.ARRAY) {
				var arr = property_node.get_array();
				for (uint i = 0; i < arr.get_length(); i++) {
					var elem = arr.get_element(i);
					var f = Json.gobject_deserialize(typeof(Factory), elem) as Factory;
					if (f != null) {
						this.tools.add(f);
					}
				}
			}
			value = Value(typeof(Gee.ArrayList));
			value.set_object(this.tools);
			return true;
		}
	}

	/**
	 * One content item in MCP tools/call result (type "text" with "text" field).
	 */
	public class CallToolContentItem : Object, Json.Serializable
	{
		public string type { get; set; default = "text"; }
		public string text { get; set; default = ""; }

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
	}

	/**
	 * MCP tools/call result: "result" object with "content" array.
	 */
	public class CallToolResult : Object, Json.Serializable
	{
		public Gee.ArrayList<CallToolContentItem> content { get; set; default = new Gee.ArrayList<CallToolContentItem>(); }

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

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name != "content") {
				return default_deserialize_property(property_name, out value, pspec, property_node);
			}
			if (property_node.get_node_type() == Json.NodeType.ARRAY) {
				var arr = property_node.get_array();
				for (uint i = 0; i < arr.get_length(); i++) {
					var elem = arr.get_element(i);
					var item = Json.gobject_deserialize(typeof(CallToolContentItem), elem) as CallToolContentItem;
					if (item != null) {
						this.content.add(item);
					}
				}
			}
			value = Value(typeof(Gee.ArrayList));
			value.set_object(this.content);
			return true;
		}

		/** Concatenate text from all content items with type "text". */
		public string text_content()
		{
			string result = "";
			foreach (var item in this.content) {
				if (item.type == "text" && item.text != "") {
					result += item.text;
				}
			}
			return result;
		}
	}

	/**
	 * JSON-RPC error object (response error member).
	 */
	public class McpJsonRpcError : Object, Json.Serializable
	{
		public int code { get; set; default = 0; }
		public string message { get; set; default = ""; }

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
	}
}
