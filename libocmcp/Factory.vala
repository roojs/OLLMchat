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
	 * Tool factory for one MCP tool: wraps descriptor data and creates
	 * a BaseTool instance for registration. Not part of MCP wire format;
	 * built from McpToolDescriptor after tools/list. The created tool
	 * is registered with Manager.register_tool() like other tools.
	 * (No Tool.Factory base exists in libollmchat to extend.)
	 *
	 * The created tool is registered via Manager.register_tool() like any
	 * other tool. When OLLMmcp.Tool exists (2.11.2), create_tool() returns it.
	 */
	public class Factory : Object
	{
		public string name { get; private set; default = ""; }
		public string description { get; private set; default = ""; }
		public Json.Node? input_schema { get; private set; default = null; }

		/** Build a Factory from the MCP wire descriptor (tools/list element). */
		public static Factory from_descriptor(McpToolDescriptor descriptor)
		{
			var f = new Factory();
			f.name = descriptor.name;
			f.description = descriptor.description;
			f.input_schema = descriptor.input_schema;
			return f;
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
