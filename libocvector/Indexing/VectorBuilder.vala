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
		private OLLMchat.Settings.Config2 config;
		private OLLMvector.Database database;
		private SQ.Database sql_db;
		
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
		 * Removes existing metadata for the file before indexing to ensure
		 * clean re-indexing without orphaned data.
		 * 
		 * @param tree The Tree object from Analysis layer
		 */
		public async void process_file(Tree tree) throws GLib.Error
		{
			// Remove existing metadata for this file before re-indexing
			this.sql_db.exec("DELETE FROM vector_metadata WHERE file_id = " + tree.file.id.to_string());
			
			if (tree.elements.size == 0) {
				GLib.debug("No elements to process in file: %s", tree.file.path);
				return;
			}
			
			// Format all elements into documents
			var documents = new Gee.ArrayList<string>();
			var element_metadata = new Gee.ArrayList<ElementMetadata>();
			
			foreach (var element in tree.elements) {
				var document = this.format_element_document(
					element, tree);
				documents.add(document);
				
				element_metadata.add(new ElementMetadata() {
					file_id = tree.file.id,
					start_line = element.start_line,
					end_line = element.end_line,
					element_type = element.element_type,
					element_name = element.element_name
				});
			}
			
			// Debug: output documents being sent to embedder
			GLib.debug("Sending %d documents to embedder for file: %s", documents.size, tree.file.path);
			for (int i = 0; i < documents.size; i++) {
				GLib.debug("Document %d for embedding:\n%s", i + 1, documents[i]);
			}
			
			// Return early if embed_model is not configured or invalid
			if (!this.config.usage.has_key("embed_model")) {
				throw new GLib.IOError.FAILED("No embed_model configured for embeddings");
			}
			
			var embed_model_usage = this.config.usage.get("embed_model") as OLLMchat.Settings.ModelUsage;
			var model = embed_model_usage.model;
			
			if (model == "" || embed_model_usage.connection == "" || !this.config.connections.has_key(embed_model_usage.connection)) {
				throw new GLib.IOError.FAILED("Invalid embed_model configuration");
			}
			
			var connection = this.config.connections.get(embed_model_usage.connection);
			
			// Create client from connection (no config - Manager owns config)
			var client = new OLLMchat.Client(connection);
			// Pass model and options from embed_model usage entry
			var embed_response = yield client.embed_array(
				model, 
				documents,
				-1,  // dimensions (default)
				false,  // truncate (default)
				embed_model_usage.options  // Use options from embed_model usage entry
			);
			if (embed_response == null || embed_response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get embeddings for file");
			}
			
			if (embed_response.embeddings.size != documents.size) {
				throw new GLib.IOError.FAILED(
					"Embedding count mismatch: expected " +
					documents.size.to_string() +
					", got " +
					embed_response.embeddings.size.to_string());
			}
			
			// Index will be auto-initialized in add_vectors_batch with the correct dimension
			
			// Convert embeddings to float arrays and store in FAISS
			var vector_batch = OLLMvector.FloatArray(this.database.dimension);
			
			// Get current vector count to determine starting vector_id
			int64 start_vector_id = (int64)this.database.vector_count;
			
			foreach (var embedding in embed_response.embeddings) {
				vector_batch.add(this.embed_to_floats(embedding));
			}
			
			// Add vectors to FAISS index
			this.database.add_vectors_batch(vector_batch);
			
			// Store metadata in SQL database
			for (int j = 0; j < element_metadata.size; j++) {
				var metadata = element_metadata[j];
				var element = tree.elements[j];
				
				var vector_id = start_vector_id + j;
				new VectorMetadata() {
					vector_id = vector_id,
					file_id = metadata.file_id,
					start_line = metadata.start_line,
					end_line = metadata.end_line,
					element_type = metadata.element_type,
					element_name = metadata.element_name,
					description = element.description
				}.saveToDB(this.sql_db, false);
			}
			
			GLib.debug("Completed processing %d elements from file: %s", documents.size, tree.file.path);
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
				var code_snippet = this.get_truncated_code_snippet(element, tree);
				doc.append(code_snippet);
			}
			
			return doc.str;
		}
		
		/**
		 * Gets a truncated code snippet as a string using Tree.lines_to_string().
		 * 
		 * Uses the Tree object's lines_to_string method to extract code snippets
		 * from the file content. Applies simple length-based truncation if needed
		 * to prevent extremely large snippets.
		 * 
		 * @param element The VectorMetadata element
		 * @param tree The Tree object with lines_to_string method
		 * @return Code snippet as string
		 */
		private string get_truncated_code_snippet(VectorMetadata element, Tree tree)
		{
			var code_snippet = tree.lines_to_string(element.start_line, element.end_line);
			
			if (code_snippet == null || code_snippet == "") {
				return "";
			}
			
			// Simple truncation if snippet is extremely large (max 200 lines)
			var lines = code_snippet.split("\n");
			const int MAX_LINES = 200;
			if (lines.length > MAX_LINES) {
				return string.joinv("\n", lines[0:MAX_LINES]) 
					+ "\n// ... (truncated)";
			}
			
			return code_snippet;
		}
		
		/**
		 * Converts embedding from ArrayList<double?> to float[].
		 */
		private float[] embed_to_floats(Gee.ArrayList<double?> embed) throws GLib.Error
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
