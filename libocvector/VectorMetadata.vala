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

namespace OLLMvector
{
	/**
	 * Represents vector metadata stored in SQL database.
	 * 
	 * Maps vector_id (from FAISS) to code location information:
	 * - file_id (references OLLMfiles.File.id)
	 * - start_line, end_line (line range for code snippet)
	 * - element_type, element_name (for display/filtering)
	 */
	public class VectorMetadata : Object
	{
		/**
		 * Vector ID from FAISS index (PRIMARY KEY).
		 */
		public int64 vector_id { get; set; default = 0; }
		
		/**
		 * File ID (references OLLMfiles.File.id).
		 */
		public int64 file_id { get; set; default = 0; }
		
		/**
		 * Starting line number (1-indexed).
		 */
		public int start_line { get; set; default = 0; }
		
		/**
		 * Ending line number (1-indexed).
		 */
		public int end_line { get; set; default = 0; }
		
		/**
		 * Element type (e.g., "class", "method", "function", "property", etc.).
		 */
		public string element_type { get; set; default = ""; }
		
		/**
		 * Element name (e.g., "DatabaseManager", "execute_query", etc.).
		 */
		public string element_name { get; set; default = ""; }
		
		/**
		 * Constructor.
		 */
		public VectorMetadata()
		{
		}
		
		/**
		 * Initialize database table for vector_metadata objects.
		 */
		public static void initDB(SQ.Database db)
		{
			string errmsg;
			// Note: Foreign key constraint removed - file_id references OLLMfiles.File.id
			// but the exact table name/structure may vary. The relationship is maintained
			// at the application level.
			var query = "CREATE TABLE IF NOT EXISTS vector_metadata (" +
				"vector_id INTEGER PRIMARY KEY, " +
				"file_id INTEGER NOT NULL, " +
				"start_line INTEGER NOT NULL, " +
				"end_line INTEGER NOT NULL, " +
				"element_type TEXT NOT NULL, " +
				"element_name TEXT NOT NULL" +
				");";
			if (Sqlite.OK != db.db.exec(query, null, out errmsg)) {
				GLib.warning("Failed to create vector_metadata table: %s", db.db.errmsg());
			}
			
			// Create indexes for efficient lookups
			if (Sqlite.OK != db.db.exec(
				"CREATE INDEX IF NOT EXISTS idx_vector_metadata_file_id ON vector_metadata(file_id);",
				null,
				out errmsg
			)) {
				GLib.warning("Failed to create index: %s", db.db.errmsg());
			}
			if (Sqlite.OK != db.db.exec(
				"CREATE INDEX IF NOT EXISTS idx_vector_metadata_vector_id ON vector_metadata(vector_id);",
				null,
				out errmsg
			)) {
				GLib.warning("Failed to create index: %s", db.db.errmsg());
			}
		}
		
		/**
		 * Create a query object for vector_metadata table.
		 * 
		 * @param db The database instance
		 * @return A configured Query object ready to use
		 */
		public static SQ.Query<VectorMetadata> query(SQ.Database db)
		{
			return new SQ.Query<VectorMetadata>(db, "vector_metadata");
		}
		
		/**
		 * Save this VectorMetadata to the database.
		 * 
		 * @param db The database instance
		 * @param sync Whether to sync database to disk after save
		 */
		public void saveToDB(SQ.Database db, bool sync = false)
		{
			var sq = VectorMetadata.query(db);
			if (this.vector_id <= 0) {
				// Insert new record
				this.vector_id = sq.insert(this);
			} else {
				// Update existing record
				sq.updateById(this);
			}
			
			// Backup in-memory database to disk only if sync is true
			if (sync) {
				db.backupDB();
			}
		}
		
		/**
		 * Remove this VectorMetadata from the database.
		 * 
		 * @param db The database instance
		 */
		public void removeFromDB(SQ.Database db)
		{
			if (this.vector_id <= 0) {
				return;
			}
			VectorMetadata.query(db).deleteId(this.vector_id);
		}
		
		/**
		 * Generic lookup method for vector metadata.
		 * 
		 * @param db The database instance
		 * @param key The column name to search (e.g., "vector_id", "file_id")
		 * @param value The value to search for
		 * @return VectorMetadata object, or null if not found
		 */
		public static VectorMetadata? lookup(
			SQ.Database db,
			string key,
			int64 value
		)
		{
			var results = new Gee.ArrayList<VectorMetadata>();
			VectorMetadata.query(db).select("WHERE " + key + " = " + value.to_string(), results);
			if (results.size > 0) {
				return results[0];
			}
			return null;
		}
		
		/**
		 * Lookup metadata for multiple vector_ids (for search results).
		 * 
		 * @param db The database instance
		 * @param vector_ids Array of vector IDs to lookup
		 * @return List of VectorMetadata objects, ordered by vector_id
		 */
		public static Gee.ArrayList<VectorMetadata> lookup_vectors(
			SQ.Database db,
			int64[] vector_ids
		)
		{
			if (vector_ids.length == 0) {
				return new Gee.ArrayList<VectorMetadata>();
			}
			
			// Build WHERE clause with OR conditions
			var conditions = new Gee.ArrayList<string>();
			for (int i = 0; i < vector_ids.length; i++) {
				conditions.add("vector_id = " + vector_ids[i].to_string());
			}
			
			var results = new Gee.ArrayList<VectorMetadata>();
			VectorMetadata.query(db).select(
				"WHERE " + string.joinv(" OR ", conditions.to_array()),
				results
			);
			return results;
		}
	}
}
