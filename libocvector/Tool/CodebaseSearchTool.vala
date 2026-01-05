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

namespace OLLMvector.Tool
{
	/**
	 * Tool for semantic codebase search using vector embeddings.
	 * 
	 * This tool performs semantic search across the codebase using FAISS
	 * vector similarity search. It can filter results by language and
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
		public static void setup_tool_config(OLLMchat.Settings.Config2 config)
		{
			CodebaseSearchToolConfig tool_config;
			if (config.tools.has_key("codebase_search")) {
				tool_config = config.tools.get("codebase_search") as CodebaseSearchToolConfig;
			} else {
				tool_config = new CodebaseSearchToolConfig();
				var default_connection = config.get_default_connection();
				if (default_connection != null) {
					tool_config.setup_defaults(default_connection.url);
				}
				config.tools.set("codebase_search", tool_config);
			}
		}
		
		/**
		 * Gets and validates the codebase search tool configuration.
		 * 
		 * Returns the CodebaseSearchToolConfig from `Config2.tools["codebase_search"]` if it exists.
		 * Validates that:
		 * - Tool config exists
		 * - Embed and analysis ModelUsage have connection and model set
		 * - Connections exist in config
		 * - Models are available on the servers
		 * 
		 * If validation fails, sets `is_valid = false` on the ModelUsage objects,
		 * disables the tool, and logs warnings. If config doesn't exist, returns a disabled tool_config.
		 * 
		 * @param config The Config2 instance
		 * @return The CodebaseSearchToolConfig instance from tools map, or a disabled one if not found
		 */
		public static async CodebaseSearchToolConfig get_tool_config(
			OLLMchat.Settings.Config2 config)
		{
			if (!config.tools.has_key("codebase_search")) {
				var tool_config = new CodebaseSearchToolConfig();
				tool_config.enabled = false;
				return tool_config;
			}
			
			var tool_config = config.tools.get("codebase_search") as CodebaseSearchToolConfig;
			
			// Validate embed ModelUsage (verify_model checks connection and model availability)
			var embed_usage = tool_config.embed;
			if (!(yield embed_usage.verify_model(config))) {
				GLib.warning("Codebase search tool: Embed model verification failed");
				tool_config.enabled = false;
				return tool_config;
			}
			
			// Validate analysis ModelUsage (verify_model checks connection and model availability)
			var analysis_usage = tool_config.analysis;
			if (!(yield analysis_usage.verify_model(config))) {
				GLib.warning("Codebase search tool: Analysis model verification failed");
				tool_config.enabled = false;
				return tool_config;
			}
			
			// All validation passed
			return tool_config;
		}
		
		public override string name { get { return "codebase_search"; } }
		
		public override string title { get { return "Sematic Codebase Search Tool"; } }
		
		public override string description { get {
			return """
Search the codebase using semantic vector search to find code elements that match a query.

This tool performs semantic search across indexed code elements in the active project.
It can find classes, methods, functions, and other code elements based on their
semantic meaning, not just exact text matches.

IMPORTANT: This tool only searches source code files (e.g., .vala, .py, .js, .ts, .java, .cpp, etc.).
It does NOT search documentation files, markdown files (.md), HTML files, CSS files, or plain text files.
For searching documentation, use a different tool.

Use this tool when you need to:
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
@param element_type {string} [optional] Filter results by element type. Supported types: "class", "struct", "interface", "enum_type", "enum", "function", "method", "constructor", "property", "field", "delegate", "signal", "constant". Note: "namespace" is not searchable as namespace declarations are not indexed.
@param max_results {integer} [optional] Maximum number of results to return (default: 10).
""";
		} }
		
		/**
		 * Project manager for accessing active project and database.
		 */
		public OLLMfiles.ProjectManager? project_manager { get; private set; }
		
		/**
		 * Vector database for FAISS search.
		 * Created lazily when needed (requires async operation).
		 */
		public OLLMvector.Database? vector_db { get; private set; }
		
		/**
		 * Embedding client for query vectorization.
		 * Extracted from client.config if client is not null.
		 */
		public OLLMchat.Client? embedding_client { get; private set; }
		
		/**
		 * Hardcoded vector database path.
		 * Uses standard data directory: ~/.local/share/ollmchat/codedb.faiss.vectors
		 */
		private string vector_db_path {
			get {
				return GLib.Path.build_filename(
					GLib.Environment.get_home_dir(),
					".local", "share", "ollmchat", "codedb.faiss.vectors"
				);
			}
		}
		
		/**
		 * Constructor with nullable dependencies.
		 * 
		 * For Phase 1 (config registration): client and project_manager can be null.
		 * For Phase 2 (tool instance creation): client and project_manager are provided.
		 * 
		 * Embedding client is extracted from client.config.tools["codebase_search"] if available.
		 * Vector database is not created in constructor (requires async operation).
		 * 
		 * @param client LLM client (nullable for Phase 1)
		 * @param project_manager Project manager for accessing active project and database (nullable for Phase 1)
		 */
		public CodebaseSearchTool(
			OLLMchat.Client? client = null,
			OLLMfiles.ProjectManager? project_manager = null
		)
		{
			base(client);
			this.project_manager = project_manager;
			
			// Extract embedding_client from client.config if client is not null
			if (client != null && client.config != null) {
				// Get tool config and extract embed ModelUsage
				if (client.config.tools.has_key("codebase_search")) {
					var tool_config = client.config.tools.get("codebase_search") as CodebaseSearchToolConfig;
					if (tool_config != null) {
						var embed_usage = tool_config.embed;
						if (embed_usage.connection != "" && 
						    client.config.connections.has_key(embed_usage.connection)) {
							var embed_connection = client.config.connections.get(embed_usage.connection);
							this.embedding_client = new OLLMchat.Client(embed_connection) {
								config = client.config,
								model = embed_usage.model
							};
						}
					}
				}
			}
			
			// Note: vector_db is not created in constructor (requires async get_embedding_dimension)
			// It will be created when needed in Phase 2
		}
		
		public override Type config_class() { return typeof(CodebaseSearchToolConfig); }
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(RequestCodebaseSearch), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}

