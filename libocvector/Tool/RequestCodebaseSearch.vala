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
	 * 
	 * Handles codebase search requests from LLM function calls. Validates
	 * parameters, executes vector search, and formats results for LLM
	 * consumption. Integrates with CodebaseSearchTool to access vector
	 * database and project manager.
	 * 
	 * Supports filtering by language and element_type, and validates
	 * element_type against a list of supported types. Results are formatted
	 * with code citations using the standard citation format.
	 */
	public class RequestCodebaseSearch : OLLMchat.Tool.RequestBase
	{
		// Parameter properties (from LLM function call)
		public string query { get; set; default = ""; }
		public string language { get; set; default = ""; }
		public string element_type { get; set; default = ""; }
		public int max_results { get; set; default = 10; }
		
		/**
		 * Valid element types that can be searched.
		 * Note: "namespace" is not included as namespace declarations are not indexed.
		 */
		private static string[] VALID_ELEMENT_TYPES = {
			"class",
			"struct",
			"interface",
			"enum_type",
			"enum",
			"function",
			"method",
			"constructor",
			"property",
			"field",
			"delegate",
			"signal",
			"constant",
			"file"
		};
		
		/**
		 * Get formatted list of valid element types for error messages.
		 * 
		 * @return Formatted string listing all valid element types
		 */
		private static string get_valid_element_types_list()
		{
			var list = new StringBuilder();
			for (int i = 0; i < VALID_ELEMENT_TYPES.length; i++) {
				if (i > 0) {
					list.append(", ");
				}
				list.append("\"" + VALID_ELEMENT_TYPES[i] + "\"");
			}
			return list.str;
		}
		
		/**
		 * Validate element type parameter.
		 * 
		 * @param element_type Element type to validate
		 * @throws GLib.IOError.INVALID_ARGUMENT if element type is invalid
		 */
		private static void validate_element_type(string element_type) throws GLib.IOError
		{
			if (element_type == null || element_type.strip() == "") {
				return; // Empty is valid (no filter)
			}
			
			var normalized = element_type.strip().down();
			foreach (var valid_type in VALID_ELEMENT_TYPES) {
				if (normalized == valid_type) {
					return; // Found valid type
				}
			}
			
			// Invalid type - throw error with list of supported types
			var valid_types_list = get_valid_element_types_list();
			throw new GLib.IOError.INVALID_ARGUMENT(
				"You requested element type \"%s\", however we only support these types: %s".printf(
					element_type,
					valid_types_list
				)
			);
		}
		
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
			
			// Validate element type if provided
			validate_element_type(this.element_type);
			
			// Debug: Log input parameters
			GLib.debug("codebase_search input: query='%s', language='%s', element_type='%s', max_results=%d",
				this.query,
				this.language != "" ? this.language : "none",
				this.element_type != "" ? this.element_type : "none",
				this.max_results
			);
			
			// Build search request message with query and options
			var request_message = "Query: " + this.query;
			if (this.language != "") {
				request_message += "\nLanguage: " + this.language;
			}
			if (this.element_type != "") {
				request_message += "\nElement Type: " + this.element_type;
			}
			request_message += "\nMax Results: " + this.max_results.to_string();
			
			// Send search query to UI (same format as commands)
			this.send_ui("txt", "Code Search requested", request_message);
			
			// Step 1: Get active project from ProjectManager
			var active_project = this.project_manager.active_project;
			if (active_project == null) {
				throw new GLib.IOError.FAILED("No active project. Please open a project first.");
			}
			
			// Step 2: Get file IDs from project_files (with optional language filter)
			var file_ids = active_project.project_files.get_ids(this.language);
			
			if (file_ids.size == 0) {
				if (this.language != "") {
					throw new GLib.IOError.FAILED(
						"No files found in folder matching language filter: " + this.language
					);
				}
				throw new GLib.IOError.FAILED("No files found in folder");
			}
			
			// Step 3: Build filtered vector IDs using SQL query (exactly as oc-vector-search.vala does)
			var filtered_vector_ids = new Gee.ArrayList<int>();
			
			// Build SQL query string (file_ids joined directly, not parameterized)
			var sql = "SELECT DISTINCT vector_id FROM vector_metadata WHERE file_id IN (" +
				string.joinv(",", file_ids.to_array()) + ")";
			
			if (this.element_type != "") {
				sql = sql + " AND element_type = $element_type";
			}
			
			// Debug: Log vector filtering query
			GLib.debug("codebase_search vector filter: file_ids_count=%d, element_type='%s', sql='%s'",
				file_ids.size,
				this.element_type != "" ? this.element_type : "none",
				sql
			);
			
			// Use VectorMetadata.query() helper
			var sql_db = this.project_manager.db;
			if (sql_db == null) {
				throw new GLib.IOError.FAILED("Database not available");
			}
			
			var vector_query = OLLMvector.VectorMetadata.query(sql_db);
			var vector_stmt = vector_query.selectPrepare(sql);
			
			if (this.element_type != "") {
				vector_stmt.bind_text(
					vector_stmt.bind_parameter_index("$element_type"), this.element_type);
			}
			
			// Fetch vector IDs as strings and parse to int
			foreach (var vector_id_str in vector_query.fetchAllString(vector_stmt)) {
				filtered_vector_ids.add((int)int64.parse(vector_id_str));
			}
			
			// Debug: Log vector filtering results
			GLib.debug("codebase_search vector filter: found %d vector_id(s) matching filter",
				filtered_vector_ids.size
			);
			
			// Step 4: Create and execute search (exactly as oc-vector-search.vala does)
			// Get config via agent interface
			var config = this.agent.config();
			
			var search = new OLLMvector.Search.Search(
				this.vector_db,
				sql_db,
				config,
				active_project,
				this.query,
				(uint64)this.max_results,
				filtered_vector_ids,
				this.element_type  // Pass element_type filter to Search
			);
			
			// Execute search
			var results = yield search.execute();
			
			// Debug: Log output results
			GLib.debug("codebase_search output: found %d result(s) for query '%s'",
				results.size,
				this.query
			);
			
			// Step 5: Format results for LLM consumption
			var formatted = yield this.format_results(results, this.query);
			
			 
			// Send output as second message via message_created (same as commands)
			var result_title = "Code Search Return %d results".printf(results.size);
			this.send_ui("txt", result_title, formatted);
			
			return formatted;
		}
		
		/**
		 * Get code snippet from file using buffer system.
		 * 
		 * @param file The file to get snippet from
		 * @param start_line Starting line number (1-based, inclusive)
		 * @param end_line Ending line number (1-based, inclusive)
		 * @param max_lines Maximum number of lines to return (-1 for no limit)
		 * @return Code snippet as string
		 */
		private async string get_code_snippet(OLLMfiles.File file, int start_line, int end_line, int max_lines = -1)
		{
			try {
				// Ensure buffer exists
				if (file.buffer == null) {
					file.manager.buffer_provider.create_buffer(file);
				}
				
				// Ensure buffer is loaded
				if (!file.buffer.is_loaded) {
					yield file.buffer.read_async();
				}
				
				// Convert from 1-based (metadata) to 0-based (buffer API)
				var start_idx = start_line - 1;
				var end_idx = end_line - 1;
				
				// Apply max_lines truncation if specified
				if (max_lines != -1 && (end_idx - start_idx + 1) > max_lines) {
					end_idx = start_idx + max_lines - 1;
				}
				
				// Get text from buffer (0-based, inclusive)
				return file.buffer.get_text(start_idx, end_idx);
			} catch (GLib.Error e) {
				GLib.debug("codebase_search.get_code_snippet: Failed to read file %s: %s", file.path, e.message);
				return "";
			}
		}
		
		/**
		 * Format search results for LLM consumption.
		 * 
		 * @param results Search results to format
		 * @param query Original search query
		 * @return Formatted string with code citations
		 */
		private async string format_results(
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
				
				if (metadata.description != "") {
					output.append_printf("Description: %s\n", metadata.description);
				}
				
				if (metadata.ast_path != "") {
					output.append_printf("ast-path: %s\n", metadata.ast_path);
				}
				
				// Code citation block (citation format: startLine:endLine:filepath in language tag position)
				// Use buffer system to get code snippet
				var snippet = yield this.get_code_snippet(file, metadata.start_line, metadata.end_line, 50);
				
				// Debug: Log snippet details
				GLib.debug("codebase_search result %d: element='%s' type='%s' lines=%d-%d snippet_length=%d snippet_preview='%.100s'",
					i + 1,
					metadata.element_name,
					metadata.element_type,
					metadata.start_line,
					metadata.end_line,
					snippet.length,
					snippet
				);
				
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

