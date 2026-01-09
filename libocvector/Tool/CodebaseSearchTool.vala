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
		public override void setup_tool_config(OLLMchat.Settings.Config2 config)
		{
			if (config.tools.has_key("codebase_search")) {
				return;
			}
			
			var tool_config = new CodebaseSearchToolConfig();
			var default_connection = config.get_default_connection();
			if (default_connection != null) {
				tool_config.setup_defaults(default_connection.url);
			}
			config.tools.set("codebase_search", tool_config);
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
		public OLLMvector.Database? vector_db { get; internal set; }
		
		/**
		 * Embedding client for query vectorization.
		 * Extracted from client.config if client is not null.
		 */
		public OLLMchat.Client? embedding_client { get; internal set; }
		
		/**
		 * Vector database file path.
		 * Set in init_databases(), used to create the database.
		 */
		private string? vector_db_path = null;
		
		/**
		 * Constructor with nullable dependencies.
		 * 
		 * For Phase 1 (config registration): client and project_manager can be null.
		 * For Phase 2 (tool instance creation): client and project_manager are provided.
		 * 
		 * Embedding client is extracted from client.config.tools["codebase_search"] if available.
		 * Vector database is not created in constructor (requires async operation).
		 * Call init_databases() after construction to create the vector database.
		 * 
		 * @param client LLM client (nullable for Phase 1)
		 * @param project_manager Project manager for accessing active project and database (nullable for Phase 1)
		 */
		public CodebaseSearchTool(
			OLLMfiles.ProjectManager? project_manager = null
		)
		{
			base();
			this.project_manager = project_manager;
			
			// Embedding client will be extracted lazily when config is available
			// (e.g., in init_databases or when tool is used with Manager context)
		}
		
		/**
		 * Initializes the vector database by getting dimension and creating the Database instance.
		 * 
		 * This method should be called after the tool is constructed and embedding_client is set.
		 * It performs the async operation to get the embedding dimension and creates the vector_db.
		 * 
		 * @param config Config2 instance for database initialization
		 * @param data_dir Data directory for vector database.
		 * @throws GLib.Error if initialization fails
		 */
		public async void init_databases(OLLMchat.Settings.Config2 config, string data_dir) throws GLib.Error
		{
			if (this.vector_db != null) {
				return; // Already initialized
			}
			
			// Extract embedding_client from config if not already set
			if (this.embedding_client == null) {
				if (!config.tools.has_key("codebase_search")) {
					throw new GLib.IOError.FAILED("codebase_search tool config not found");
				}
				
				var tool_config = config.tools.get("codebase_search") as CodebaseSearchToolConfig;
				if (tool_config.embed.connection == "" || 
					!config.connections.has_key(tool_config.embed.connection)) {
					throw new GLib.IOError.FAILED("codebase_search embed connection not configured");
				}
				
				this.embedding_client = new OLLMchat.Client(config.connections.get(tool_config.embed.connection));
			}
			
			// Set vector database path
			this.vector_db_path = GLib.Path.build_filename(data_dir, "codedb.faiss.vectors");
			
			// Get dimension first, then create database
			var temp_db = new OLLMvector.Database(config, 
				this.vector_db_path, OLLMvector.Database.DISABLE_INDEX);
			var dimension = yield temp_db.embed_dimension();
			this.vector_db = new OLLMvector.Database(config, this.vector_db_path, dimension);
		}
		
		public override Type config_class() { return typeof(CodebaseSearchToolConfig); }
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(RequestCodebaseSearch), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}

