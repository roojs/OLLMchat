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
	 * 
	 * The indexing pipeline processes files through three layers:
	 * 1. Tree: Extracts code structure using tree-sitter
	 * 2. Analysis: Generates one-line descriptions using LLM
	 * 3. VectorBuilder: Converts to embeddings and stores in FAISS
	 * 
	 * Supports incremental indexing by checking file modification times
	 * and skipping unchanged files (unless force=true).
	 * 
	 * == Usage Example ==
	 * 
	 * {{{
	 * // Create indexer
	 * var indexer = new OLLMvector.Indexing.Indexer(
	 *     analysis_client,
	 *     embed_client,
	 *     vector_db,
	 *     sql_db,
	 *     project_manager
	 * );
	 * 
	 * // Index single file
	 * yield indexer.index_file(file, force: false);
	 * 
	 * // Index folder recursively
	 * yield indexer.index_folder(folder, recursive: true);
	 * }}}
	 */
	public class Indexer : VectorBase
	{
		private OLLMvector.Database vector_db;
		private SQ.Database sql_db;
		private OLLMfiles.ProjectManager manager;
		
		/**
		 * Emitted when indexing progress is made.
		 * 
		 * @param current Current file number being processed (1-based)
		 * @param total Total number of files to process
		 * @param file_path Path of the file currently being processed
		 */
		public signal void progress(int current, int total, string file_path);
		
		/**
		 * Emitted when an element is scanned during indexing.
		 * 
		 * @param element_name Name of the element being scanned
		 * @param element_number Current element number (1-based)
		 * @param total_elements Total number of elements in the current file
		 */
		public signal void element_scanned(string element_name, int element_number, int total_elements);
		
		/**
		 * Constructor.
		 * 
		 * @param config The Config2 instance containing tool configuration
		 * @param vector_db The vector database for FAISS storage (should have filename set in constructor to auto-save)
		 * @param sql_db The SQLite database for metadata storage
		 * @param manager The ProjectManager for file/folder operations
		 */
		public Indexer(
			OLLMchat.Settings.Config2 config,
			OLLMvector.Database vector_db,
			SQ.Database sql_db,
			OLLMfiles.ProjectManager manager)
		{
			base(config);
			this.vector_db = vector_db;
			this.sql_db = sql_db;
			this.manager = manager;
		}
		
		/**
		 * Index a single file.
		 * 
		 * Processes the file through Tree → Analysis → VectorBuilder pipeline.
		 * Updates last_vector_scan timestamp after successful indexing.
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
				if (file.last_vector_scan >= mtime && mtime > 0) {
					GLib.debug("Skipping file '%s' (not modified since last scan)", file.path);
					return false;
				}
			}
			
			GLib.debug("Processing file '%s'", file.path);
			
			var tree = new Tree(file);
			yield tree.parse();
			
			if (tree.elements.size == 0) {
				GLib.debug("No elements found in file '%s'", file.path);
				
				// After scanning completes, check if file was deleted before saving
				// Fetch filebase from database again to check current delete_id
				var query = OLLMfiles.FileBase.query(this.sql_db, this.manager);
				var check_file = new Gee.ArrayList<OLLMfiles.FileBase>();
				yield query.select_async("WHERE id = " + file.id.to_string(), check_file);
				
				// Check if file was deleted during scan or no longer exists
				if (check_file.size == 0) {
					// File not found in database - may have been deleted, skip update
					GLib.debug("Indexer: Skipping saveToDB for file '%s' (not found in database)", file.path);
					return true;  // Return success but don't update database
				}
				
				var db_file = check_file.get(0);
				if (db_file.delete_id > 0) {
					// File was deleted - skip database update
					GLib.debug("Indexer: Skipping saveToDB for deleted file '%s' (delete_id=%lld)", 
						file.path, db_file.delete_id);
					return true;  // Return success but don't update database
				}
				
				// File not deleted - proceed with normal save
				file.last_vector_scan = new DateTime.now_local().to_unix();
				file.saveToDB(this.sql_db, null, false);
				return true;
			}
			
			var analysis = new Analysis(this.config, this.sql_db);
			
			// Connect to element_analyzed signal and forward as element_scanned
			analysis.element_analyzed.connect((element_name, element_number, total_elements) => {
				this.element_scanned(element_name, element_number, total_elements);
			});
			
			tree = yield analysis.analyze_tree(tree);
			
			// Analyze file and create file-level summary
			tree = yield analysis.analyze_file(tree);
			
			// VectorBuilder already takes config
			var vector_builder = new VectorBuilder(
				this.config, this.vector_db, this.sql_db);
			yield vector_builder.process_file(tree);
			
			// After scanning completes, check if file was deleted before saving
			// Fetch filebase from database again to check current delete_id
			var query = OLLMfiles.FileBase.query(this.sql_db, this.manager);
			var check_file = new Gee.ArrayList<OLLMfiles.FileBase>();
			yield query.select_async("WHERE id = " + file.id.to_string(), check_file);
			
			// Check if file was deleted during scan or no longer exists
			if (check_file.size == 0) {
				// File not found in database - may have been deleted, skip update
				GLib.debug("Indexer: Skipping saveToDB for file '%s' (not found in database)", file.path);
				return true;  // Return success but don't update database
			}
			
			var db_file = check_file.get(0);
			if (db_file.delete_id > 0) {
				// File was deleted - skip database update
				GLib.debug("Indexer: Skipping saveToDB for deleted file '%s' (delete_id=%lld)", 
					file.path, db_file.delete_id);
				return true;  // Return success but don't update database
			}
			
			// File not deleted - proceed with normal save
			file.last_vector_scan = new DateTime.now_local().to_unix();
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
		 * Index a folder.
		 * 
		 * Indexes all files in the folder's project_files list. The caller should
		 * ensure that the folder has been scanned (via read_dir) and project_files
		 * has been updated (via update_from) before calling this method.
		 * 
		 * @param folder The folder to index (must exist in database and have project_files populated)
		 * @param recurse Unused (kept for API compatibility)
		 * @param force If true, skip incremental check and force re-indexing
		 * @return Number of files indexed
		 */
		public async int index_folder(OLLMfiles.Folder folder, bool recurse = false, bool force = false) throws GLib.Error
		{
			GLib.debug("Processing folder '%s'", folder.path);
			
			int files_indexed = 0;
			uint n_items = folder.project_files.get_n_items();
			GLib.debug("Folder '%s' has %u files in project_files", folder.path, n_items);
			
			// Index all files from ProjectFiles
			uint current = 0;
			foreach (var project_file in folder.project_files) {
				current++;
				var file = project_file.file;
				this.progress((int)current, (int)n_items, file.path);
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
				var file = (OLLMfiles.File)filebase;
				this.progress(1, 1, file.path);
				if (yield this.index_file(file, force)) {
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
			// Use the static VectorMetadata.reset_database method to do the actual reset
			OLLMvector.VectorMetadata.reset_database(this.sql_db, vector_db_path);
			
		// Get dimension first, then create database
			var temp_db = new OLLMvector.Database(this.config, vector_db_path,
				 OLLMvector.Database.DISABLE_INDEX);
			var dimension = yield temp_db.embed_dimension();
			this.vector_db = new OLLMvector.Database(this.config, vector_db_path, dimension);
		}
	}

}
