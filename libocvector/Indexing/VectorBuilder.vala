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
		private const int BATCH_SIZE = 15; // Process 10-20 documents per batch
		
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
			this.ensure_schema();
		}
		
		/**
		 * Ensures the vector_metadata table exists in the SQL database.
		 */
		private void ensure_schema()
		{
			var create_table = """
				CREATE TABLE IF NOT EXISTS vector_metadata (
					vector_id INTEGER PRIMARY KEY,
					file_id INTEGER NOT NULL,
					start_line INTEGER NOT NULL,
					end_line INTEGER NOT NULL,
					element_type TEXT NOT NULL,
					element_name TEXT NOT NULL,
					FOREIGN KEY (file_id) REFERENCES files(id)
				);
			""";
			
			this.sql_db.exec(create_table);
			
			// Create indexes for efficient lookups
			this.sql_db.exec("CREATE INDEX IF NOT EXISTS idx_vector_metadata_file_id ON vector_metadata(file_id);");
			this.sql_db.exec("CREATE INDEX IF NOT EXISTS idx_vector_metadata_vector_id ON vector_metadata(vector_id);");
		}
		
		/**
		 * Processes a CodeFile and generates vectors for all elements.
		 * 
		 * @param code_file The CodeFile from Analysis layer
		 * @param file The OLLMfiles.File object (for file_id)
		 */
		public async void process_file(CodeFile code_file, OLLMfiles.File file) throws GLib.Error
		{
			if (code_file.elements.size == 0) {
				GLib.debug("No elements to process in file: %s", code_file.file_path);
				return;
			}
			
			// Format all elements into documents
			var documents = new Gee.ArrayList<string>();
			var element_metadata = new Gee.ArrayList<ElementMetadata>();
			
			foreach (var element in code_file.elements) {
				var document = this.format_element_document(element, code_file);
				documents.add(document);
				
				element_metadata.add(ElementMetadata() {
					file_id = file.id,
					start_line = element.start_line,
					end_line = element.end_line,
					element_type = element.property_type,
					element_name = element.name
				});
			}
			
			// Process in batches
			int total_processed = 0;
			for (int i = 0; i < documents.size; i += BATCH_SIZE) {
				int batch_end = int.min(i + BATCH_SIZE, documents.size);
				var batch_docs = new Gee.ArrayList<string>();
				var batch_metadata = new Gee.ArrayList<ElementMetadata>();
				
				for (int j = i; j < batch_end; j++) {
					batch_docs.add(documents[j]);
					batch_metadata.add(element_metadata[j]);
				}
				
				// Generate embeddings for batch
				var embed_response = yield this.client.embed_array(batch_docs);
				if (embed_response == null || embed_response.embeddings.size == 0) {
					throw new GLib.IOError.FAILED("Failed to get embeddings for batch");
				}
				
				if (embed_response.embeddings.size != batch_docs.size) {
					throw new GLib.IOError.FAILED(
						"Embedding count mismatch: expected %d, got %d".printf(
							batch_docs.size, embed_response.embeddings.size));
				}
				
				// Initialize database index from first embedding if needed
				if (this.database.get_embedding_dimension() == 0) {
					var first_embedding = embed_response.embeddings[0];
					this.database.init_index((uint64)first_embedding.size);
				}
				
				// Convert embeddings to float arrays and store in FAISS
				var vector_batch = FloatArray(this.database.get_embedding_dimension());
				
				// Get current vector count to determine starting vector_id
				int64 start_vector_id = (int64)this.database.get_total_vectors();
				
				foreach (var embedding in embed_response.embeddings) {
					var float_array = this.embed_to_floats(embedding);
					vector_batch.add(float_array);
				}
				
				// Add vectors to FAISS index
				this.database.add_vectors_batch(vector_batch);
				
				// Store metadata in SQL database
				for (int j = 0; j < batch_metadata.size; j++) {
					var metadata = batch_metadata[j];
					int64 vector_id = start_vector_id + j;
					
					this.store_metadata(
						vector_id,
						metadata.file_id,
						metadata.start_line,
						metadata.end_line,
						metadata.element_type,
						metadata.element_name
					);
				}
				
				total_processed += batch_docs.size;
				GLib.debug("Processed batch: %d/%d elements", total_processed, documents.size);
			}
			
			GLib.debug("Completed processing %d elements from file: %s", total_processed, code_file.file_path);
		}
		
		/**
		 * Formats a CodeElement into a document string for vectorization.
		 * 
		 * Format follows the specification in the plan document:
		 * - type, name, file, lines, description, parameters, return type, dependencies, code snippet
		 * 
		 * @param element The CodeElement to format
		 * @param code_file The CodeFile containing the element
		 * @return Formatted document string
		 */
		private string format_element_document(CodeElement element, CodeFile code_file)
		{
			var doc = new GLib.StringBuilder();
			
			// Element type and name
			doc.append("%s: %s\n".printf(element.property_type, element.name));
			
			// Access modifier
			if (element.access_modifier != null && element.access_modifier != "") {
				doc.append("Access: %s\n".printf(element.access_modifier));
			}
			
			// File location
			doc.append("File: %s\n".printf(code_file.file_path));
			
			// Line range
			doc.append("Lines: %d-%d\n".printf(element.start_line, element.end_line));
			
			// Signature
			if (element.signature != null && element.signature != "") {
				doc.append("Signature: %s\n".printf(element.signature));
			}
			
			// Description
			if (element.description != null && element.description != "") {
				doc.append("Description: %s\n".printf(element.description));
			}
			
			// Parameters (for functions/methods/constructors)
			if (element.parameters.size > 0) {
				var param_parts = new Gee.ArrayList<string>();
				foreach (var param in element.parameters) {
					param_parts.add("%s: %s".printf(param.name, param.argument_type));
				}
				doc.append("Parameters: %s\n".printf(string.joinv(", ", param_parts.to_array())));
			}
			
			// Return type (for functions/methods)
			if (element.return_type != null && element.return_type != "" && element.return_type != "void") {
				doc.append("Returns: %s\n".printf(element.return_type));
			}
			
			// Properties (for classes/structs/interfaces)
			if (element.properties.size > 0) {
				var prop_parts = new Gee.ArrayList<string>();
				foreach (var prop in element.properties) {
					var accessors_str = string.joinv(", ", prop.accessors.to_array());
					prop_parts.add("%s: %s [%s]".printf(prop.name, prop.value_type, accessors_str));
				}
				doc.append("Properties: %s\n".printf(string.joinv(", ", prop_parts.to_array())));
			}
			
			// Dependencies
			if (element.dependencies.size > 0) {
				var dep_parts = new Gee.ArrayList<string>();
				foreach (var dep in element.dependencies) {
					dep_parts.add("%s: %s".printf(dep.relationship_type, dep.target));
				}
				doc.append("Dependencies: %s\n".printf(string.joinv(", ", dep_parts.to_array())));
			}
			
			// Code snippet (with smart truncation)
			doc.append("Code:\n");
			var code_snippet = this.get_truncated_code_snippet(element);
			doc.append(code_snippet);
			
			return doc.str;
		}
		
		/**
		 * Gets a truncated code snippet based on element type.
		 * 
		 * Applies smart truncation:
		 * - Classes/structs/interfaces: Only declaration and properties (~50 lines max)
		 * - Methods/functions/constructors: Full implementation
		 * - Properties/fields: Only declaration (1-10 lines)
		 * - Enums: All values
		 * - Namespaces: Only declaration
		 * - General: Max ~100 lines
		 * 
		 * @param element The CodeElement
		 * @return Truncated code snippet
		 */
		private string get_truncated_code_snippet(CodeElement element)
		{
			var snippet = element.code_snippet;
			if (snippet == null || snippet == "") {
				return "";
			}
			
			var lines = snippet.split("\n");
			var max_lines = 100; // Default maximum
			
			// Apply smart truncation based on element type
			switch (element.property_type) {
				case "class":
				case "struct":
				case "interface":
					// For classes, stop at first method (methods are separate elements)
					max_lines = 50;
					for (int i = 0; i < int.min(lines.length, max_lines); i++) {
						// Look for method definitions (heuristic: lines with "{" that aren't property declarations)
						if (lines[i].contains("{") && 
						    !lines[i].contains("get") && 
						    !lines[i].contains("set") &&
						    !lines[i].contains("property") &&
						    lines[i].contains("(")) {
							// Found a method, truncate before it
							var truncated = new GLib.StringBuilder();
							for (int j = 0; j < i; j++) {
								truncated.append(lines[j]);
								if (j < i - 1) truncated.append("\n");
							}
							truncated.append("\n// ... (methods extracted as separate elements)");
							return truncated.str;
						}
					}
					break;
					
				case "method":
				case "function":
				case "constructor":
					// Full implementation, but cap at 200 lines
					max_lines = 200;
					break;
					
				case "property":
				case "field":
					// Only declaration
					max_lines = 10;
					break;
					
				case "enum":
					// All enum values
					max_lines = 100;
					break;
					
				case "namespace":
					// Only declaration
					max_lines = 20;
					break;
			}
			
			// Apply general truncation if needed
			if (lines.length > max_lines) {
				var truncated = new GLib.StringBuilder();
				for (int i = 0; i < max_lines; i++) {
					truncated.append(lines[i]);
					if (i < max_lines - 1) truncated.append("\n");
				}
				truncated.append("\n// ... (truncated)");
				return truncated.str;
			}
			
			return snippet;
		}
		
		/**
		 * Converts embedding from ArrayList<double?> to float[].
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
		 * Stores metadata in SQL database.
		 */
		private void store_metadata(
			int64 vector_id,
			int64 file_id,
			int start_line,
			int end_line,
			string element_type,
			string element_name
		)
		{
			var insert_sql = """
				INSERT INTO vector_metadata 
				(vector_id, file_id, start_line, end_line, element_type, element_name)
				VALUES (?, ?, ?, ?, ?, ?);
			""";
			
			Sqlite.Statement stmt;
			if (this.sql_db.db.prepare_v2(insert_sql, -1, out stmt) != Sqlite.OK) {
				GLib.warning("Failed to prepare metadata insert statement: %s", this.sql_db.db.errmsg());
				return;
			}
			
			stmt.bind_int64(1, vector_id);
			stmt.bind_int64(2, file_id);
			stmt.bind_int(3, start_line);
			stmt.bind_int(4, end_line);
			stmt.bind_text(5, element_type);
			stmt.bind_text(6, element_name);
			
			if (stmt.step() != Sqlite.DONE) {
				GLib.warning("Failed to insert metadata: %s", this.sql_db.db.errmsg());
			}
			
			this.sql_db.is_dirty = true;
		}
		
		/**
		 * Metadata structure for batch processing.
		 */
		private struct ElementMetadata
		{
			public int64 file_id;
			public int start_line;
			public int end_line;
			public string element_type;
			public string element_name;
		}
	}
}
