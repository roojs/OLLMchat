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

namespace OLLMfiles
{
	/**
	 * Represents a file change history entry.
	 * Handles backup creation and database storage for file changes.
	 * 
	 * This class tracks what happened to each file during command execution
	 * and edit file actions. It is organized around files (what users understand),
	 * not operations (implementation details).
	 * 
	 * == Key Purpose ==
	 * 
	 * This table is primarily for user review, approval, and restoration of changes:
	 * - User thinks in terms of files: "What happened to file X?" rather than "What operations occurred?"
	 * - Listing file changes for user review before applying them
	 * - Backing up files so they can be compared (diff)
	 * - Approving/rejecting file changes with ability to restore if rejected
	 * - Restoring files if changes are rejected
	 * - Reviewing what changed and when for each file
	 * 
	 * == Ignored Files ==
	 * 
	 * Files with `is_ignored = true` are filtered out and not tracked in the
	 * file_history table. Only non-ignored files are recorded in the history
	 * for user review and approval.
	 */
	public class FileHistory : Object
	{
		/**
		 * Database ID.
		 */
		public int64 id { get; set; default = 0; }
		
		/**
		 * The file path (primary identifier - what user cares about).
		 */
		public string path { get; set; default = ""; }
		
		/**
		 * Reference to filebase record (0 for new files or deleted files).
		 * Deleted files are removed from filebase.
		 */
		public int64 filebase_id { get; set; default = 0; }
		
		/**
		 * When the change occurred (when file was removed or changed).
		 * For overlay/command execution updates, all timestamps for the same
		 * command/run/edit should be the same (based on when the command/run/edit
		 * started, NOT when the record was created).
		 */
		public int64 timestamp { get; set; default = 0; }
		
		/**
		 * Change type: "added", "modified", or "deleted".
		 * User-friendly: "file X was deleted", "file Y was modified", "file Z was added".
		 * 
		 * Note: Type changes (file→folder, folder→file) are just delete + add, not a separate action.
		 * Note: Renames use change_type="deleted" with moved_to filled in (file was deleted from original path, moved to new path).
		 * Note: Renames also use change_type="added" with moved_from filled in (file was added at new path, moved from old path).
		 */
		public string change_type { get; set; default = ""; }
		
		/**
		 * The file type before it was changed (matches filebase base_type standard).
		 * Type identifiers: "f" = File, "d" = Folder/Directory, "fa" = FileAlias (alias/symlink).
		 * 
		 * Note: FileAlias always uses "fa" regardless of whether it points to a file or folder (no "da" distinction).
		 * 
		 * For history purposes - represents what the file was before the change:
		 * - For "added": represents the type of the new file
		 * - For "deleted": represents what type it was before deletion
		 * - For "modified": represents the file type (usually "f")
		 */
		public string base_type { get; set; default = ""; }
		
		/**
		 * Path where the old version will be saved (empty string "" for new files).
		 * This is the path where FileHistory class will save the backup of the original file.
		 * Used for restoration if change is rejected.
		 * 
		 * For new files: backup_path = "" (empty string, no backup needed)
		 * For modified/deleted files: backup_path = path where backup file will be created
		 * 
		 * Note: backup_path will be removed from filebase table - this is the only place to store it.
		 * Note: FileHistory class is responsible for creating backups (this responsibility used to be in ProjectManager or elsewhere).
		 * Note: The filebase contains the 'new file' info and the real file has the contents - so backup_path will be empty "" for new files.
		 */
		public string backup_path { get; set; default = ""; }
		
		/**
		 * User approval state (0 = pending, 1 = approved, -1 = rejected).
		 * - 0 = pending (not yet reviewed)
		 * - 1 = approved (user approved the change)
		 * - -1 = rejected (user rejected the change)
		 * 
		 * Note: Don't track "applied" or "restored" - status is just approval state.
		 */
		public int status { get; set; default = 0; }
		
		/**
		 * Target path if file was previously an alias (symlink target).
		 * Empty string "" if file was not an alias.
		 * Stored for restoration purposes.
		 */
		public string alias_target { get; set; default = ""; }
		
		/**
		 * Destination path (for rename operations when file was deleted - file was moved to here).
		 * For renames: change_type="deleted", path = original path, moved_to = destination path.
		 * Empty string "" for non-rename operations (regular delete, add, modify).
		 * 
		 * NOTE: Rename tracking (moved_to/moved_from) is not currently supported.
		 * This would require additional tracking in the scanning system to detect and correlate
		 * MOVED events with source and destination paths. For now, renames are tracked
		 * as separate "deleted" and "added" events without the moved_to/moved_from fields.
		 * This is a future enhancement to keep the initial implementation simple.
		 */
		public string moved_to { get; set; default = ""; }
		
		/**
		 * Source path (for rename operations when file was added - file was moved from here).
		 * For renames: change_type="added", path = new path, moved_from = original path.
		 * Empty string "" for non-rename operations (regular add, delete, modify).
		 * 
		 * NOTE: Rename tracking (moved_to/moved_from) is not currently supported.
		 * This would require additional tracking in the scanning system to detect and correlate
		 * MOVED events with source and destination paths. For now, renames are tracked
		 * as separate "deleted" and "added" events without the moved_to/moved_from fields.
		 * This is a future enhancement to keep the initial implementation simple.
		 */
		public string moved_from { get; set; default = ""; }
		
		/**
		 * Agent identifier (0 for now, may be used later to track which agent/tool made the change).
		 */
		public int agent_id { get; set; default = 0; }
		
		// Internal fields
		private SQ.Database db;
		private FileBase filebase_object;
		
		// Static field for cleanup throttling
		private static int64 last_cleanup_timestamp = 0;
		
		/**
		* Constructor - creates a FileHistory object for a change.
		* 
		* @param db Database instance
		* @param filebase_object FileBase object (File or Folder) - required (even for new files, create a fake/temporary one)
		* @param change_type "added", "modified", or "deleted"
		* @param timestamp Timestamp when change occurred (same for all changes in same command/run/edit)
		*/
		public FileHistory(
			SQ.Database db,
			FileBase filebase_object,
			string change_type,
			GLib.DateTime timestamp)
		{
			this.db = db;
			this.filebase_object = filebase_object;
			this.change_type = change_type;
			this.timestamp = timestamp.to_unix();
			
			// Set path and filebase_id from filebase_object
			this.path = filebase_object.path;
			this.filebase_id = filebase_object.id;
			this.base_type = filebase_object.base_type;
			
			// Store alias target if it's an alias
			if (filebase_object.is_alias && filebase_object.target_path != "") {
				this.alias_target = filebase_object.target_path;
			}
		}
		
		/**
		 * Commit the change to database.
		 * 
		 * This method:
		 * 1. Checks if file is ignored (skips if so)
		 * 2. Inserts change record into database (to get id)
		 * 3. Creates backup file if needed (for modified/deleted files)
		 * 4. Updates database record with backup_path
		 * 
		 * @throws Error if backup creation or database insert fails
		 */
		public async void commit() throws Error
		{
			// Check if file is ignored - skip if so
			if (this.filebase_object.is_ignored) {
				return; // Do nothing for ignored files
			}
			
			// Insert into database first (to get id)
			yield this.save_to_db();
			
			if (!(this.filebase_object is File)) {
				return;
			}
			// Create backup if needed (for modified/deleted/revert files, but not for symlinks)
			if ((this.change_type == "modified" || 
				this.change_type == "deleted" || this.change_type == "revert")) {
				yield this.create_backup();
				// Update database record with backup_path
				yield this.save_to_db();
			}
		}
		
		/**
		 * Create backup file for modified/deleted files.
		 * 
		 * Uses the same system as edit file tool: ~/.cache/ollmchat/edited/
		 * Format: {timestamp}-{id}-{basename}
		 * 
		 * Uses timestamp-based date format (Y-m-d) from this.timestamp.
		 * Sets this.backup_path to the backup file path.
		 * 
		 * For deleted files: Copies file from its current path to backup location.
		 * For modified files: Copies file from its current path to backup location.
		 * 
		 * @throws Error if backup creation fails
		 */
		private async void create_backup() throws Error
		{
			try {
				var cache_dir = GLib.Path.build_filename(
					GLib.Environment.get_home_dir(),
					".cache",
					"ollmchat",
					"edited"
				);
				
				// Create cache directory if it doesn't exist
				var cache_dir_file = GLib.File.new_for_path(cache_dir);
				if (!cache_dir_file.query_exists()) {
					cache_dir_file.make_directory_with_parents(null);
				}
				
				// Generate backup filename using timestamp-based date and id
				var basename = GLib.Path.get_basename(this.path);
				var date_time = new GLib.DateTime.from_unix_local(this.timestamp);
				this.backup_path = GLib.Path.build_filename(
					cache_dir,
					"%s-%lld-%s".printf(
						date_time.format("%Y-%m-%d"),
						this.id,
						basename
					)
				);
				
				// Copy file synchronously (GLib.File.copy() is synchronous, called from async method)
				var source_file = GLib.File.new_for_path(this.path);
				var backup_file = GLib.File.new_for_path(this.backup_path);
				source_file.copy(
					backup_file,
					GLib.FileCopyFlags.OVERWRITE,
					null,
					null
				);
				
				// Note: cleanup_old_backups() should be called separately with db and config
				// (e.g., on startup or periodically) - not called here since we don't have config access
			} catch (GLib.Error e) {
				GLib.warning("FileHistory.create_backup: Failed to create backup for %s: %s", 
					this.path, e.message);
				throw e;
			}
		}
		
		/**
		 * Save FileHistory record to database.
		 * 
		 * @throws Error if database insert fails
		 */
		private async void save_to_db() throws Error
		{
			var sq = FileHistory.query(this.db);
			if (this.id == 0) {
				// Insert new record
				this.id = sq.insert(this);
			} else {
				// Update existing record
				sq.updateById(this);
			}
		}
		
		/**
		 * Delete the backup file from disk.
		 * 
		 * Removes the backup file at backup_path from the filesystem.
		 * If backup_path is empty or the file doesn't exist, does nothing.
		 * 
		 * Uses GLib.FileUtils.unlink() which handles errors silently.
		 */
		public void unlink()
		{
			if (this.backup_path == "") {
				return;
			}
			if (!GLib.FileUtils.test(this.backup_path, GLib.FileTest.EXISTS)) {
				return;
			}
			GLib.debug("FileHistory.unlink: Deleting backup file %s", this.backup_path);
			GLib.FileUtils.unlink(this.backup_path);
		}
		
		/**
		 * Create a query object for file_history table.
		 * 
		 * @param db The database instance
		 * @return A configured Query object ready to use
		 */
		public static SQ.Query<FileHistory> query(SQ.Database db)
		{
			return new SQ.Query<FileHistory>(db, "file_history");
		}
		
		/**
		 * Cleanup old backup files from the backup directory and database records.
		 * 
		 * Removes backup files and database records older than max_deleted_days
		 * from ~/.cache/ollmchat/edited/ and the database.
		 * 
		 * This method:
		 * 1. Selects FileHistory records older than max_deleted_days
		 * 2. Deletes database records (filebase and file_history)
		 * 3. Deletes backup files from disk
		 * 
		 * This should be called on startup or periodically to prevent backup directory
		 * and database from growing indefinitely.
		 * 
		 * Only runs once per day to avoid excessive file system and database operations.
		 * 
		 * @param db Database instance (required)
		 * @param max_deleted_days Number of days to retain deleted file records (default: 30 if <= 0)
		 */
		public static async void cleanup_old_backups(SQ.Database db, int max_deleted_days = 30)
		{
			var now = new GLib.DateTime.now_local().to_unix();
			
			if (last_cleanup_timestamp > now - (24 * 60 * 60)) {
				return;
			}
			
			last_cleanup_timestamp = now;
			
			// Calculate cutoff timestamp based on max_deleted_days
			var cutoff_timestamp = new GLib.DateTime.now_local().add_days(
				-1 * (max_deleted_days > 0 ? max_deleted_days : 30)
			).to_unix().to_string();
			
			// Step 1: Select FileHistory records older than max_deleted_days
			var old_records = new Gee.ArrayList<FileHistory>();
			try {
				yield FileHistory.query(db).select_async(
					"WHERE timestamp < " + cutoff_timestamp, old_records);
			} catch (GLib.Error e) {
				GLib.warning("FileHistory.cleanup_old_backups: Failed to select old records: %s", e.message);
				return;
			}
			
			if (old_records.size == 0) {
				// No old records to clean up
				return;
			}
			
			// Step 2: Delete database records (before deleting files from disk)
			string errmsg;
			
			// Delete filebase records for deleted files (where delete_id points to old FileHistory records)
			if (Sqlite.OK != db.db.exec("""
				DELETE FROM 
					filebase 
				WHERE 
				delete_id IN (
					SELECT 
						id 
					FROM 
						file_history 
					WHERE 
						timestamp < """ + cutoff_timestamp + """
				)"""	
				, null, out errmsg)) {
				GLib.warning("FileHistory.cleanup_old_backups: Failed to delete filebase records: %s", errmsg);
				return;
			}
			
			// Delete all old FileHistory records (added, modified, deleted - no filtering by change_type needed)
			if (Sqlite.OK != db.db.exec(
				"""
				DELETE FROM 
					file_history 
				WHERE 
					timestamp < """ + cutoff_timestamp, null, out errmsg)) {
				GLib.warning("FileHistory.cleanup_old_backups: Failed to delete file_history records: %s", errmsg);
				return;
			}
			
			// Step 3: Delete backup files from disk (only if database deletion succeeded)
			// Iterate through FileHistory objects from Step 1 (we already have them in old_records)
			foreach (var history in old_records) {
				history.unlink();
			}
		}
		
		/**
		 * Initialize file_history table in database.
		 * 
		 * @param db Database instance
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			var query = "CREATE TABLE IF NOT EXISTS file_history (" +
				"id INTEGER PRIMARY KEY, " +
				"path TEXT NOT NULL DEFAULT '', " +
				"filebase_id INT64 NOT NULL DEFAULT 0, " +
				"timestamp INT64 NOT NULL DEFAULT 0, " +
				"change_type TEXT NOT NULL DEFAULT '', " +
				"base_type TEXT NOT NULL DEFAULT '', " +
				"backup_path TEXT NOT NULL DEFAULT '', " +
				"status INTEGER NOT NULL DEFAULT 0, " +
				"alias_target TEXT NOT NULL DEFAULT '', " +
				"moved_to TEXT NOT NULL DEFAULT '', " +
				"moved_from TEXT NOT NULL DEFAULT '', " +
				"agent_id INTEGER NOT NULL DEFAULT 0" +
				");";
			if (Sqlite.OK != db.db.exec(query, null, out errmsg)) {
				GLib.warning("Failed to create file_history table: %s", db.db.errmsg());
			}
		}
	}
}
