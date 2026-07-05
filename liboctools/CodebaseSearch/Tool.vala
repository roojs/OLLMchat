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

namespace OLLMtools.CodebaseSearch
{
	/**
	 * Tool for semantic codebase search using vector embeddings.
	 * 
	 * This tool performs semantic search across the codebase using vector
	 * similarity search on {{{ollmfilesd}}}. It can filter results by language and
	 * element type (class, method, function, etc.).
	 */
	public class CodebaseSearchTool : OLLMchat.Tool.BaseTool
	{
		/**
		 * Sets up the codebase search tool configuration with default connection.
		 * 
		 * Creates a CodebaseSearchToolConfig in `Config2.tools["codebase_search"]` if it doesn't exist.
		 * The config class already has default model names and options set in its properties.
		 * This method only sets the connection from the default connection. This replaces the separate
		 * setup_embed_usage() and setup_analysis_usage() methods with a unified setup.
		 */
		public override void setup_tool_config_default(OLLMchat.Settings.Config2 config)
		{
			var default_connection = config.default_connection();
			if (!config.tools.has_key("codebase_search")) {
				var tool_config = new CodebaseSearchToolConfig();
				if (default_connection != null) {
					tool_config.setup_defaults(default_connection.url);
				}
				config.tools.set("codebase_search", tool_config);
				return;
			}
			if (default_connection == null) {
				return;
			}
			var tool_config = config.tools.get("codebase_search") as CodebaseSearchToolConfig;
			if (tool_config.embed.connection != ""
				&& tool_config.embed.model != ""
				&& tool_config.analysis.connection != ""
				&& tool_config.analysis.model != "") {
				return;
			}
			tool_config.setup_defaults(default_connection.url);
			config.save();
		}
		
		public override string name { get { return "codebase_search"; } }
		public override string title { get { return "Semantic Codebase Search Tool"; } }
		public override string example_call {
			get { return "{\"name\": \"codebase_search\", \"arguments\": {\"query\": \"where is file reading implemented\"}}"; }
		}
		public override string description { get {
			return """
Search the codebase using semantic vector search to find code elements that match a query.

This tool performs semantic search across indexed code elements in the active project.
It can find files, classes, methods, functions, and other code elements based on their
semantic meaning, not just exact text matches.

IMPORTANT: This tool only searches source code files (e.g., .vala, .py, .js, .ts, .java, .cpp, etc.).
It does NOT search documentation files, markdown files (.md), HTML files, CSS files, or plain text files.
For searching documentation, use a different tool.

Use this tool when you need to:
- Find files that contain specific functionality or topics
- Find code that implements a specific functionality
- Locate classes or methods by their purpose or behavior
- Search for code patterns or design implementations
- Discover related code elements across the codebase

The search uses vector embeddings to understand the semantic meaning of code,
making it more effective than simple text search for finding relevant code.
""";
		} }
		
		public override string parameter_description { get {
			return """
@param query {string} [required] The search query text describing what code to find.
@param language {string} [optional] Filter results by programming language (e.g., "vala", "python", "javascript").
@param element_type {string} [optional] Filter results by element type. Code: "class", "struct", "interface", "enum_type", "enum", "function", "method", "constructor", "property", "field", "delegate", "signal", "constant", "file". Documentation: "document", "section". Note: "namespace" is not searchable.
@param category {string} [optional] Filter documentation by category. Valid values: "plan", "documentation", "rule", "configuration", "data", "license", "changelog", "other". Only applies to doc elements (document/section).
@param max_results {integer} [optional] Maximum number of results to return (default: 10).
""";
		} }
		
		/**
		 * Project manager for accessing active project and {@link OLLMrpc.Client}.
		 */
		public OLLMfiles.ProjectManager? project_manager { get; private set; }
		
		/**
		* Constructor with nullable dependencies.
		* 
		* For Phase 1 (config registration): project_manager can be null.
		* For Phase 2 (tool instance creation): project_manager is provided.
		* 
		* If project_manager is provided, init_dependencies() is called automatically.
		* 
		* @param project_manager Project manager for RPC to ollmfilesd (nullable for Phase 1)
		*/
		public CodebaseSearchTool(
			OLLMfiles.ProjectManager? project_manager = null
		)
		{
			base();
			// If project_manager is provided, initialize dependencies immediately
			if (project_manager != null) {
				this.init_dependencies(project_manager);
			}
		}
		
		/**
		* Initializes tool dependencies after creation.
		* 
		* Called after tool is created via Object.new() to set dependencies
		* that weren't available during registration. Also called from constructor
		* if project_manager is provided.
		* 
		* Returns early if project_manager is already set to avoid re-initialization.
		* 
		* @param project_manager Project manager instance (required)
		*/
		public void init_dependencies(OLLMfiles.ProjectManager project_manager)
		{
			// Return early if already initialized
			if (this.project_manager != null) {
				return;
			}
			
			this.project_manager = project_manager;
		}
		
		public override Type config_class() { return typeof(CodebaseSearchToolConfig); }
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(RequestCodebaseSearch), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}
