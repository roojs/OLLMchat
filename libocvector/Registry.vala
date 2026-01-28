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

namespace OLLMvector
{
	/**
	 * Registry for all tools in libocvector.
	 * 
	 * Registers: CodebaseSearchTool.
	 */
	public class Registry : Object
	{
		public void init_config()
		{
			// Ensure libocvector tool GTypes are registered
			typeof(Tool.CodebaseSearchTool).ensure();
			
			// Register only libocvector tool config types with Config2
			OLLMchat.Tool.BaseTool.register_config(typeof(Tool.CodebaseSearchTool));
			
			GLib.debug("OLLMvector.Registry.init_config: Registered libocvector tool config types");
		}
		
		public void setup_config_defaults(OLLMchat.Settings.Config2 config)
		{
			// Setup only libocvector tool configs
			// Creates default configs if they don't exist in the loaded config
			var tool = new Tool.CodebaseSearchTool(null);
			tool.setup_tool_config_default(config);
			
			GLib.debug("OLLMvector.Registry.setup_config_defaults: Set up libocvector tool configs");
		}
		
		public void fill_tools(
			OLLMchat.History.Manager manager,
			OLLMfiles.ProjectManager? project_manager = null
		)
		{
			// Register CodebaseSearchTool with project_manager
			manager.register_tool(new Tool.CodebaseSearchTool(project_manager));
			
			GLib.debug("OLLMvector.Registry.fill_tools: Registered CodebaseSearchTool (total tools: %d)", 
				manager.tools.size);
		}
	}
}
