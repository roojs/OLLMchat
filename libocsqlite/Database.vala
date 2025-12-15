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

namespace SQ {
	
	/**
	 * Manages SQLite database connections with in-memory storage and file backup.
	 * 
	 * The Database class provides a wrapper around SQLite that uses an in-memory
	 * database for performance, with the ability to backup to and restore from
	 * a file. It maintains a schema cache to avoid repeated schema queries.
	 * 
	 * The database is configured for serialized access mode, allowing safe
	 * multi-threaded access.
	 */
	public class Database {
	
		/**
		 * The underlying SQLite database connection.
		 */
		public Sqlite.Database db;
		
		/**
		 * The filename used for backup and restore operations.
		 */
		private string _filename;
		
		/**
		 * Cache of table schemas to avoid repeated PRAGMA queries.
		 */
		public Gee.HashMap<string,Gee.ArrayList<Schema>> schema_cache;
		
		/**
		 * Whether the database has unsaved changes (dirty flag).
		 */
		public bool is_dirty { get; set; default = false; }
		
		/**
		 * Timeout source for periodic save checks.
		 */
		private uint? save_timeout_id = null;
		
		/**
		 * Creates a new Database instance.
		 * 
		 * If the file exists and is non-empty, the database is restored from
		 * the file into memory. Otherwise, a new in-memory database is created.
		 * 
		 * @param filename The path to the database file for backup/restore
		 * @param autosave Whether to automatically save periodically (default: false)
		 */
		public Database(string filename, bool autosave = false)
		{
			_filename = filename;
			schema_cache = new Gee.HashMap<string,Gee.ArrayList<Schema>>();
			Sqlite.config(Sqlite.Config.SERIALIZED);
			var exists = GLib.FileUtils.test(filename, GLib.FileTest.EXISTS);
			if (exists) {
				Posix.Stat buf;
				Posix.stat(filename, out buf);
				if (buf.st_size > 0) {
					Sqlite.Database filedb;
					Sqlite.Database.open(filename, out filedb);
					Sqlite.Database.open(":memory:", out db);
					var b = new Sqlite.Backup(db, "main", filedb, "main");
					b.step(-1);
					// Start periodic save timer if autosave is enabled
					if (!autosave) {
						return;
					}
					this.save_timeout_id = GLib.Timeout.add_seconds(60, () => {
						if (this.is_dirty) {
							this.backupDB();
						}
						return true; // Continue timer
					});
					return;
				}
			}
			Sqlite.Database.open(":memory:", out db);
			
			// Start periodic save timer if autosave is enabled
			if (!autosave) {
				return;
			}
			this.save_timeout_id = GLib.Timeout.add_seconds(60, () => {
				if (this.is_dirty) {
					this.backupDB();
				}
				return true; // Continue timer
			});
		}
		
		/**
		 * Backs up the in-memory database to the file.
		 * 
		 * This method saves the current state of the in-memory database to
		 * the file specified in the constructor. If the database is not open,
		 * this method does nothing.
		 * 
		 * After saving, the is_dirty flag is reset to false.
		 */
		public void backupDB()
		{
			if (db == null) {
				GLib.debug("database not open = not saving");
				return;
			}
			Sqlite.Database filedb;
			Sqlite.Database.open(_filename, out filedb);
			var b = new Sqlite.Backup(filedb, "main", db, "main");
			b.step(-1);
			this.is_dirty = false;
		}
		 
		/**
		 * Executes a raw SQL query.
		 * 
		 * This method executes a SQL statement that doesn't return results
		 * (e.g., CREATE TABLE, INSERT, UPDATE, DELETE).
		 * 
		 * @param q The SQL query string to execute
		 */
		public void exec(string q) 
		{
			GLib.debug("EXEC %s", q);
			string errmsg;
			if (Sqlite.OK != db.exec(q, null, out errmsg)) {
				GLib.debug("error %s", db.errmsg());
			}
		}
	}
}
		