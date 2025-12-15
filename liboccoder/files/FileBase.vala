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

namespace OLLMcoder.Files
{
	/**
	 * Base class for File and Folder objects.
	 * 
	 * Provides common properties and methods shared by both files and folders.
	 */
	public abstract class FileBase : Object
	{
		/**
		 * Database ID.
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
		public  OLLMcoder.ProjectManager manager { get; construct; }
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		protected FileBase(OLLMcoder.ProjectManager manager)
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
		 * Base type identifier for serialization.
		 * 
		 * Returns "f" for File, "d" for Folder/Directory, "fa" for FileAlias.
		 * Projects are folders with is_project = true (no separate "p" type).
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
				"is_project INTEGER NOT NULL DEFAULT 0" +
				");";
			if (Sqlite.OK != db.db.exec(query, null, out errmsg)) {
				GLib.warning("Failed to create filebase table: %s", db.db.errmsg());
			}
		}
		
		/**
		 * Create a query object for filebase table with typemap configured.
		 * 
		 * @param db The database instance
		 * @return A configured Query object ready to use
		 */
		public static SQ.Query<FileBase> query(SQ.Database db)
		{
			var query = new SQ.Query<FileBase>(db, "filebase");
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
		 * Used when updating from filesystem: preserves DB fields like id, is_active,
		 * cursor positions, etc. that shouldn't be overwritten by filesystem scan.
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
		}
		
		/**
		 * Save filebase object to SQLite database.
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
			var sq = new SQ.Query<FileBase>(db, "filebase");
			if (this.id <= 0) {
				this.id = sq.insert(this);
				this.manager.file_cache.set(this.path, this);
			} else {
				if (new_values != null) {
					sq.updateOld(this, new_values);
				} else {
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
