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
	/** Client identity for MCP initialize (name + version). */
	public class ClientInfo : Object, Json.Serializable
	{
		public string name { get; set; default = ""; }
		public string version { get; set; default = ""; }

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
	 * Build with with_client(name, version); send in JSON-RPC via to_params_json().
	 */
	public class InitializeParams : Object, Json.Serializable
	{
		public string protocol_version { get; set; default = "2024-11-05"; }
		public OLLMmcp.Capabilities capabilities { get; set; default = new OLLMmcp.Capabilities(); }
		public OLLMmcp.ClientInfo client_info { get; set; }

		/** Build params for the initialize request; client_info is set to name and version. */
		public InitializeParams.with_client(string name, string version)
		{
			this.client_info = new OLLMmcp.ClientInfo() {
				name = name,
				version = version
			};
		}

		/** Serialize params to JSON string using gobject_serialize for nested objects. */
		public string to_params_json()
		{
			var root = new Json.Object();
			root.set_string_member("protocolVersion", this.protocol_version);
			root.set_member("clientInfo", Json.gobject_serialize(this.client_info));
			root.set_member("capabilities", Json.gobject_serialize(this.capabilities));
			var node = new Json.Node(Json.NodeType.OBJECT);
			node.set_object(root);
			return Json.to_string(node, false);
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

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "protocolVersion":
					return default_serialize_property("protocol_version", value, pspec);
				case "capabilities":
					return default_serialize_property("capabilities", value, pspec);
				case "clientInfo":
					return default_serialize_property("client_info", value, pspec);
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "protocolVersion":
					return default_deserialize_property("protocol_version", out value, pspec, property_node);
				case "capabilities":
					return default_deserialize_property("capabilities", out value, pspec, property_node);
				case "clientInfo":
					return default_deserialize_property("client_info", out value, pspec, property_node);
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
	}

	/** JSON-RPC helpers: work with strings and GLib.Objects; avoid Json.Object in client code. */
	public static class McpJson
	{
		/** Serialize a Json.Object to JSON string (boundary only; prefer GObject + to_params_json). */
		public static string object_to_string(Json.Object obj)
		{
			var node = new Json.Node(Json.NodeType.OBJECT);
			node.set_object(obj);
			return Json.to_string(node, false);
		}

		/** Build full JSON-RPC request body string from method and params JSON string. */
		public static string build_request_body(uint id, string method, string? params_json)
		{
			var envelope = new Json.Object();
			envelope.set_string_member("jsonrpc", "2.0");
			envelope.set_int_member("id", (int) id);
			envelope.set_string_member("method", method);
			string p = params_json ?? "{}";
			var parser = new Json.Parser();
			try {
				parser.load_from_data(p, -1);
				envelope.set_member("params", parser.get_root());
			} catch (GLib.Error e) {
				var empty = new Json.Node(Json.NodeType.OBJECT);
				empty.set_object(new Json.Object());
				envelope.set_member("params", empty);
			}
			var node = new Json.Node(Json.NodeType.OBJECT);
			node.set_object(envelope);
			return Json.to_string(node, false);
		}

		/** Body for the initialized notification (no id, no response). */
		public static string initialized_notification_body()
		{
			var obj = new Json.Object();
			obj.set_string_member("jsonrpc", "2.0");
			obj.set_string_member("method", "initialized");
			var node = new Json.Node(Json.NodeType.OBJECT);
			node.set_object(obj);
			return Json.to_string(node, false);
		}
	}

	/** Params for tools/call: name + arguments. Use with_arguments() at boundary (Json.Object → string). */
	public class CallToolParams : Object
	{
		public string name { get; private set; default = ""; }
		public string arguments_json { get; private set; default = "{}"; }

		public static CallToolParams with_arguments(string name, Json.Object arguments)
		{
			var p = new CallToolParams();
			p.name = name;
			p.arguments_json = McpJson.object_to_string(arguments);
			return p;
		}

		/** Serialize to JSON string for the RPC params. */
		public string to_params_json()
		{
			var parser = new Json.Parser();
			try {
				parser.load_from_data(this.arguments_json, -1);
			} catch (GLib.Error e) {
				var empty = new Json.Node(Json.NodeType.OBJECT);
				empty.set_object(new Json.Object());
				var obj = new Json.Object();
				obj.set_string_member("name", this.name);
				obj.set_member("arguments", empty);
				var node = new Json.Node(Json.NodeType.OBJECT);
				node.set_object(obj);
				return Json.to_string(node, false);
			}
			var obj = new Json.Object();
			obj.set_string_member("name", this.name);
			obj.set_member("arguments", parser.get_root());
			var node = new Json.Node(Json.NodeType.OBJECT);
			node.set_object(obj);
			return Json.to_string(node, false);
		}
	}

	/**
	 * MCP tool descriptor from tools/list (wire format).
	 * Serialization only; use Factory to represent the tool and create BaseTool instances.
	 */
	public class McpToolDescriptor : Object, Json.Serializable
	{
		public string name { get; set; default = ""; }
		public string description { get; set; default = ""; }
		public Json.Node? input_schema { get; set; default = null; }

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
			if (property_name == "input_schema") {
				if (this.input_schema != null) {
					return this.input_schema;
				}
				var empty = new Json.Node(Json.NodeType.OBJECT);
				empty.set_object(new Json.Object());
				return empty;
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name == "inputSchema") {
				this.input_schema = property_node;
				value = Value(typeof(Json.Node));
				value.set_object(property_node);
				return true;
			}
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}

	/**
	 * MCP tools/list result: "result" object with "tools" array of McpToolDescriptor.
	 */
	public class ToolsListResult : Object, Json.Serializable
	{
		public Gee.ArrayList<McpToolDescriptor> tools { get; set; default = new Gee.ArrayList<McpToolDescriptor>(); }

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
			this.tools.clear();
			if (property_node.get_node_type() == Json.NodeType.ARRAY) {
				var arr = property_node.get_array();
				for (uint i = 0; i < arr.get_length(); i++) {
					var elem = arr.get_element(i);
					var d = Json.gobject_deserialize(typeof(McpToolDescriptor), elem) as McpToolDescriptor;
					if (d != null) {
						this.tools.add(d);
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
			this.content.clear();
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
