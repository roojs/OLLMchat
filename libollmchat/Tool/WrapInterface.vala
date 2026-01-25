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

namespace OLLMchat.Tool
{
	/**
	 * Interface for tools that can be wrapped by other tools.
	 *
	 * Only tools that implement this interface can be wrapped. Each tool
	 * implements deserialize_wrapped() differently based on its needs.
	 * For example, RunCommand.Tool might construct a command string from
	 * a template, while WebFetch.Tool might parse arguments differently
	 * for URL construction.
	 */
	public interface WrapInterface : Object
	{
		/**
		 * Deserializes wrapped tool parameters into a Request object.
		 *
		 * This method is called when a wrapped tool is executed. It extracts
		 * the arguments from the JSON parameters and converts them according
		 * to the tool's needs, using the provided command template.
		 *
		 * @param parameters_node The parameters as a Json.Node
		 * @param command_template The command template with {arguments} placeholder
		 * @return A RequestBase instance or null if deserialization fails
		 */
		public abstract RequestBase? deserialize_wrapped(Json.Node parameters_node, string command_template);
		
		/**
		 * Creates a clone of this tool with the same project_manager.
		 *
		 * This method is used by ToolBuilder when creating wrapped tool instances.
		 * Tools that can be wrapped should implement this to create a new instance
		 * with the same project_manager.
		 *
		 * @return A new tool instance with the same project_manager
		 */
		public abstract BaseTool clone();
	}
}
