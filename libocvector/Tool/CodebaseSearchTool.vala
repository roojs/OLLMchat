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
	public class CodebaseSearchTool : OLLMchat.Tool.Interface
	{
		public override string name { get { return "codebase_search"; } }
		
		public override string description { get {
			return """
Search the codebase using semantic vector search to find code elements that match a query.

This tool performs semantic search across indexed code elements in the active project.
It can find classes, methods, functions, and other code elements based on their
semantic meaning, not just exact text matches.

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
@param element_type {string} [optional] Filter results by element type (e.g., "class", "method", "function", "property").
@param max_results {integer} [optional] Maximum number of results to return (default: 10).
""";
		} }
		
		/**
		 * Project manager for accessing active project and database.
		 */
		public OLLMfiles.ProjectManager project_manager { get; private set; }
		
		/**
		 * Vector database for FAISS search.
		 */
		public OLLMvector.Database vector_db { get; private set; }
		
		/**
		 * Embedding client for query vectorization.
		 */
		public OLLMchat.Client embedding_client { get; private set; }
		
		/**
		 * Constructor with required dependencies.
		 * 
		 * @param client LLM client (required by base class)
		 * @param manager Project manager for accessing active project and database
		 * @param vector_db Vector database for FAISS search
		 * @param embedding_client Embedding client for query vectorization (may be same as client)
		 */
		public CodebaseSearchTool(
			OLLMchat.Client client,
			OLLMfiles.ProjectManager manager,
			OLLMvector.Database vector_db,
			OLLMchat.Client embedding_client
		)
		{
			base(client);
			this.project_manager = manager;
			this.vector_db = vector_db;
			this.embedding_client = embedding_client;
		}
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(RequestCodebaseSearch), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}

