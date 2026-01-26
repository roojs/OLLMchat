namespace OLLMapp
{
	/**
	 * Central registry for registering all tools.
	 * 
	 * Used by both Window and ollmchat-cli to ensure consistent tool registration.
	 * Has two phases: config registration (Phase 1) and tool instance registration (Phase 2).
	 */
	public class ToolRegistry : Object
	{
		/**
		 * Phase 1: Initializes tool config types with Config2.
		 * 
		 * Must be called before loading config. Ensures all tool GTypes are registered,
		 * then calls BaseTool.register_config() to discover and register config types.
		 * Does not require project_manager.
		 */
		public void init_config()
		{
			// Ensure all tool GTypes are registered in GType system
			// GType registration is lazy, so we need to explicitly reference each type
			typeof(OLLMtools.ReadFile.Tool).ensure();
			typeof(OLLMtools.RunCommand.Tool).ensure();
			typeof(OLLMtools.WebFetch.Tool).ensure();
			typeof(OLLMtools.EditMode.Tool).ensure();
			typeof(OLLMvector.Tool.CodebaseSearchTool).ensure();
			typeof(OLLMtools.GoogleSearch.Tool).ensure();
			
			// Register all tool config types with Config2
			// This discovers all tools via GType registry and registers their config types
			OLLMchat.Tool.BaseTool.register_config();
			
			GLib.debug("ToolRegistry.init_config: Registered tool config types");
		}
		
		/**
		 * Phase 2: Fills the manager with all tool instances.
		 * 
		 * Creates tool instances with project_manager and registers them.
		 * Also registers wrapped tools and agent tools.
		 * 
		 * @param manager The history manager to register tools with
		 * @param project_manager Optional project manager (null if not available)
		 */
		public void fill_tools(
			OLLMchat.History.Manager manager,
			OLLMfiles.ProjectManager? project_manager = null
		)
		{
			// Register standard tools with project_manager
			manager.register_tool(new OLLMtools.ReadFile.Tool(project_manager));
			manager.register_tool(new OLLMtools.RunCommand.Tool(project_manager));
			manager.register_tool(new OLLMtools.WebFetch.Tool(project_manager));
			manager.register_tool(new OLLMtools.EditMode.Tool(project_manager));
			manager.register_tool(new OLLMtools.GoogleSearch.Tool(project_manager));
			manager.register_tool(new OLLMvector.Tool.CodebaseSearchTool(project_manager));
			
			GLib.debug("ToolRegistry.fill_tools: Registered %d standard tools", 
				manager.tools.size);
			
			// Register wrapped tools from .tool definition files
			var builder = new OLLMtools.ToolBuilder(manager.tools);
			builder.scan_and_build();
			
			GLib.debug("ToolRegistry.fill_tools: Registered wrapped tools (total tools: %d)", 
				manager.tools.size);
			
			// Register agent tools from resources/agents/
			var parser = new OLLMtools.Child.Parser();
			parser.scan_and_register(manager, project_manager);
			
			GLib.debug("ToolRegistry.fill_tools: Registered agent tools (total tools: %d)", 
				manager.tools.size);
		}
	}
}
