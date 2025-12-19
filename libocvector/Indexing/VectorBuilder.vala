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
	 * Takes CodeFile from Analysis layer and converts each CodeElement
	 * into vector embeddings, storing them in FAISS and metadata in SQL.
	 */
	public class VectorBuilder : Object
	{
		private OLLMchat.Client client;
		private OLLMvector.Database database;
		private SQ.Database sql_db;
		
		/**
		 * Constructor.
		 * 
		 * @param client The OLLMchat client for embeddings API
		 * @param database The vector database for FAISS storage
		 * @param sql_db The SQLite database for metadata storage
		 */
		public VectorBuilder(OLLMchat.Client client, Database database, SQ.Database sql_db)
		{
			this.client = client;
			this.database = database;
			this.sql_db = sql_db;
			
			// Initialize SQL schema if needed
			VectorMetadata.initDB(sql_db);
		}
		
		/**
		 * Processes a CodeFile and generates vectors for all elements.
		 * 
		 * @param code_file The CodeFile from Analysis layer
		 * @param file The OLLMfiles.File object (for file_id)
		 */
		public async void process_file(OLLMvector.CodeFile code_file, OLLMfiles.File file) throws GLib.Error
		{
			if (code_file.elements.size == 0) {
				GLib.debug("No elements to process in file: %s", file.path);
				return;
			}
			
			// Format all elements into documents
			var documents = new Gee.ArrayList<string>();
			var element_metadata = new Gee.ArrayList<ElementMetadata>();
			
			foreach (var element in code_file.elements) {
				documents.add(this.format_element_document(
					element, code_file, file.path));
				
				element_metadata.add(new ElementMetadata() {
					file_id = file.id,
					start_line = element.start_line,
					end_line = element.end_line,
					element_type = element.property_type,
					element_name = element.name
				});
			}
			
			// Generate embeddings for all elements in the file at once
			var embed_response = yield this.client.embed_array(documents);
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
			
			// Initialize database index from first embedding if needed
			if (this.database.dimension == 0) {
				this.database.init_index((uint64)embed_response.embeddings[0].size);
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
			
			// Store metadata in SQL database
			for (int j = 0; j < element_metadata.size; j++) {
				var metadata = element_metadata[j];
				
				new VectorMetadata() {
					vector_id = start_vector_id + j,
					file_id = metadata.file_id,
					start_line = metadata.start_line,
					end_line = metadata.end_line,
					element_type = metadata.element_type,
					element_name = metadata.element_name
				}.saveToDB(this.sql_db, false);
			}
			
			GLib.debug("Completed processing %d elements from file: %s", documents.size, file.path);
		}
		
		/**
		 * Formats a CodeElement into a document string for vectorization.
		 * 
		 * Format follows the specification in the plan document:
		 * - type, name, file, lines, description, parameters, return type, dependencies, code snippet
		 * 
		 * @param element The CodeElement to format
		 * @param code_file The CodeFile containing the element
		 * @param file_path The file path (from OLLMfiles.File)
		 * @return Formatted document string
		 */
		private string format_element_document(OLLMvector.CodeElement element, 
			OLLMvector.CodeFile code_file, string file_path)
		{
			var doc = new GLib.StringBuilder();
			
			// Element type and name
			doc.append_printf("%s: %s\n", element.property_type, element.name);
			
			// Access modifier
			if (element.access_modifier != null && element.access_modifier != "") {
				doc.append_printf("Access: %s\n", element.access_modifier);
			}
			
			// File location and line range (merged)
			doc.append_printf("File: %s\nLines: %d-%d\n", file_path, element.start_line, element.end_line);
			
			// Signature
			if (element.signature != null && element.signature != "") {
				doc.append_printf("Signature: %s\n", element.signature);
			}
			
			// Description
			if (element.description != null && element.description != "") {
				doc.append_printf("Description: %s\n", element.description);
			}
			
			// Parameters (for functions/methods/constructors)
			if (element.parameters.size > 0) {
				var param_parts = new Gee.ArrayList<string>();
				foreach (var param in element.parameters) {
					param_parts.add("%s: %s".printf(param.name, param.argument_type));
				}
				doc.append_printf("Parameters: %s\n", string.joinv(", ", param_parts.to_array()));
			}
			
			// Return type (for functions/methods)
			if (element.return_type != null && element.return_type != "" && element.return_type != "void") {
				doc.append_printf("Returns: %s\n", element.return_type);
			}
			
			// Properties (for classes/structs/interfaces)
			if (element.properties.size > 0) {
				var prop_parts = new Gee.ArrayList<string>();
				foreach (var prop in element.properties) {
					prop_parts.add("%s: %s [%s]".printf(
						prop.name,
						prop.value_type,
						string.joinv(", ", prop.accessors.to_array())));
				}
				doc.append_printf("Properties: %s\n", string.joinv(", ", prop_parts.to_array()));
			}
			
			// Dependencies
			if (element.dependencies.size > 0) {
				var dep_parts = new Gee.ArrayList<string>();
				foreach (var dep in element.dependencies) {
					dep_parts.add("%s: %s".printf(dep.relationship_type, dep.target));
				}
				doc.append_printf("Dependencies: %s\n", string.joinv(", ", dep_parts.to_array()));
			}
			
			// Code snippet (with smart truncation)
			doc.append("Code:\n");
			var code_snippet = this.get_truncated_code_snippet(element);
			doc.append(code_snippet);
			
			return doc.str;
		}
		
		/**
		 * Gets a truncated code snippet as a string.
		 * 
		 * Trusts LLM analysis - uses the code snippet lines as provided.
		 * Only applies simple length-based truncation if needed to prevent
		 * extremely large snippets.
		 * 
		 * @param element The CodeElement
		 * @return Code snippet as joined string
		 */
		private string get_truncated_code_snippet(OLLMvector.CodeElement element)
		{
			if (element.code_snippet_lines == null || element.code_snippet_lines.length == 0) {
				return "";
			}
			
			// Simple truncation if snippet is extremely large (max 200 lines)
			// Trust LLM to provide appropriate snippets for each element type
			const int MAX_LINES = 200;
			if (element.code_snippet_lines.length > MAX_LINES) {
				return string.joinv("\n", element.code_snippet_lines[0:MAX_LINES]) 
					+ "\n// ... (truncated)";
			}
			
			return string.joinv("\n", element.code_snippet_lines);
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
