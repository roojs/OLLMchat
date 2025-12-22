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
	 * Main indexing orchestrator.
	 * 
	 * Integrates Tree, Analysis, and VectorBuilder components to process
	 * files and folders for vector indexing. Implements incremental update
	 * logic and folder-based indexing with recursion support.
	 */
	public class Indexer : Object
	{
		private OLLMchat.Client analysis_client;
		private OLLMchat.Client embed_client;
		private OLLMvector.Database vector_db;
		private SQ.Database sql_db;
		private OLLMfiles.ProjectManager manager;
		
		/**
		 * Constructor.
		 * 
		 * @param analysis_client The OLLMchat client for analysis (LLM summarization)
		 * @param embed_client The OLLMchat client for embeddings API
		 * @param vector_db The vector database for FAISS storage (should have filename set in constructor to auto-save)
		 * @param sql_db The SQLite database for metadata storage
		 * @param manager The ProjectManager for file/folder operations
		 */
		public Indexer(
			OLLMchat.Client analysis_client,
			OLLMchat.Client embed_client,
			OLLMvector.Database vector_db,
			SQ.Database sql_db,
			OLLMfiles.ProjectManager manager)
		{
			this.analysis_client = analysis_client;
			this.embed_client = embed_client;
			this.vector_db = vector_db;
			this.sql_db = sql_db;
			this.manager = manager;
		}
		
		/**
		 * Index a single file.
		 * 
		 * Processes the file through Tree → Analysis → VectorBuilder pipeline.
		 * Updates last_scan timestamp after successful indexing.
		 * 
		 * @param file The file to index (must exist in database)
		 * @param force If true, skip incremental check and force re-indexing
		 * @return true if file was indexed, false if skipped (not modified)
		 */
		public async bool index_file(OLLMfiles.File file, bool force = false) throws GLib.Error
		{
			// Skip ignored files
			if (file.is_ignored) {
				GLib.debug("Skipping file '%s' (is_ignored=true)", file.path);
				return false;
			}
			
			// Only index text files
			if (!file.is_text) {
				GLib.debug("Skipping file '%s' (not a text file, is_text=false)", file.path);
				return false;
			}
			
			
			if (!force) {
				var mtime = file.mtime_on_disk();
				if (file.last_scan >= mtime && mtime > 0) {
					GLib.debug("Skipping file '%s' (not modified since last scan)", file.path);
					return false;
				}
			}
			
			GLib.debug("Processing file '%s'", file.path);
			
			var tree = new Tree(file);
			yield tree.parse();
			
			if (tree.elements.size == 0) {
				GLib.debug("No elements found in file '%s'", file.path);
				file.last_scan = new DateTime.now_local().to_unix();
				file.saveToDB(this.sql_db, null, false);
				return true;
			}
			
			var analysis = new Analysis(this.analysis_client, this.sql_db);
			tree = yield analysis.analyze_tree(tree);
			
			var vector_builder = new VectorBuilder(
				this.embed_client, this.vector_db, this.sql_db);
			yield vector_builder.process_file(tree);
			
			file.last_scan = new DateTime.now_local().to_unix();
			file.saveToDB(this.sql_db, null, false);
			
			// Save vector database after each file
			try {
				this.vector_db.save_index();
			} catch (GLib.Error e) {
				GLib.warning("Failed to save vector database after indexing '%s': %s", file.path, e.message);
			}
			
			GLib.debug("Completed indexing file '%s' (%d elements)", file.path, tree.elements.size);
			return true;
		}
		
		/**
		 * Index a folder and optionally recurse into subfolders.
		 * 
		 * Uses ProjectFiles to get the list of files to index. ProjectFiles already
		 * filters out ignored files and non-text files, and handles recursion.
		 * 
		 * @param folder The folder to index (must exist in database)
		 * @param recurse If true, recursively process subfolders (used by ProjectFiles.update_from)
		 * @param force If true, skip incremental check and force re-indexing
		 * @param scan_time Fixed scan time for this scan session (0 = create new)
		 * @return Number of files indexed
		 */
		public async int index_folder(OLLMfiles.Folder folder, bool recurse = false, bool force = false, int64 scan_time = 0) throws GLib.Error
		{
			if (scan_time == 0) {
				scan_time = new DateTime.now_local().to_unix();
			}
			
			if (!force && folder.last_scan == scan_time) {
				GLib.debug("Skipping folder '%s' (already being scanned in this session)", folder.path);
				return 0;
			}
			
			folder.last_scan = scan_time;
			folder.saveToDB(this.sql_db, null, false);
			
			GLib.debug("Processing folder '%s' (recurse=%s)", folder.path, recurse.to_string());
			
			// Load children from database if needed
			if (folder.children.items.size == 0) {
				GLib.debug("Loading folder children from database for '%s'", folder.path);
				yield folder.load_files_from_db();
			}
			
			// Update ProjectFiles to get the list of files to index
			// ProjectFiles.update_from already filters ignored and non-text files
			folder.project_files.update_from(folder);
			
			int files_indexed = 0;
			uint n_items = folder.project_files.get_n_items();
			GLib.debug("Folder '%s' has %u files in project_files", folder.path, n_items);
			
			// Index all files from ProjectFiles
			for (uint i = 0; i < n_items; i++) {
				var project_file = folder.project_files.get_item(i) as OLLMfiles.ProjectFile;
				if (project_file == null) {
					continue;
				}
				
				var file = project_file.file;
				try {
					if (yield this.index_file(file, force)) {
						files_indexed++;
					}
				} catch (GLib.Error e) {
					GLib.warning("Failed to index file '%s': %s", file.path, e.message);
				}
			}
			
			GLib.debug("Completed indexing folder '%s' (%d files indexed)", folder.path, files_indexed);
			
			// At end of scan: delete metadata with invalid file_ids
			this.sql_db.exec(
				"DELETE FROM vector_metadata " +
				"WHERE file_id NOT IN (SELECT id FROM filebase WHERE base_type = 'f')"
			);
			
			return files_indexed;
		}
		
		/**
		 * Index a file or folder.
		 * 
		 * Processes the FileBase object through the appropriate indexing method.
		 * Handles FileAlias by following to target.
		 * 
		 * @param filebase The file or folder to index (must exist in database)
		 * @param recurse If true and filebase is a folder, recursively process subfolders
		 * @param force If true, skip incremental check and force re-indexing
		 * @return Number of files indexed
		 */
		public async int index_filebase(OLLMfiles.FileBase filebase, bool recurse = false, bool force = false) throws GLib.Error
		{
			if (filebase.is_alias && filebase.points_to != null) {
				filebase = filebase.points_to;
			}
			
			if (filebase is OLLMfiles.File) {
				if (yield this.index_file((OLLMfiles.File)filebase, force)) {
					return 1;
				}
				return 0;
			}
			
			if (filebase is OLLMfiles.Folder) {
				return yield this.index_folder((OLLMfiles.Folder)filebase, recurse, force);
			}
			
			throw new GLib.IOError.INVALID_ARGUMENT("FileBase is not a file or folder: " + filebase.path);
		}
		
		/**
		 * Resets the entire vector database.
		 * 
		 * Deletes the FAISS vector database file, resets all file scan dates to 0,
		 * and deletes all vector metadata entries.
		 * 
		 * @param vector_db_path Path to the FAISS vector database file (e.g., "codedb.faiss.vectors")
		 */
		public async void reset_database(string vector_db_path) throws GLib.Error
		{
			// Delete FAISS vector database file
			var vector_db_file = GLib.File.new_for_path(vector_db_path);
			if (vector_db_file.query_exists()) {
				try {
					vector_db_file.delete();
					GLib.debug("Deleted vector database file: %s", vector_db_path);
				} catch (GLib.Error e) {
					GLib.warning("Failed to delete vector database file '%s': %s", vector_db_path, e.message);
				}
			}
			
			// Get dimension first, then create new Database object (clears in-memory index)
			var dimension = yield OLLMvector.Database.get_embedding_dimension(this.embed_client);
			this.vector_db = new OLLMvector.Database(this.embed_client, vector_db_path, dimension);
			
			// Delete all vector metadata
			this.sql_db.exec("DELETE FROM vector_metadata");
			
			// Reset all file scan dates to -1
			this.sql_db.exec("UPDATE filebase SET last_scan = -1 WHERE base_type = 'f'");
		}
	}

}
