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
	 * Cached file contents with lines array (same as BufferProviderBase).
	 */
	private class FileCacheEntry : Object
	{
		public string[] lines { get; set; }
		
		public FileCacheEntry(string[] lines)
		{
			this.lines = lines;
		}
	}
	
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
		 * File cache for this query (same structure as BufferProviderBase).
		 * Maps file path => FileCacheEntry with lines array.
		 */
		private Gee.HashMap<string, FileCacheEntry> file_cache = new Gee.HashMap<string, FileCacheEntry>();
		
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
			
			// Debug: Log input parameters
			GLib.debug("codebase_search input: query='%s', language=%s, element_type=%s, max_results=%d",
				this.query,
				this.language ?? "null",
				this.element_type ?? "null",
				this.max_results
			);
			
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
			
			// Debug: Log vector filtering query
			GLib.debug("codebase_search vector filter: file_ids_count=%d, element_type=%s, sql='%s'",
				file_ids.size,
				this.element_type ?? "null",
				sql
			);
			
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
			
			// Debug: Log vector filtering results
			GLib.debug("codebase_search vector filter: found %d vector_id(s) matching filter",
				filtered_vector_ids.size
			);
			
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
			
			// Debug: Log output results
			GLib.debug("codebase_search output: found %d result(s) for query '%s'",
				results.size,
				this.query
			);
			
			// Step 5: Format results for LLM consumption (this will cache files)
			var formatted = yield this.format_results(results, this.query);
			
			// Clear file cache at end of query
			var cache_size = this.file_cache.size;
			this.file_cache.clear();
			GLib.debug("codebase_search: cleared file cache (%d entries)", cache_size);
			
			return formatted;
		}
		
		/**
		 * Get lines array from cache or file using File.read_async().
		 * 
		 * @param file The file to load
		 * @return Lines array, or empty array if file cannot be read
		 */
		private async string[] get_lines(OLLMfiles.File file)
		{
			// Check cache first
			if (this.file_cache.has_key(file.path)) {
				return this.file_cache.get(file.path).lines;
			}
			
			string[] ret = {}; 
			// Load from file using File.read_async()
			try {
				var contents = yield file.read_async();
				
				var lines_array = contents.split("\n");
				var cache_entry = new FileCacheEntry(lines_array);
				this.file_cache.set(file.path, cache_entry);
				GLib.debug("codebase_search.get_lines: Loaded and cached file: %s (%d lines)", 
					file.path, lines_array.length);
				return lines_array;
			} catch (GLib.Error e) {
				GLib.debug("codebase_search.get_lines: Failed to read file %s: %s", file.path, e.message);
				return ret;
			}
		}
		
		/**
		 * Get code snippet from file using cached lines array.
		 * 
		 * @param file The file to get snippet from
		 * @param start_line Starting line number (1-based, inclusive)
		 * @param end_line Ending line number (1-based, inclusive)
		 * @param max_lines Maximum number of lines to return (-1 for no limit)
		 * @return Code snippet as string
		 */
		private async string get_code_snippet(OLLMfiles.File file, int start_line, int end_line, int max_lines = -1)
		{
			var lines = yield this.get_lines(file);
			
			if (lines.length == 0) {
				return "";
			}
			
			// Convert from 1-indexed (metadata) to 0-based (array)
			var start_idx = (start_line - 1).clamp(0, lines.length - 1);
			var end_idx = (end_line - 1).clamp(0, lines.length - 1);
			
			if (start_idx > end_idx) {
				return "";
			}
			
			// Apply max_lines truncation if specified
			if (max_lines != -1 && (end_idx - start_idx + 1) > max_lines) {
				end_idx = start_idx + max_lines - 1;
			}
			
			// Extract lines and join
			return string.joinv("\n", lines[start_idx:end_idx+1]);
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
				
				if (metadata.description != null && metadata.description != "") {
					output.append_printf("Description: %s\n", metadata.description);
				}
				
				// Code citation block (citation format: startLine:endLine:filepath in language tag position)
				// Use our own get_code_snippet method that uses file cache and File.read_async()
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

