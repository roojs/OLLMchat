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
		 * Optional AST path to inspect in debug output.
		 *
		 * When set, search emits one targeted debug line showing whether
		 * the AST path made it into the filtered set, the raw FAISS hits,
		 * and the final formatted results.
		 */
		public string debug_ast_path { get; set; default = ""; }
		
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
		 * Resolve the configured debug AST path to one vector_id within the
		 * current folder scope.
		 *
		 * @return Matching vector_id, or -1 when not found
		 */
		private int64 lookup_debug_vector_id()
		{
			if (this.debug_ast_path == "") {
				return -1;
			}
			
			var file_ids = this.folder.project_files.get_ids("");
			if (file_ids.size == 0) {
				return -1;
			}
			
			var rows = new Gee.ArrayList<OLLMfiles.SQT.VectorMetadata>();
			OLLMfiles.SQT.VectorMetadata.query(this.sql_db).select(
				"WHERE file_id IN (" + string.joinv(",", file_ids.to_array()) +
					") AND ast_path = '" +
					this.debug_ast_path.replace("'", "''") +
					"' ORDER BY id DESC LIMIT 1",
				rows
			);
			if (rows.size == 0) {
				return -1;
			}
			
			return rows.get(0).vector_id;
		}
		
		/**
		 * Emit one focused debug line for a watched AST path.
		 *
		 * @param normalized_query Normalized query text
		 * @param faiss_results Raw FAISS results before metadata filtering
		 * @param filtered_set Allowed vector IDs after SQL filtering
		 * @param metadata_map Metadata keyed by vector_id
		 * @param search_results Final formatted search results
		 */
		private void debug_target(
			string normalized_query,
			OLLMvector.SearchResult[] faiss_results,
			Gee.HashSet<int> filtered_set,
			Gee.HashMap<int, OLLMfiles.SQT.VectorMetadata> metadata_map,
			Gee.ArrayList<SearchResult> search_results
		)
		{
			if (this.debug_ast_path == "") {
				return;
			}
			
			var target_vector_id = this.lookup_debug_vector_id();
			var target_in_filtered = target_vector_id != -1 &&
				filtered_set.contains((int)target_vector_id);
			var target_in_raw = false;
			var target_in_final = false;
			var target_distance = "";
			
			for (int i = 0; i < faiss_results.length; i++) {
				if (faiss_results[i].document_id != target_vector_id) {
					continue;
				}
				target_in_raw = true;
				target_distance = "%.4f".printf(faiss_results[i].distance);
				break;
			}
			
			foreach (var result in search_results) {
				if (result.vector_id != target_vector_id) {
					continue;
				}
				target_in_final = true;
				if (target_distance == "") {
					target_distance = "%.4f".printf(result.distance);
				}
				break;
			}
			
			var top1_id = faiss_results.length > 0 ?
				faiss_results[0].document_id.to_string() : "";
			var top1_distance = faiss_results.length > 0 ?
				"%.4f".printf(faiss_results[0].distance) : "";
			var top1_ast = faiss_results.length > 0 &&
				metadata_map.has_key((int)faiss_results[0].document_id) ?
				metadata_map.get((int)faiss_results[0].document_id).ast_path : "";
			var top2_id = faiss_results.length > 1 ?
				faiss_results[1].document_id.to_string() : "";
			var top2_distance = faiss_results.length > 1 ?
				"%.4f".printf(faiss_results[1].distance) : "";
			var top2_ast = faiss_results.length > 1 &&
				metadata_map.has_key((int)faiss_results[1].document_id) ?
				metadata_map.get((int)faiss_results[1].document_id).ast_path : "";
			var top3_id = faiss_results.length > 2 ?
				faiss_results[2].document_id.to_string() : "";
			var top3_distance = faiss_results.length > 2 ?
				"%.4f".printf(faiss_results[2].distance) : "";
			var top3_ast = faiss_results.length > 2 &&
				metadata_map.has_key((int)faiss_results[2].document_id) ?
				metadata_map.get((int)faiss_results[2].document_id).ast_path : "";
			
			GLib.debug(
				"query='%s' target='%s' vector_id=%s filtered=%s raw=%s final=%s distance=%s top1=%s:%s:%s top2=%s:%s:%s top3=%s:%s:%s",
				normalized_query,
				this.debug_ast_path,
				target_vector_id.to_string(),
				target_in_filtered.to_string(),
				target_in_raw.to_string(),
				target_in_final.to_string(),
				target_distance,
				top1_id,
				top1_distance,
				top1_ast,
				top2_id,
				top2_distance,
				top2_ast,
				top3_id,
				top3_distance,
				top3_ast
			);
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
			
			var connection = yield this.connection("embed", true);
			var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
			var model_name = yield tool_config.embed.model_obj.customize(
				connection, tool_config.embed.options);

			var call = new OLLMchat.Call.Embeddings(connection, model_name) {
				input = { normalized_query },
				dimensions = -1
			};
			var embed_response = yield call.exec_embedding();

			if (embed_response.embeddings.rows == 0) {
				throw new GLib.IOError.FAILED("Failed to get query embedding");
			}
			var query_vector = embed_response.embeddings.get_vector(0);
			
			/*
			 * Old path — id_array for IDSelector (rollback: docs/bugs/2026-04-19-vector search results.md).
			 * Debug line was GLib.debug("...Creating IDSelector with...", size, first_ids_str) using same first_ids_str as below.
			 *
			 * var id_array = new int64[this.filtered_vector_ids.size];
			 * for (int i = 0; i < this.filtered_vector_ids.size; i++) {
			 *     id_array[i] = this.filtered_vector_ids[i];
			 * }
			 */
			
			// Step 3: Debug — filtered id count (tmp in-memory copy + search replaces IDSelector filtering)
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
			GLib.debug(
				"Search.execute: tmp index copy search with %d filtered_vector_ids (first 10: %s)",
				this.filtered_vector_ids.size,
				first_ids_str
			);
			
			// Create a set for quick lookup to verify results and debug_target
			var filtered_set = new Gee.HashSet<int>();
			foreach (var vid in this.filtered_vector_ids) {
				filtered_set.add(vid);
			}
			
			if (this.debug_ast_path != "") {
				var target_vector_id = this.lookup_debug_vector_id();
				var in_filtered = target_vector_id >= 0 && filtered_set.contains((int)target_vector_id);
				GLib.debug(
					"Search.execute: debug_ast_path '%s' -> vector_id %s, in filtered list: %s",
					this.debug_ast_path,
					target_vector_id.to_string(),
					in_filtered.to_string()
				);
			}
			
			/*
			 * Old path — IDSelector + search on main index (same filtered_set / debug_ast / null check as here).
			 *
			 * Faiss.IDSelector? selector = null;
			 * if (Faiss.id_selector_batch_new(out selector, (int64)this.filtered_vector_ids.size, id_array) != 0) {
			 *     throw new GLib.IOError.FAILED("Failed to create IDSelector for filtering");
			 * }
			 * var faiss_results = this.vector_db.index.search(query_vector, this.max_results, selector);
			 */
			
			// Step 4: Copy filtered vectors into a tmp FAISS index and search (avoids IDSelector bugs)
			if (this.vector_db.index == null) {
				throw new GLib.IOError.FAILED("Vector database index is not initialized");
			}
			
			var copy = new OLLMvector.Index.create_tmp_hnsw(this.vector_db.index.dimension);
			uint64 copied = copy.copy_from(this.vector_db.index, this.filtered_vector_ids);
			if (copied == 0) {
				return new Gee.ArrayList<SearchResult>();
			}
			
			uint64 k = this.max_results;
			if (k > copied) {
				k = copied;
			}
			
			var faiss_results = copy.search(query_vector, k, null);
			
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
			
			var metadata_list = OLLMfiles.SQT.VectorMetadata.lookup_vectors(
					this.sql_db, result_vector_ids);
			
			// No post-filtering needed: filtered_vector_ids was built from SQL with element_type/category
			// so FAISS only searched that set and returned metadata already matches the filters.
			
			// Create a map of vector_id -> metadata for quick lookup
			var metadata_map = new Gee.HashMap<int, OLLMfiles.SQT.VectorMetadata>();
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
			
			this.debug_target(
				normalized_query,
				faiss_results,
				filtered_set,
				metadata_map,
				search_results
			);
			
			return search_results;
		}
	}
}

