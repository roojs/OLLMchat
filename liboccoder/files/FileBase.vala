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
		public virtual string display_text_with_indicators {
			get {
				return this.display_name;
			}
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
		 * Returns "p" for Project, "f" for File, "d" for Folder/Directory.
		 */
		public string base_type { get; set; default = ""; }
		
		/**
		 * Whether this is the currently active/viewed item.
		 */
		public bool is_active { get; set; default = false; }
		
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
				"scroll_position REAL NOT NULL DEFAULT 0.0, " +
				"last_viewed INT64 NOT NULL DEFAULT 0" +
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
			query.typemap["p"] = typeof(Project);
			query.typemap["f"] = typeof(File);
			query.typemap["d"] = typeof(Folder);
			query.typekey = "base_type";
			return query;
		}
		
		/**
		 * Save filebase object to SQLite database.
		 * 
		 * @param db The database instance to save to
		 * @param sync If true, backup the in-memory database to disk immediately. 
		 *              Set to false when saving multiple items to avoid frequent disk writes.
		 */
		public void saveToDB(SQ.Database db, bool sync = true)
		{
			var sq = new SQ.Query<FileBase>(db, "filebase");
			if (this.id <= 0) {
				this.id = sq.insert(this);
			} else {
				sq.updateById(this);
			}
			// Backup in-memory database to disk only if sync is true
			if (sync) {
				db.backupDB();
			}
		}
	}
}
