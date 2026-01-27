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

namespace OLLMvector.Indexing
{
	
	
	/**
	 * Metadata structure for batch processing.
	 */
	private class ElementMetadata : Object
	{
		public int64 file_id;
		public int start_line;
		public int end_line;
		public string element_type;
		public string element_name;
	}
	/**
	 * Vector building layer for code file processing.
	 * 
	 * Takes Tree from Analysis layer and converts each VectorMetadata
	 * into vector embeddings, storing them in FAISS and metadata in SQL.
	 */
	public class VectorBuilder : Object
	{
		protected OLLMchat.Settings.Config2 config;
		protected OLLMvector.Database database;
		protected SQ.Database sql_db;
		
		/**
		 * Constructor.
		 * 
		 * @param config The Config2 instance containing embed_model usage entry
		 * @param database The vector database for FAISS storage
		 * @param sql_db The SQLite database for metadata storage
		 */
		public VectorBuilder(OLLMchat.Settings.Config2 config, Database database, SQ.Database sql_db)
		{
			this.config = config;
			this.database = database;
			this.sql_db = sql_db;
			
			// Initialize SQL schema if needed
			VectorMetadata.initDB(sql_db);
		}
		
		/**
		 * Processes a Tree and generates vectors for all elements.
		 * 
		 * Implements incremental processing: only creates new embeddings for
		 * changed/new elements, reuses existing vectors for unchanged elements.
		 * 
		 * @param tree The Tree object from Analysis layer
		 */
		public async void process_file(Tree tree) throws GLib.Error
		{
			if (tree.elements.size == 0) {
				GLib.debug("No elements to process in file: %s", tree.file.path);
				return;
			}
			
			// Separate elements into unchanged (reuse vector) and changed/new (create new vector)
			var unchanged_elements = new Gee.ArrayList<VectorMetadata>();
			var changed_elements = new Gee.ArrayList<VectorMetadata>();
			var elements_to_delete = new Gee.HashSet<int>();
			
			// Build set of current element keys (ast_path or fallback) for deletion detection
			var current_keys = new Gee.HashSet<string>();
			foreach (var element in tree.elements) {
				current_keys.add(element.ast_path == "" ? 
					element.element_type + ":" + element.element_name : 
					element.ast_path);
			}
			
			// Check each element
			foreach (var element in tree.elements) {
				var cache_key = element.ast_path == "" ? 
					element.element_type + ":" + element.element_name : 
					element.ast_path;
				
				if (!tree.cached_metadata.has_key(cache_key)) {
					// New element - needs new embedding
					changed_elements.add(element);
					continue;
				}
				
				var cached = tree.cached_metadata.get(cache_key);
				
				// Check if element is unchanged (can reuse existing vector)
				// Element is unchanged if:
				// 1. MD5 hashes match (or both are empty for legacy data that matched by name)
				// 2. Element has vector_id set (from Tree.match_element_with_cache())
				bool is_unchanged = false;
				
				if (element.vector_id > 0 && element.vector_id == cached.vector_id) {
					// Vector ID matches - check MD5
					if (element.md5_hash != "" &&
						cached.md5_hash != "" &&
						element.md5_hash == cached.md5_hash) {
						// MD5 matches - definitely unchanged
						is_unchanged = true;
					} else if (element.md5_hash == "" &&
							cached.md5_hash == "" &&
							element.element_name == cached.element_name &&
							element.element_type == cached.element_type) {
						// Both MD5 empty (legacy) but names match - unchanged (Tree already matched)
						is_unchanged = true;
					}
				}
				
				if (is_unchanged) {
					// Unchanged element - reuse existing vector
					unchanged_elements.add(element);
				} else {
					// Changed element - needs new embedding
					changed_elements.add(element);
					// Mark old metadata for deletion (will be replaced with new entry)
					if (cached.id > 0) {
						elements_to_delete.add((int)cached.id);
					}
				}
			}

			// Delete metadata for elements that no longer exist in file
			foreach (var entry in tree.cached_metadata.entries) {
				if (current_keys.contains(entry.key)) {
					continue;
				}
				
				// Element was deleted from file
				if (entry.value.id > 0) {
					elements_to_delete.add((int)entry.value.id);
				}
			}

			// Delete old metadata entries
			foreach (var id in elements_to_delete) {
				VectorMetadata.query(this.sql_db).deleteId((int64)id);
			}
			
			GLib.debug("VectorBuilder.process_file: %d unchanged (reuse vector), %d changed/new (create vector), %d deleted", 
			           unchanged_elements.size, changed_elements.size, elements_to_delete.size);
			
			// Process unchanged elements (just update metadata if needed)
			foreach (var element in unchanged_elements) {
				var cache_key = element.ast_path == "" ? 
					element.element_type + ":" + element.element_name : 
					element.ast_path;
				
				if (!tree.cached_metadata.has_key(cache_key)) {
					continue;
				}
				
				var cached = tree.cached_metadata.get(cache_key);
				// Check if metadata needs updating (line numbers or MD5 hash)
				bool needs_update = false;
				
				if (cached.start_line != element.start_line || cached.end_line != element.end_line) {
					cached.start_line = element.start_line;
					cached.end_line = element.end_line;
					needs_update = true;
				}
				
				// Update MD5 if it was just calculated (legacy data migration)
				if (element.md5_hash != "" && cached.md5_hash == "") {
					cached.md5_hash = element.md5_hash;
					needs_update = true;
				}
				
				// Update description if it changed (shouldn't happen for unchanged, but be safe)
				if (cached.description != element.description) {
					cached.description = element.description;
					needs_update = true;
				}
				
				if (needs_update) {
					cached.saveToDB(this.sql_db, false);
				}
			}

			// Process changed/new elements (create new embeddings)
			if (changed_elements.size == 0) {
				GLib.debug("No changed elements to vectorize for file: %s", tree.file.path);
				return;
			}
			
			// Format changed elements into documents
			var documents = new Gee.ArrayList<string>();
			
			foreach (var element in changed_elements) {
				documents.add(this.format_element_document(element, tree));
			}
			
			// Get embed model from codebase_search tool config
			if (!this.config.tools.has_key("codebase_search")) {
				throw new GLib.IOError.FAILED("Codebase search tool config not found");
			}
			
			var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
			if (!tool_config.enabled) {
				throw new GLib.IOError.FAILED("Codebase search tool is disabled");
			}
			
			if (tool_config.embed.model == "" || tool_config.embed.connection == "" || 
			    !this.config.connections.has_key(tool_config.embed.connection)) {
				throw new GLib.IOError.FAILED("Invalid embed_model configuration");
			}
			
			// Create client from connection
			var embed_response = yield new OLLMchat.Client(
				this.config.connections.get(tool_config.embed.connection)
			).embed_array(
				tool_config.embed.model, 
				documents,
				-1,
				false,
				tool_config.embed.options
			);
			
			if (embed_response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get embeddings for file");
			}
			
			if (embed_response.embeddings.size != documents.size) {
				throw new GLib.IOError.FAILED(
					"Embedding count mismatch: expected " +
					documents.size.to_string() +
					", got " +
					embed_response.embeddings.size.to_string());
			}
			
			// Convert embeddings to float arrays and store in FAISS
			var vector_batch = OLLMvector.FloatArray(this.database.dimension);
			
			// Get current vector count to determine starting vector_id
			int64 start_vector_id = (int64)this.database.vector_count;
			
			foreach (var embedding in embed_response.embeddings) {
				vector_batch.add(this.embed_to_floats(embedding));
			}
			
			// Add vectors to FAISS index
			this.database.add_vectors_batch(vector_batch);
			
			// Store metadata in SQL database for changed elements
			for (int j = 0; j < changed_elements.size; j++) {
				var element = changed_elements.get(j);
				element.vector_id = start_vector_id + j;
				element.saveToDB(this.sql_db, false);
			}
			
			GLib.debug("Completed processing %d changed elements from file: %s", changed_elements.size, tree.file.path);
		}
		
		/**
		 * Formats a VectorMetadata into a document string for vectorization.
		 * 
		 * Format follows the specification in the plan document:
		 * - type, name, file, lines, description, signature, code snippet
		 * 
		 * @param element The VectorMetadata to format
		 * @param tree The Tree object containing the element and file information
		 * @return Formatted document string
		 */
		private string format_element_document(VectorMetadata element, Tree tree)
		{
			var doc = new GLib.StringBuilder();
			
			// Element type and name
			doc.append_printf("%s: %s\n", element.element_type, element.element_name);
			
			// Namespace
			if (element.namespace != null && element.namespace != "") {
				doc.append_printf("Namespace: %s\n", element.namespace);
			}
			
			// Parent class/struct/interface
			if (element.parent_class != null && element.parent_class != "") {
				doc.append_printf("Class: %s\n", element.parent_class);
			}
			
			// File location and line range (merged)
			doc.append_printf("File: %s\nLines: %d-%d\n", tree.file.path, element.start_line, element.end_line);
			
			// Signature
			if (element.signature != null && element.signature != "") {
				doc.append_printf("Signature: %s\n", element.signature);
			}
			
			// Description
			if (element.description != null && element.description != "") {
				doc.append_printf("Description: %s\n", element.description);
			}
			
			// Code snippet - skip for classes and namespaces (only use signature)
			if (element.element_type != "class" && element.element_type != "namespace") {
				doc.append("Code:\n");
				var code_snippet = this.get_code_snippet(element, tree);
				doc.append(code_snippet);
			}
			
			return doc.str;
		}
		
		/**
		 * Gets a code snippet as a string using Tree.lines_to_string().
		 * 
		 * Uses the Tree object's lines_to_string method to extract code snippets
		 * from the file content.
		 * 
		 * @param element The VectorMetadata element
		 * @param tree The Tree object with lines_to_string method
		 * @return Code snippet as string
		 */
		private string get_code_snippet(VectorMetadata element, Tree tree)
		{
			var code_snippet = tree.lines_to_string(element.start_line, element.end_line);
			
			if (code_snippet == null || code_snippet == "") {
				return "";
			}
			
			return code_snippet;
		}
		
		/**
		 * Converts embedding from ArrayList<double?> to float[].
		 */
		protected float[] embed_to_floats(Gee.ArrayList<double?> embed) throws GLib.Error
		{
			var float_array = new float[embed.size];
			for (int i = 0; i < embed.size; i++) {
				if (embed[i] == null) {
					throw new GLib.IOError.FAILED("Null value in embed vector");
				}
				float_array[i] = (float)embed[i];
			}
			return float_array;
		}
		
		
		
	}
}
