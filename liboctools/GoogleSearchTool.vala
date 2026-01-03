/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
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
	 * Tool for performing web searches using Google Custom Search API.
	 *
	 * This tool performs web searches and returns results in markdown format.
	 * Requires Google Custom Search API credentials configured in ~/.config/ollmchat/google.json
	 */
	public class GoogleSearchTool : OLLMchat.Tool.Interface
	{
		/**
		 * Registers the Google search tool configuration type in Config2.
		 * 
		 * This should be called before loading config to register
		 * "google_search" as a GoogleSearchToolConfig type for deserialization.
		 */
		public static void register_config()
		{
			// Register the tool config type
			OLLMchat.Settings.Config2.register_tool_type("google_search", typeof(Tool.GoogleSearchToolConfig));
		}
		
		/**
		 * Sets up the Google search tool configuration with default values.
		 * 
		 * Creates a GoogleSearchToolConfig in `Config2.tools["google_search"]` if it doesn't exist.
		 * The config will have empty api_key and engine_id, which the user must configure.
		 * 
		 * If a new config is created, it will be saved automatically. If saving fails, a warning
		 * will be logged but the method will still return true (config was created successfully).
		 * 
		 * @param config The Config2 instance to update
		 * @return true if the tool config was created, false if it already existed
		 */
		public static bool setup_tool_config(OLLMchat.Settings.Config2 config)
		{
			// Only create if it doesn't already exist
			if (config.tools.has_key("google_search")) {
				return false;
			}
			
			// Create tool config with empty values (user must configure api_key and engine_id)
			var tool_config = new Tool.GoogleSearchToolConfig();
			config.tools.set("google_search", tool_config);
			
			// Save config if we created new entries (so they persist)
			config.save();
			
			return true;
		}
		
		public override string name { get { return "google_search"; } }
		
		public override string description { get {
			return """
Perform a web search using Google Custom Search API and return results in markdown format.

This tool searches the web and returns a list of relevant results with titles, snippets, and links.
Results are formatted as markdown for easy reading.

The tool requires permission to access the Google Custom Search API.""";
		} }
		
		public override string parameter_description { get {
			return """
@param query {string} [required] The search query string.
@param start {int} [optional] The starting index for results (default: 1). Use this to paginate through results.""";
		} }
		
		/**
		 * ProjectManager instance for accessing project context.
		 * Optional - set to null if not available.
		 */
		public OLLMfiles.ProjectManager? project_manager { get; set; default = null; }
		
		public GoogleSearchTool(OLLMchat.Client client, OLLMfiles.ProjectManager? project_manager = null)
		{
			base(client);
			this.project_manager = project_manager;
		}
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(GoogleSearchRequest), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}

