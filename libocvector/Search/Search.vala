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

namespace OLLMvector.Search
{
	/**
	 * Executes vector search operations.
	 * 
	 * Performs semantic codebase search using FAISS vector similarity
	 * and returns formatted search results with code snippets. Converts
	 * search queries to vector embeddings, performs similarity search,
	 * and retrieves code snippets from source files using the buffer
	 * system.
	 * 
	 * Supports filtering by vector IDs (from SQL queries) and element
	 * type. Results include metadata and code snippets extracted from
	 * the source files.
	 * 
	 * == Usage Example ==
	 * 
	 * {{{
	 * // Create search instance (optional via initializer)
	 * var search = new OLLMvector.Search.Search(
	 *     vector_db,
	 *     sql_db,
	 *     config,
	 *     active_project,
	 *     "find authentication logic",
	 *     filtered_vector_ids
	 * ) {
	 *     max_results = 20,
	 *     element_type_filter = "method",
	 *     category_filter = "documentation"
	 * };
	 * var results = yield search.execute();
	 * }}}
	 */
	public class Search : VectorBase
	{
		/**
		 * Vector database for FAISS search.
		 */
		private OLLMvector.Database vector_db;
		
		/**
		 * SQL database for metadata and filtering.
		 */
		private SQ.Database sql_db;
		
		/**
		 * Project folder for file operations.
		 */
		private OLLMfiles.Folder folder;
		
		/**
		 * Search query text.
		 */
		private string query;
		
		/**
		 * Maximum number of results to return.
		 * Set via object initializer, e.g. { max_results = 20 }. Default 10.
		 */
		public uint64 max_results { get; set; default = 10; }
		
		/**
		 * Filtered vector IDs (from SQL filter query).
		 * Empty list means search all vectors.
		 */
		private Gee.ArrayList<int> filtered_vector_ids;
		
		/**
		 * Optional element_type filter for metadata results.
		 * Set via object initializer, e.g. { element_type_filter = "method" }.
		 * Empty string means no filtering.
		 */
		public string element_type_filter { get; set; default = ""; }
		
		/**
		 * Optional category filter for documentation metadata.
		 * Set via object initializer, e.g. { category_filter = "documentation" }.
		 * Valid values: plan, documentation, rule, configuration, data, license, changelog, other.
		 * Empty string means no filtering.
		 */
		public string category_filter { get; set; default = ""; }
		
		/**
		 * Constructor with required dependencies.
		 * Optional: max_results, element_type_filter, category_filter via object initializer, e.g.
		 * {{{
		 * var search = new OLLMvector.Search.Search(..., filtered_vector_ids) {
		 *     max_results = 20,
		 *     element_type_filter = "method",
		 *     category_filter = "documentation"
		 * };
		 * }}}
		 */
		public Search(
			OLLMvector.Database vector_db,
			SQ.Database sql_db,
			OLLMchat.Settings.Config2 config,
			OLLMfiles.Folder folder,
			string query,
			Gee.ArrayList<int> filtered_vector_ids
		)
		{
			base(config);
			this.vector_db = vector_db;
			this.sql_db = sql_db;
			this.folder = folder;
			this.query = query;
			this.filtered_vector_ids = filtered_vector_ids;
		}
		
		/**
		 * Normalize query text (basic preprocessing).
		 * 
		 * @param query_text Input query text
		 * @return Normalized query text
		 */
		private string normalize_query(string query_text)
		{
			// Trim whitespace
			var normalized = query_text.strip();
			
			// Basic normalization: remove extra whitespace
			normalized = normalized.replace("\n", " ").replace("\t", " ");
			while (normalized.contains("  ")) {
				normalized = normalized.replace("  ", " ");
			}
			
			return normalized.strip();
		}
		
		/**
		 * Convert embedding response to float array.
		 * 
		 * @param embed Embedding response
		 * @return Float array representation
		 */
		private float[] embed_to_floats(Gee.ArrayList<double?> embed) throws GLib.Error
		{
			var float_array = new float[embed.size];
			for (int i = 0; i < embed.size; i++) {
				var val = embed[i];
				if (val == null) {
					throw new GLib.IOError.FAILED("Null value in embed vector");
				}
				float_array[i] = (float)val;
			}
			return float_array;
		}
		
		/**
		 * Execute the search operation.
		 * 
		 * @return ArrayList of SearchResult objects
		 */
		public async Gee.ArrayList<SearchResult> execute() throws GLib.Error
		{
			// Log backend being used (CPU-only for now)
			GLib.debug("Using CPU backend for FAISS search");
			
			if (this.filtered_vector_ids.size == 0) {
				return new Gee.ArrayList<SearchResult>();
			}
			
			// Step 1: Query preprocessing (basic normalization)
			var normalized_query = this.normalize_query(this.query);
			if (normalized_query == "") {
				return new Gee.ArrayList<SearchResult>();
			}
			
			// Step 2: Query vectorization (convert text to embeddings)
			GLib.debug("Vectorizing query: %s", normalized_query);
			
			// Get embedding connection using base class method
			var connection = yield this.connection("embed");
			
			// Get model from tool config (already validated above)
			var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
			
			var client = new OLLMchat.Client(connection);
			var embed_response = yield client.embed(tool_config.embed.model, normalized_query);
			if (embed_response == null || embed_response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get query embedding");
			}
			
			var query_vector = this.embed_to_floats(embed_response.embeddings[0]);
			
			// Step 3: Create IDSelector for filtering
			var id_array = new int64[this.filtered_vector_ids.size];
			for (int i = 0; i < this.filtered_vector_ids.size; i++) {
				id_array[i] = this.filtered_vector_ids[i];
			}
			
			// Debug: Log filtered vector IDs being passed to FAISS
			var first_ids_str = "";
			if (this.filtered_vector_ids.size > 0) {
				var first_ids = new string[this.filtered_vector_ids.size > 10 ? 10 : this.filtered_vector_ids.size];
				for (int i = 0; i < first_ids.length; i++) {
					first_ids[i] = this.filtered_vector_ids[i].to_string();
				}
				first_ids_str = string.joinv(",", first_ids);
			} else {
				first_ids_str = "none";
			}
			GLib.debug("Search.execute: Creating IDSelector with %d filtered_vector_ids (first 10: %s)",
				this.filtered_vector_ids.size,
				first_ids_str
			);
			
			// Create a set for quick lookup to verify results
			var filtered_set = new Gee.HashSet<int>();
			foreach (var vid in this.filtered_vector_ids) {
				filtered_set.add(vid);
			}
			
			Faiss.IDSelector? selector = null;
			if (Faiss.id_selector_batch_new(out selector, (int64)this.filtered_vector_ids.size, id_array) != 0) {
				throw new GLib.IOError.FAILED("Failed to create IDSelector for filtering");
			}
			
			// Step 4: Perform FAISS similarity search with native filtering
			// Access internal index property (same library, so accessible)
			if (this.vector_db.index == null) {
				throw new GLib.IOError.FAILED("Vector database index is not initialized");
			}
			
			var faiss_results = this.vector_db.index.search(query_vector, this.max_results, selector);
			
			if (faiss_results.length == 0) {
				return new Gee.ArrayList<SearchResult>();
			}
			
			// Step 5: Filter valid vector IDs from FAISS results
			// FAISS returns -1 as a sentinel value when it can't find enough results
			// We need to filter out -1 values and IDs not in the filtered set
			var valid_vector_ids = new Gee.ArrayList<int>();
			
			for (int i = 0; i < faiss_results.length; i++) {
				var vector_id = faiss_results[i].document_id;
				
				// Skip -1 sentinel values (invalid results from FAISS)
				if (vector_id == -1) {
					continue;
				}
				
				// If filtering is active, verify document_id is in filtered set
				if (this.filtered_vector_ids.size > 0 && !filtered_set.contains((int)vector_id)) {
					continue;
				}
				
				// This is a valid vector ID
				valid_vector_ids.add((int)vector_id);
			}
			
			// If no valid results, return empty list
			if (valid_vector_ids.size == 0) {
				return new Gee.ArrayList<SearchResult>();
			}
			
			// Step 6: Lookup metadata for valid vector_ids only
			var result_vector_ids = new int64[valid_vector_ids.size];
			for (int i = 0; i < valid_vector_ids.size; i++) {
				result_vector_ids[i] = (int64)valid_vector_ids[i];
			}
			
			var metadata_list = OLLMvector.VectorMetadata.lookup_vectors(
					this.sql_db, result_vector_ids);
			
			// No post-filtering needed: filtered_vector_ids was built from SQL with element_type/category
			// so FAISS only searched that set and returned metadata already matches the filters.
			
			// Create a map of vector_id -> metadata for quick lookup
			var metadata_map = new Gee.HashMap<int, OLLMvector.VectorMetadata>();
			foreach (var metadata in metadata_list) {
				metadata_map.set((int)metadata.vector_id, metadata);
			}
			
			// Step 7: Create SearchResult ArrayList
			var search_results = new Gee.ArrayList<SearchResult>();
			foreach (var faiss_result in faiss_results) {
				var metadata = metadata_map.get((int)faiss_result.document_id);
				if (metadata == null) {
					// Skip results without metadata
					continue;
				}
				
				var search_result = new SearchResult(
					this.sql_db,
					this.folder,
					faiss_result.document_id,
					faiss_result.distance,
					metadata
				);
				search_results.add(search_result);
			}
			
			return search_results;
		}
	}
}

