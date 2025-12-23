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

namespace OLLMvector.Search
{
	/**
	 * Executes vector search operations.
	 * 
	 * Performs semantic codebase search using FAISS vector similarity
	 * and returns formatted search results with code snippets.
	 */
	public class Search : Object
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
		 * Embedding client for query vectorization.
		 */
		private OLLMchat.Client embedding_client;
		
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
		 */
		private uint64 max_results;
		
		/**
		 * Filtered vector IDs (from SQL filter query).
		 * Empty set means search all vectors.
		 */
		private Gee.HashSet<int64?> filtered_vector_ids;
		
		/**
		 * Constructor with all required dependencies.
		 * 
		 * @param vector_db Vector database for FAISS search
		 * @param sql_db SQL database for metadata and filtering
		 * @param embedding_client Embedding client for query vectorization
		 * @param folder Project folder for file operations
		 * @param query Search query text
		 * @param max_results Maximum number of results (default: 10)
		 * @param filtered_vector_ids Set of vector IDs to filter search (empty set = search all)
		 */
		public Search(
			OLLMvector.Database vector_db,
			SQ.Database sql_db,
			OLLMchat.Client embedding_client,
			OLLMfiles.Folder folder,
			string query,
			uint64 max_results = 10,
			Gee.HashSet<int64?> filtered_vector_ids
		)
		{
			this.vector_db = vector_db;
			this.sql_db = sql_db;
			this.embedding_client = embedding_client;
			this.folder = folder;
			this.query = query;
			this.max_results = max_results;
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
			
			// Step 1: Query preprocessing (basic normalization)
			var normalized_query = this.normalize_query(this.query);
			if (normalized_query == "") {
				return new Gee.ArrayList<SearchResult>();
			}
			
			// Step 2: Query vectorization (convert text to embeddings)
			GLib.debug("Vectorizing query: %s", normalized_query);
			var embed_response = yield this.embedding_client.embed(normalized_query);
			if (embed_response == null || embed_response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get query embedding");
			}
			
			var query_vector = this.embed_to_floats(embed_response.embeddings[0]);
			
			// Step 3: Create IDSelector if filtering is needed
			Faiss.IDSelector? selector = null;
			if (this.filtered_vector_ids.size > 0) {
				// Convert HashSet to array for IDSelector
				var id_list = new Gee.ArrayList<int64>();
				foreach (var id in this.filtered_vector_ids) {
					if (id != null) {
						id_list.add(id);
					}
				}
				
				if (id_list.size > 0) {
					var id_array = new int64[id_list.size];
					for (int i = 0; i < id_list.size; i++) {
						id_array[i] = id_list[i];
					}
					
					if (Faiss.id_selector_batch_new(out selector, (int64)id_list.size, id_array) != 0) {
						throw new GLib.IOError.FAILED("Failed to create IDSelector for filtering");
					}
				}
			}
			
			// Step 4: Perform FAISS similarity search with native filtering
			// Access internal index property (same library, so accessible)
			if (this.vector_db.index == null) {
				if (selector != null) {
					selector.free();
				}
				throw new GLib.IOError.FAILED("Vector database index is not initialized");
			}
			
			var faiss_results = this.vector_db.index.search(query_vector, this.max_results, selector);
			
			// Free selector if we created it
			if (selector != null) {
				selector.free();
			}
			
			if (faiss_results.length == 0) {
				return new Gee.ArrayList<SearchResult>();
			}
			
			// Step 5: Extract vector IDs from results
			var result_vector_ids = new int64[faiss_results.length];
			for (int i = 0; i < faiss_results.length; i++) {
				result_vector_ids[i] = faiss_results[i].document_id;
			}
			
			// Step 6: Lookup metadata for result vector_ids
			var metadata_list = OLLMvector.VectorMetadata.lookup_vectors(
					this.sql_db, result_vector_ids);
			
			// Create a map of vector_id -> metadata for quick lookup
			var metadata_map = new Gee.HashMap<int64, OLLMvector.VectorMetadata>();
			foreach (var metadata in metadata_list) {
				metadata_map.set(metadata.vector_id, metadata);
			}
			
			// Step 7: Create SearchResult ArrayList
			var search_results = new Gee.ArrayList<SearchResult>();
			foreach (var faiss_result in faiss_results) {
				var metadata = metadata_map.get(faiss_result.document_id);
				if (metadata == null) {
					// Skip results without metadata
					continue;
				}
				
				var search_result = new SearchResult(
					this.sql_db,
					this.folder,
					faiss_result.document_id,
					faiss_result.similarity_score,
					metadata
				);
				search_results.add(search_result);
			}
			
			return search_results;
		}
	}
}

