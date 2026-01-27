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
	 * Vector building layer for documentation file processing.
	 * 
	 * Extends VectorBuilder to handle documentation-specific chunking
	 * with context headers.
	 */
	public class DocumentationVectorBuilder : VectorBuilder
	{
		/**
		 * Constructor.
		 */
		public DocumentationVectorBuilder(
			OLLMchat.Settings.Config2 config,
			OLLMvector.Database database,
			SQ.Database sql_db)
		{
			base(config, database, sql_db);
		}
		
		/**
		 * Processes a DocumentationTree and generates vectors for leaf sections.
		 * 
		 * Overrides VectorBuilder.process_file() to handle documentation chunking.
		 */
		public async void process_file(DocumentationTree tree) throws GLib.Error
		{
			if (tree.elements.size == 0) {
				GLib.debug("No elements to process in documentation file: %s", tree.file.path);
				return;
			}
			
			// Find all leaf sections (sections with no children)
			var leaf_sections = new Gee.ArrayList<VectorMetadata>();
			foreach (var element in tree.elements) {
				if (element.children.size == 0) {
					leaf_sections.add(element);
				}
			}
			
			// Load cached metadata for incremental processing
			var cached_metadata = new Gee.HashMap<string, VectorMetadata>();
			var results = new Gee.ArrayList<VectorMetadata>();
			VectorMetadata.query(this.sql_db).select("WHERE file_id = " + tree.file.id.to_string(), results);
			
			foreach (var metadata in results) {
				var cache_key = metadata.ast_path == "" ? 
					metadata.element_type + ":" + metadata.element_name : 
					metadata.ast_path;
				cached_metadata.set(cache_key, metadata);
			}
			
			// Separate into unchanged and changed (similar to VectorBuilder)
			var unchanged_elements = new Gee.ArrayList<VectorMetadata>();
			var changed_elements = new Gee.ArrayList<VectorMetadata>();
			var elements_to_delete = new Gee.HashSet<int>();
			
			// Build set of current element keys for deletion detection
			var current_keys = new Gee.HashSet<string>();
			foreach (var element in leaf_sections) {
				var cache_key = element.ast_path == "" ? 
					element.element_type + ":" + element.element_name : 
					element.ast_path;
				current_keys.add(cache_key);
			}
			
			// Check each leaf section
			foreach (var element in leaf_sections) {
				var cache_key = element.ast_path == "" ? 
					element.element_type + ":" + element.element_name : 
					element.ast_path;
				
				if (!cached_metadata.has_key(cache_key)) {
					// New element - needs new embedding
					changed_elements.add(element);
					continue;
				}
				
				var cached = cached_metadata.get(cache_key);
				
				// Calculate MD5 for current element content
				var element_content = tree.lines_to_string(element.start_line, element.end_line);
				var checksum = new GLib.Checksum(GLib.ChecksumType.MD5);
				checksum.update((uint8[])element_content.to_utf8(), -1);
				element.md5_hash = checksum.get_string();
				
				// Check if element is unchanged (can reuse existing vector)
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
						// Both MD5 empty (legacy) but names match - unchanged
						is_unchanged = true;
					}
				}
				
				if (is_unchanged) {
					// Unchanged element - reuse existing vector
					unchanged_elements.add(element);
					// Update line numbers if they changed
					if (cached.start_line != element.start_line || cached.end_line != element.end_line) {
						cached.start_line = element.start_line;
						cached.end_line = element.end_line;
						cached.saveToDB(this.sql_db, false);
					}
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
			foreach (var entry in cached_metadata.entries) {
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
			
			GLib.debug("DocumentationVectorBuilder.process_file: %d unchanged (reuse vector), %d changed/new (create vector), %d deleted", 
			           unchanged_elements.size, changed_elements.size, elements_to_delete.size);
			
			// Process changed/new leaf sections
			if (changed_elements.size == 0) {
				return;
			}
			
			// Chunk each leaf section and create documents
			var documents = new Gee.ArrayList<string>();
			var chunk_metadata = new Gee.ArrayList<VectorMetadata>();
			
			foreach (var section in changed_elements) {
				// Get section content
				var section_content = tree.lines_to_string(section.start_line, section.end_line);
				
				// Process section as single chunk (like code elements)
				var document = this.format_documentation_chunk(section, section_content, tree);
				documents.add(document);
				
				// Create metadata for this section
				var chunk_meta = this.create_chunk_metadata(section, section_content);
				chunk_metadata.add(chunk_meta);
			}
			
			// Get embed model (unified for code and documentation)
			var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
			
			// Create embeddings
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
				throw new GLib.IOError.FAILED("Failed to get embeddings for documentation file");
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
			for (int j = 0; j < chunk_metadata.size; j++) {
				var element = chunk_metadata.get(j);
				element.vector_id = start_vector_id + j;
				element.saveToDB(this.sql_db, false);
			}
			
			GLib.debug("Completed processing %d changed elements from documentation file: %s", changed_elements.size, tree.file.path);
		}
		
		/**
		 * Formats a documentation chunk with context headers.
		 * 
		 * Overrides VectorBuilder.format_element_document().
		 */
		private string format_documentation_chunk(
			VectorMetadata section,
			string chunk_content,
			DocumentationTree tree)
		{
			string doc = "DOCUMENT: " + GLib.Path.get_basename(tree.file.path) + "\n";
			
			// DOCUMENT SUMMARY header (from root element)
			if (tree.root_element != null && tree.root_element.description != "") {
				doc += "DOCUMENT SUMMARY: " + tree.root_element.description.strip() + "\n";
			}
			
			// SECTION CONTEXT header (only if nesting level > 1)
			var nesting_level = section.ast_path.split("-").length;
			if (nesting_level > 1) {
				var section_context = section.get_section_context();
				if (section_context != "") {
					doc += "SECTION CONTEXT: " + section_context + "\n";
				}
			}
			
			// Section content
			doc += "\n" + chunk_content;
			
			return doc;
		}
		
		/**
		 * Creates metadata for a chunk (copy of section metadata).
		 */
		private VectorMetadata create_chunk_metadata(VectorMetadata section, string chunk)
		{
			// Create copy of section metadata
			var chunk_meta = new VectorMetadata() {
				file_id = section.file_id,
				element_type = section.element_type,
				element_name = section.element_name,
				category = section.category,
				ast_path = section.ast_path,
				parent = section.parent,
				description = section.description,
				start_line = section.start_line,
				end_line = section.end_line
			};
			
			// Calculate MD5 for chunk content
			var checksum = new GLib.Checksum(GLib.ChecksumType.MD5);
			checksum.update((uint8[])chunk.to_utf8(), -1);
			chunk_meta.md5_hash = checksum.get_string();
			
			return chunk_meta;
		}
	}
}
