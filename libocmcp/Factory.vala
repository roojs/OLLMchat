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
	/**
	 * Tool factory for one MCP tool. Same shape as MCP tools/list element (name, description, inputSchema);
	 * deserialized directly from the wire. The created tool is registered via Manager.register_tool().
	 * When OLLMmcp.Tool exists (2.11.2), create_tool() returns it.
	 */
	public class Factory : Object, Json.Serializable
	{
		public string name { get; set; default = ""; }
		public string description { get; set; default = ""; }
		/** JSON Schema for parameters (MCP wire name "inputSchema"). */
		public Json.Object? inputSchema { get; set; default = null; }

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
			if (property_name == "inputSchema") {
				var node = new Json.Node(Json.NodeType.OBJECT);
				node.set_object(this.inputSchema != null ? this.inputSchema : new Json.Object());
				return node;
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name == "inputSchema") {
				this.inputSchema = (property_node.get_node_type() == Json.NodeType.OBJECT)
					? property_node.get_object()
					: new Json.Object();
				value = Value(typeof(Json.Object));
				value.set_object(this.inputSchema);
				return true;
			}
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}

		/**
		 * Create the BaseTool for this MCP tool; register it with Manager.register_tool().
		 * Implemented when OLLMmcp.Tool exists (2.11.2).
		 */
		public virtual OLLMchat.Tool.BaseTool create_tool(Client.Base client, string server_id) throws GLib.Error
		{
			// OLLMmcp.Tool (extends BaseTool) will be added in 2.11.2
			throw new GLib.IOError.NOT_IMPLEMENTED(
				"OLLMmcp.Tool not yet implemented; create_tool() will return new Tool(client, server_id, this)"
			);
		}
	}
}
