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

namespace OLLMfiles
{
	/**
	 * Abstract base class providing common properties and methods for files and folders.
	 * 
	 * FileBase is the foundation of the file system hierarchy:
	 * 
	 *  * File: Represents individual files
	 *  * Folder: Represents directories (can also be projects when is_project = true)
	 *  * FileAlias: Represents symlinks/aliases to files or folders
	 * 
	 * == ID Semantics ==
	 * 
	 *  * id = 0: New file (will be inserted into database)
	 *  * id > 0: Existing file (will be updated in database)
	 *  * id < 0: Fake file (not in database, skips DB operations)
	 * 
	 * Fake files are used for accessing files outside the project scope.
	 * They skip database operations in saveToDB().
	 */
	public abstract class FileBase : Object
	{
		/**
		 * Database ID.
		 * 
		 * Semantics: 0 = new file (will be inserted), >0 = existing file (will be updated),
		 * <0 = fake file (not in database, skips DB operations).
		 */
		public int64 id { get; set; default = 0; }
		
		/**
		 * File/folder path.
		 */
		public string path { get; set; default = ""; }
		
		/**
		 * Parent folder ID for database storage.
		 */
		public int64 parent_id { get; set; default = 0; }
		
		/**
		 * Reference to parent folder (nullable for root folders/projects).
		 */
		public Folder? parent { get; set; default = null; }
		
		/**
		 * Whether this is an alias/symlink.
		 * Computed property: Returns true if this is a FileAlias.
		 */
		public bool is_alias {
			get {
				return (this is FileAlias);
			}
		}
		
		/**
		 * Reference to the FileBase object this alias points to (nullable, only set when is_alias = true).
		 * This is the actual object reference, loaded from database via points_to_id.
		 */
		public FileBase? points_to { get; set; default = null; }
		
		/**
		 * The ID of the FileBase object this alias points to (foreign key reference).
		 */
		public int64 points_to_id { get; set; default = 0; }
		
		/**
		 * The path of the FileBase object this alias points to (for database queries).
		 * This is stored in the database to enable efficient path-based lookups.
		 */
		public string target_path { get; set; default = ""; }
		
		/**
		 * Reference to ProjectManager.
		 * 
		 */
		public  ProjectManager manager { get; construct; }
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		protected FileBase(ProjectManager manager)
		{
			Object(manager: manager);
		}
		
		/**
		 * Icon name for binding in lists.
		 * Returns icon_name if set, otherwise a default based on type.
		 */
		public virtual string icon_name {
			get { return "folder"; }
			set {}
		}
 		
		/**
		 * Display name for binding in lists.
		 */
		public string display_name { get; set; default = ""; }
		
		/**
		 * Basename derived from path (for property binding).
		 */
		public string path_basename {
			owned get { return GLib.Path.get_basename(this.path); }
		}
		
		/**
		 * Display text with status indicators.
		 * Base implementation just returns display_name.
		 */
		public virtual string display_with_indicators {
			get { return this.display_name; 	}
		}
		
		/**
		 * Tooltip text for binding in lists.
		 */
		public string tooltip { get; set; default = ""; }
		
		/**
		 * Get modification time on disk (Unix timestamp).
		 * 
		 * @return Modification time as Unix timestamp, or 0 if unavailable
		 */
		public int64 mtime_on_disk()
		{
			var file = GLib.File.new_for_path(this.path);
			if (!file.query_exists()) {
				return 0;
			}
			
			try {
				var info = file.query_info(
					GLib.FileAttribute.TIME_MODIFIED,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
				var date_time = info.get_modification_date_time();
				return date_time.to_unix();
			} catch (GLib.Error e) {
				return 0;
			}
		}
		
		/**
		 * Base type identifier for serialization and database storage.
		 * 
		 * Type identifiers: "f" = File, "d" = Folder/Directory, "fa" = FileAlias (file alias),
		 * "da" = FileAlias (folder alias). Projects are folders with is_project = true
		 * (no separate "p" type).
		 */
		public string base_type { get; set; default = ""; }
		
		/**
		 * Whether this is the currently active/viewed item.
		 */
		public bool is_active { get; set; default = false; }
		
		/**
		 * Programming language (optional, for files).
		 */
		public string language { get; set; default = ""; }
		
		/**
		 * Last cursor line number (stored in database, default: 0).
		 */
		public int cursor_line { get; set; default = 0; }
		
		/**
		 * Last cursor character offset (stored in database, default: 0).
		 */
		public int cursor_offset { get; set; default = 0; }
		
		/**
		 * Last scroll position (stored in database, optional, default: 0).
		 */
		public int scroll_position { get; set; default = 0; }
		
		/**
		 * Filename of last approved copy (default: empty string).
		 */
		public string last_approved_copy_path { get; set; default = ""; }
		
		/**
		 * Whether the file needs approval (inverted from is_approved).
		 * true = needs approval, false = approved.
		 */
		public bool needs_approval { get; set; default = true; }
		
		/**
		 * Whether the file has unsaved changes.
		 */
		public bool is_unsaved { get; set; default = false; }
		
		/**
		 * Whether this folder represents a project (stored in database, default: false).
		 */
		public bool is_project { get; set; default = false; }
		
		/**
		 * Unix timestamp of last view (stored in database, default: 0).
		 */
		public int64 last_viewed { get; set; default = 0; }
		
		/**
		 * Unix timestamp of last modification (stored in database, default: 0).
		 */
		public int64 last_modified { get; set; default = 0; }
		
		/**
		 * Whether this file is ignored by git (stored in database, default: false).
		 */
		public bool is_ignored { get; set; default = false; }
		
		/**
		 * Whether this file is a text file (stored in database, default: false).
		 */
		public bool is_text { get; set; default = false; }
		
		/**
		 * Whether this folder is a git repository (stored in database, default: -1).
		 * -1 = not checked, 0 = checked and not a repo, 1 = it is a repo.
		 */
		public int is_repo { get; set; default = -1; }
		
		/**
		 * Unix timestamp of last vector scan (stored in database, default: 0).
		 * For files: timestamp when vector scan completed (after successful vectorization).
		 * For folders: timestamp when vector scan started (to prevent re-recursion during same scan).
		 */
		public int64 last_vector_scan { get; set; default = 0; }
		
		/**
		 * Initialize database table for filebase objects.
		 */
		public static void initDB(SQ.Database db)
		{
			string errmsg;
			var query = "CREATE TABLE IF NOT EXISTS filebase (" +
				"id INTEGER PRIMARY KEY, " +
				"path TEXT NOT NULL DEFAULT '', " +
				"parent_id INT64 NOT NULL DEFAULT 0, " +
				"base_type TEXT NOT NULL DEFAULT '', " +
				"language TEXT, " +
				"last_approved_copy_path TEXT NOT NULL DEFAULT '', " +
				"is_active INTEGER NOT NULL DEFAULT 0, " +
				"cursor_line INTEGER NOT NULL DEFAULT 0, " +
				"cursor_offset INTEGER NOT NULL DEFAULT 0, " +
				"scroll_position INTEGER NOT NULL DEFAULT 0, " +
				"last_viewed INT64 NOT NULL DEFAULT 0, " +
				"last_modified INT64 NOT NULL DEFAULT 0, " +
				"points_to_id INT64 NOT NULL DEFAULT 0, " +
				"target_path TEXT NOT NULL DEFAULT '', " +
				"is_project INTEGER NOT NULL DEFAULT 0, " +
				"is_ignored INTEGER NOT NULL DEFAULT 0, " +
				"is_text INTEGER NOT NULL DEFAULT 0, " +
				"is_repo INTEGER NOT NULL DEFAULT -1, " +
				"last_vector_scan INT64 NOT NULL DEFAULT 0" +
				");";
			if (Sqlite.OK != db.db.exec(query, null, out errmsg)) {
				GLib.warning("Failed to create filebase table: %s", db.db.errmsg());
			}
			
			// Migrate existing databases: add last_vector_scan column if it doesn't exist
			var migrate_query = "ALTER TABLE filebase ADD COLUMN last_vector_scan INT64 NOT NULL DEFAULT 0";
			if (Sqlite.OK != db.db.exec(migrate_query, null, out errmsg)) {
				// Column might already exist, which is fine
				if (!errmsg.contains("duplicate column name")) {
					GLib.debug("Migration note (may be expected): %s", errmsg);
				}
			}
		}
		
		/**
		 * Create a query object for filebase table with typemap configured.
		 * 
		 * @param db The database instance
		 * @param manager The ProjectManager instance (required for constructing objects)
		 * @return A configured Query object ready to use
		 */
		public static SQ.Query<FileBase> query(SQ.Database db, ProjectManager manager)
		{
			// Set up property_names and property_values to pass manager to constructors
			var property_names = new string[] { "manager" };
			var property_values = new Value[] { manager };
			var query = new SQ.Query<FileBase>.with_properties(db, "filebase", property_names, property_values);
			query.typemap = new Gee.HashMap<string, Type>();
			// Note: Projects are now folders with is_project = true, no separate "p" type
			query.typemap["f"] = typeof(File);
			query.typemap["d"] = typeof(Folder);
			query.typemap["fa"] = typeof(FileAlias);
			query.typemap["da"] = typeof(FileAlias);
			query.typekey = "base_type";
			return query;
		}
		
		/**
		 * Compare this FileBase with another to determine if they represent the same item.
		 * Used to check if a newly read file from filesystem matches the DB/memory version.
		 * 
		 * @param other The other FileBase to compare with (typically the new filesystem item)
		 * @return true if they represent the same item, false otherwise
		 */
		public bool compare(FileBase other)
		{
			// Must have same path
			if (this.path != other.path) {
				return false;
			}
			
			// If both have IDs, they must match (same DB record)
			if (this.base_type != other.base_type) {
				return false;
			}
			// not sure if other tests are needed.
			
			// Same path is sufficient if IDs aren't set
			return true;
		}
		
		/**
		 * Copy database-preserved fields from this object to another.
		 * 
		 * Used when updating from filesystem: preserves DB fields like id, is_active,
		 * cursor positions, etc. that shouldn't be overwritten by filesystem scan.
		 * 
		 * == Copied Fields ==
		 * 
		 * Copies all database-preserved fields (excluding filesystem-derived fields):
		 * id, is_active, last_viewed, last_modified, language, last_approved_copy_path,
		 * cursor_line, cursor_offset, scroll_position, is_project, is_ignored, is_text,
		 * is_repo, last_vector_scan.
		 * 
		 * Note: base_type is not copied as it's determined by object type and should match.
		 * 
		 * @param target The target object to copy fields to (typically the new filesystem item)
		 */
		public virtual void copy_db_fields_to(FileBase target)
		{
			// Copy database-preserved fields (excluding filesystem-derived: path, parent_id, target_path)
			// Note: base_type is not copied as it's determined by object type and should match
			target.id = this.id;
			target.is_active = this.is_active;
			target.last_viewed = this.last_viewed;
			target.last_modified = this.last_modified;
			
			// Copy all database fields (now all in FileBase)
			target.language = this.language;
			target.last_approved_copy_path = this.last_approved_copy_path;
			target.cursor_line = this.cursor_line;
			target.cursor_offset = this.cursor_offset;
			target.scroll_position = this.scroll_position;
			target.is_project = this.is_project;
			target.is_ignored = this.is_ignored;
			target.is_text = this.is_text;
			target.is_repo = this.is_repo;
			target.last_vector_scan = this.last_vector_scan;
		}
		
		// Static counter for tracking saveToDB calls
		private static int64 saveToDB_call_count = 0;
		
		/**
		 * Save filebase object to SQLite database.
		 * 
		 * == ID Semantics ==
		 * 
		 *  * id = 0: New file (inserts into database, sets this.id to new ID)
		 *  * id > 0: Existing file (updates database record)
		 *  * id < 0: Fake file (skips database operations, returns early)
		 * 
		 * == Update Modes ==
		 * 
		 *  * If new_values is provided and this.id > 0: Uses updateOld to only update changed fields
		 *  * Otherwise: Performs insert (id = 0) or full update (id > 0)
		 * 
		 * == Best Practices ==
		 * 
		 *  * Set sync = false when saving multiple items to avoid frequent disk writes
		 *  * Fake files (id < 0) automatically skip database operations
		 *  * New files (id = 0) are automatically inserted and assigned an ID
		 * 
		 * @param db The database instance to save to
		 * @param new_values Optional new values object. If provided and this.id > 0,
		 *                   uses updateOld to only update changed fields. Otherwise
		 *                   performs insert or full update.
		 * @param sync If true, backup the in-memory database to disk immediately. 
		 *              Set to false when saving multiple items to avoid frequent disk writes.
		 */
		public void saveToDB(SQ.Database db, FileBase? new_values = null, bool sync = true)
		{
			// Skip DB operations for fake files (id < 0 indicates not in database)
			// id = -1: fake file (ignore), id = 0: new file (insert), id > 0: existing file (update)
			if (this.id < 0) {
				GLib.debug("FileBase.saveToDB: Skipping DB operation for fake file (id=%lld, path='%s')", 
					this.id, this.path);
				return;
			}
			
			var sq = new SQ.Query<FileBase>(db, "filebase");
			// At this point, id >= 0 (fake files with id < 0 already returned above)
			// id = 0: new file (insert), id > 0: existing file (update)
			if (this.id == 0) {
				// New file - insert into database
				GLib.debug("INSERT new file path='%s'", this.path);
				this.id = sq.insert(this);
				this.manager.file_cache.set(this.path, this);
			} else {
				if (new_values != null) {
					var updated = sq.updateOld(this, new_values);
					if (updated) {
						GLib.debug("UPDATE (changed fields only) id=%d path='%s'", (int)this.id, this.path);
					}
				} else {
					GLib.debug("UPDATE (all fields) id=%d path='%s'", (int)this.id, this.path);
					sq.updateById(this);
				}
			}
			// Backup in-memory database to disk only if sync is true
			if (sync) {
				db.backupDB();
			}
		}
		
		/**
		 * Remove filebase object from SQLite database.
		 * 
		 * @param db The database instance
		 */
		public void removeFromDB(SQ.Database db)
		{
			if (this.id <= 0) {
				return;
			}
			var sq = new SQ.Query<FileBase>(db, "filebase");
			sq.deleteId(this.id);
			this.manager.file_cache.unset(this.path);
		}
		
		/**
		 * Get target info for a given path.
		 * Only queries the path - does not resolve symlinks recursively.
		 * 
		 * @param target_path The path to query
		 * @return FileInfo for the path, or null if target doesn't exist or query fails
		 */
		public  GLib.FileInfo? get_target_info(string target_path)
		{
			var target_file_obj = GLib.File.new_for_path(target_path);
			if (!target_file_obj.query_exists()) {
				return null; // Target doesn't exist
			}
			
			try {
				return target_file_obj.query_info(
					GLib.FileAttribute.STANDARD_TYPE + "," +
					GLib.FileAttribute.STANDARD_IS_SYMLINK + "," +
					GLib.FileAttribute.STANDARD_SYMLINK_TARGET,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("Failed to get target info for %s: %s", target_path, e.message);
				return null;
			}
		}
		
		
		
	}
}
