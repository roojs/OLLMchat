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

namespace OLLMtools
{
	/**
	 * Registry for all tools in liboctools.
	 * 
	 * Registers: ReadFile, RunCommand, WebFetch, EditMode, GoogleSearch,
	 * wrapped tools (via ToolBuilder), and agent tools (via Child.Parser).
	 */
	public class Registry : Object
	{
		public void init_config()
		{
			// Ensure all liboctools tool GTypes are registered
			typeof(ReadFile.Tool).ensure();
			typeof(RunCommand.Tool).ensure();
			typeof(WebFetch.Tool).ensure();
			typeof(EditMode.Tool).ensure();
			typeof(GoogleSearch.Tool).ensure();
			
			// Register all tool config types with Config2
			OLLMchat.Tool.BaseTool.register_config();
			
			GLib.debug("OLLMtools.Registry.init_config: Registered liboctools tool config types");
		}
		
		public void fill_tools(
			OLLMchat.History.Manager manager,
			OLLMfiles.ProjectManager? project_manager = null
		)
		{
			// Register standard liboctools tools with project_manager
			manager.register_tool(new ReadFile.Tool(project_manager));
			manager.register_tool(new RunCommand.Tool(project_manager));
			manager.register_tool(new WebFetch.Tool(project_manager));
			manager.register_tool(new EditMode.Tool(project_manager));
			manager.register_tool(new GoogleSearch.Tool(project_manager));
			
			GLib.debug("OLLMtools.Registry.fill_tools: Registered %d liboctools standard tools", 
				manager.tools.size);
			
			// Register wrapped tools from .tool definition files
			var builder = new ToolBuilder(manager.tools);
			builder.scan_and_build();
			
			GLib.debug("OLLMtools.Registry.fill_tools: Registered wrapped tools (total tools: %d)", 
				manager.tools.size);
			
			// Register agent tools from resources/agents/
			var parser = new Child.Parser();
			parser.scan_and_register(manager, project_manager);
				
			GLib.debug("OLLMtools.Registry.fill_tools: Registered agent tools (total tools: %d)", 
			manager.tools.size);
	}
	}
}
