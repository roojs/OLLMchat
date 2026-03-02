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

namespace OLLMtools.Child
{
	/**
	 * Main tool class that executes agent requests.
	 *
	 * Each agent from resources/agents/ is registered as a separate tool
	 * using this class. The tool accepts a query parameter and executes
	 * the agent with that query.
	 */
	public class Tool : OLLMchat.Tool.BaseTool
	{
		/**
		 * Agent name (from frontmatter).
		 */
		public string agent_name { get; set; }
		
		/**
		 * Agent description (from frontmatter).
		 */
		public string agent_description { get; set; }
		
		/**
		 * List of tool names the agent can use.
		 */
		public Gee.ArrayList<string> agent_tools { get; set; }
		
		/**
		 * Agent model preference (from frontmatter, may be empty).
		 */
		public string agent_model { get; set; }
		
		/**
		 * Agent instructions (from agent file, after frontmatter).
		 */
		public string agent_instructions { get; set; }
		
		/**
		 * Example call JSON (from agent frontmatter ''example:'').
		 * When set, ''example_call'' returns this; otherwise a default with ''agent_name'' is used.
		 */
		public string agent_example { get; set; default = ""; }
		
		/**
		 * Tool name (returns agent_name).
		 */
		public override string name { get { return this.agent_name; } }
		
		/**
		 * Tool description (returns agent_description).
		 */
		public override string description { get {
			return this.agent_description;
		} }
		
		public override string title { get { return this.agent_name; } }
		public override string example_call { get { return this.agent_example; } }
		/**
		 * Parameter description for the tool.
		 */
		public override string parameter_description { get {
			return """
@param query {string} [required] The query or prompt to send to the agent.""";
		} }
		
		/**
		 * Config class for this tool.
		 * TODO: Will be implemented in Phase 5 with Child.Config
		 */
		public override Type config_class() { 
			return typeof(OLLMchat.Settings.BaseToolConfig); 
		}
		
		/**
		 * Sets up the agent tool configuration with default connection.
		 * 
		 * Creates an AgentToolConfig in `Config2.tools[agent_name]` if it doesn't exist.
		 * The config class has a default ModelUsage property that can be configured.
		 * 
		 * TODO: Will be fully implemented in Phase 5 with Child.Config
		 */
		public override void setup_tool_config_default(OLLMchat.Settings.Config2 config)
		{
			// Phase 1: Basic implementation - will be enhanced in Phase 5
			if (config.tools.has_key(this.agent_name)) {
				return;
			}
			
			// Create basic config (will use Child.Config in Phase 5)
			var tool_config = new OLLMchat.Settings.BaseToolConfig();
			config.tools.set(this.agent_name, tool_config);
		}
		
		/**
		 * ProjectManager instance for accessing project context.
		 * Optional - set to null if not available.
		 */
		public OLLMfiles.ProjectManager? project_manager { get; set; default = null; }
		
		/**
		 * Creates a new Tool instance.
		 *
		 * @param project_manager Optional project manager
		 */
		public Tool(OLLMfiles.ProjectManager? project_manager = null)
		{
			base();
			this.project_manager = project_manager;
		}
		
		/**
		 * Deserializes request parameters from JSON.
		 *
		 * @param parameters_node JSON node containing parameters
		 * @return Request instance, or null on error
		 */
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(Request), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}
