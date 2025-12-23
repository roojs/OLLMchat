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
	 * Request handler for codebase search operations.
	 */
	public class RequestCodebaseSearch : OLLMchat.Tool.RequestBase
	{
		// Parameter properties (from LLM function call)
		public string query { get; set; default = ""; }
		public string? language { get; set; default = null; }
		public string? element_type { get; set; default = null; }
		public int max_results { get; set; default = 10; }
		
		/**
		 * Default constructor.
		 */
		public RequestCodebaseSearch()
		{
		}
		
		/**
		 * Project manager from tool.
		 */
		private OLLMfiles.ProjectManager project_manager {
			get { return (this.tool as OLLMvector.Tool.CodebaseSearchTool).project_manager; }
		}
		
		/**
		 * Vector database from tool.
		 */
		private OLLMvector.Database vector_db {
			get { return (this.tool as OLLMvector.Tool.CodebaseSearchTool).vector_db; }
		}
		
		/**
		 * Embedding client from tool.
		 */
		private OLLMchat.Client embedding_client {
			get { return (this.tool as OLLMvector.Tool.CodebaseSearchTool).embedding_client; }
		}
		
		protected override bool build_perm_question()
		{
			// Codebase search is read-only and doesn't require permission prompts
			return false;
		}
		
		protected override async string execute_request() throws Error
		{
			// Validate required parameter
			if (this.query == null || this.query.strip() == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("Query parameter is required");
			}
			
			// Emit execution message
			this.chat_call.client.tool_message(
				new OLLMchat.Message(
					this.chat_call,
					"ui",
					"Executing codebase search for: " + this.query
				)
			);
			
			// Step 1: Get active project from ProjectManager
			var active_project = this.project_manager.active_project;
			if (active_project == null) {
				throw new GLib.IOError.FAILED("No active project. Please open a project first.");
			}
			
			// Step 2: Get file IDs from project_files (with optional language filter)
			var language_filter = this.language != null ? this.language : "";
			var file_ids = active_project.project_files.get_ids(language_filter);
			
			if (file_ids.size == 0) {
				if (language_filter != "") {
					throw new GLib.IOError.FAILED(
						"No files found in folder matching language filter: " + language_filter
					);
				}
				throw new GLib.IOError.FAILED("No files found in folder");
			}
			
			// Step 3: Build filtered vector IDs using SQL query (exactly as oc-vector-search.vala does)
			var filtered_vector_ids = new Gee.ArrayList<int>();
			
			// Build SQL query string (file_ids joined directly, not parameterized)
			var sql = "SELECT DISTINCT vector_id FROM vector_metadata WHERE file_id IN (" +
				string.joinv(",", file_ids.to_array()) + ")";
			
			if (this.element_type != null) {
				sql = sql + " AND element_type = $element_type";
			}
			
			// Use VectorMetadata.query() helper
			var sql_db = this.project_manager.db;
			if (sql_db == null) {
				throw new GLib.IOError.FAILED("Database not available");
			}
			
			var vector_query = OLLMvector.VectorMetadata.query(sql_db);
			var vector_stmt = vector_query.selectPrepare(sql);
			
			if (this.element_type != null) {
				vector_stmt.bind_text(
					vector_stmt.bind_parameter_index("$element_type"), this.element_type);
			}
			
			// Fetch vector IDs as strings and parse to int
			foreach (var vector_id_str in vector_query.fetchAllString(vector_stmt)) {
				filtered_vector_ids.add((int)int64.parse(vector_id_str));
			}
			
			// Step 4: Create and execute search (exactly as oc-vector-search.vala does)
			var search = new OLLMvector.Search.Search(
				this.vector_db,
				sql_db,
				this.embedding_client,
				active_project,
				this.query,
				(uint64)this.max_results,
				filtered_vector_ids
			);
			
			// Execute search
			var results = yield search.execute();
			
			// Step 5: Format results for LLM consumption
			return this.format_results(results, this.query);
		}
		
		/**
		 * Format search results for LLM consumption.
		 * 
		 * @param results Search results to format
		 * @param query Original search query
		 * @return Formatted string with code citations
		 */
		private string format_results(
			Gee.ArrayList<OLLMvector.Search.SearchResult> results,
			string query
		)
		{
			if (results.size == 0) {
				return "No results found for \"" + query + "\"";
			}
			
			var output = new StringBuilder();
			output.append_printf("Found %d result(s) for \"%s\":\n\n",
				 results.size, query);
			
			for (int i = 0; i < results.size; i++) {
				var result = results[i];
				var file = result.file();
				var metadata = result.metadata;
				
				// Format result header
				output.append_printf(
					"%d. %s (%s) - %s:%d-%d\n",
					i + 1,
					metadata.element_name,
					metadata.element_type,
					file.path,
					metadata.start_line,
					metadata.end_line
				);
				
				if (metadata.description != null && metadata.description != "") {
					output.append_printf("Description: %s\n", metadata.description);
				}
				
				// Code citation block (citation format: startLine:endLine:filepath in language tag position)
				var snippet = result.code_snippet(50);
				output.append_printf(
					"```%d:%d:%s\n%s\n```\n",
					metadata.start_line,
					metadata.end_line,
					file.path,
					snippet
				);
				
				// Check if snippet was truncated
				var original_line_count = metadata.end_line - metadata.start_line + 1;
				if (original_line_count > 50) {
					output.append_printf("... (%d more lines)\n", 
						original_line_count - 50);
				}
				
				output.append("\n");
			}
			
			return output.str;
		}
	}
}

