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
	 * Represents a single search result from vector search.
	 * 
	 * Contains vector search results with metadata and code snippets.
	 */
	public class SearchResult : Object, Json.Serializable
	{
		/**
		 * FAISS vector ID.
		 */
		public int64 vector_id { get; set; default = 0; }
		
		/**
		 * FAISS distance (L2 distance - lower is better).
		 */
		public float distance { get; set; default = 0.0f; }
		
		/**
		 * Code location metadata.
		 */
		public OLLMvector.VectorMetadata metadata { get; set; }
		
		/**
		 * Get file object (computed from metadata.file_id).
		 * 
		 * @return File object
		 */
		public OLLMfiles.File file()
		{
			return this.folder.project_files.get_by_id(this.metadata.file_id);
		}
		
		/**
		 * SQL database for file lookup.
		 */
		private SQ.Database sql_db;
		
		/**
		 * Project folder for file operations.
		 */
		private OLLMfiles.Folder folder;
		
		/**
		 * Constructor.
		 * 
		 * @param sql_db SQL database for file lookup and VectorMetadata access
		 * @param folder Project folder for file operations (to read code snippets)
		 * @param vector_id FAISS vector ID
		 * @param distance FAISS distance (L2 distance - lower is better)
		 * @param metadata Code location metadata
		 */
		public SearchResult(
			SQ.Database sql_db,
			OLLMfiles.Folder folder,
			int64 vector_id,
			float distance,
			OLLMvector.VectorMetadata metadata
		)
		{
			this.sql_db = sql_db;
			this.folder = folder;
			this.vector_id = vector_id;
			this.distance = distance;
			this.metadata = metadata;
		}
		
		/**
		 * Get code snippet extracted from file_path + line_range.
		 * 
		 * Uses metadata.file_id to lookup File via folder.project_files,
		 * then uses buffer_provider to get code snippet using metadata.start_line and metadata.end_line.
		 * 
		 * @param max_lines Maximum number of lines to return (-1 for no limit)
		 * @return Code snippet as string, truncated to max_lines if specified
		 */
		public string code_snippet(int max_lines = -1)
		{
			var file = this.file();
			
			// Use buffer to get code snippet (0-based line numbers)
			// Convert from 1-indexed (metadata) to 0-based (buffer)
			var start_line = (this.metadata.start_line - 1).clamp(0, int.MAX);
			var end_line = (this.metadata.end_line - 1).clamp(0, int.MAX);
			
			if (start_line > end_line) {
				return "";
			}
			
			// Apply max_lines truncation if specified
			end_line = (max_lines != -1 && (end_line - start_line + 1) > max_lines) ?
					 start_line + max_lines - 1 : end_line;
			
			if (file.buffer == null) {
				return "";
			}
			
			return file.buffer.get_text(start_line, end_line);
		}
		
		/**
		 * Custom property serialization to exclude internal dependencies.
		 */
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "sql-db":
				case "folder":
					// Exclude internal dependencies from serialization
					return null;
				
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}
}
}

