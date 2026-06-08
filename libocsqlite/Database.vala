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
	 * 
	 * Thread safety is ensured via a mutex that protects all database operations,
	 * allowing safe concurrent access from multiple threads (e.g., main thread
	 * and background async query threads).
	 */
	public class Database {
	
		/**
		 * The underlying SQLite database connection.
		 */
		public Sqlite.Database db;
		
		/**
		 * Mutex to protect database operations from concurrent access.
		 * All operations that use `db` must lock this mutex first.
		 */
		public GLib.Mutex db_mutex = GLib.Mutex();
		
		/**
		 * The filename used for backup and restore operations.
		 */
		public string filename { get; private set; }
		
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
		 * Steps remaining before a deferred disk backup runs (reset to 5 on each
		 * coalesced backupDB request while a timer is armed).
		 */
		public int countdown { get; private set; default = 0; }

		/**
		 * GLib timeout source id for the repeating backup countdown tick.
		 * Zero when no timer is armed.
		 */
		public uint countdown_id { get; private set; default = 0; }

		/**
		 * Unix time of the last successful disk backup (backup_real).
		 * Zero before any backup has completed.
		 */
		public int64 last_backup { get; private set; default = 0; }
		
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
			this.filename = filename;
			schema_cache = new Gee.HashMap<string,Gee.ArrayList<Schema>>();
			Sqlite.config(Sqlite.Config.SERIALIZED);
			
			if (!this.load_from_file()) {
				// Database loaded from file
				Sqlite.Database.open(":memory:", out db);
			}
			
			this.setup_autosave(autosave);
		}
		
		/**
		 * Loads database from file into memory if file exists and is non-empty.
		 * 
		 * @return true if database was loaded from file, false otherwise
		 */
		private bool load_from_file()
		{
			var exists = GLib.FileUtils.test(this.filename, GLib.FileTest.EXISTS);
			if (!exists) {
				return false;
			}
			
			var file = GLib.File.new_for_path(this.filename);
			GLib.FileInfo info;
			try {
				info = file.query_info(GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE);
				if (info.get_size() == 0) {
					// Delete zero-size file
					GLib.FileUtils.remove(this.filename);
					return false;
				}
			} catch (GLib.Error e) {
				return false;
			}
			
			// Note: db_mutex not needed here as this is only called from constructor
			// before any other operations, but we'll protect it anyway for safety
			db_mutex.lock();
			Sqlite.Database filedb;
			Sqlite.Database.open(this.filename, out filedb);
			Sqlite.Database.open(":memory:", out db);
			var b = new Sqlite.Backup(db, "main", filedb, "main");
			b.step(-1);
			db_mutex.unlock();
			
			return true;
		}
		
		/**
		 * Sets up periodic autosave timer if enabled.
		 * 
		 * @param autosave Whether to enable autosave
		 */
		private void setup_autosave(bool autosave)
		{
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
		 * Request a disk backup of the in-memory database.
		 *
		 * Coalesces rapid calls: if last_backup is older than 20 seconds,
		 * {@link backup_real} runs immediately. While a countdown timer is armed,
		 * only resets countdown. Otherwise arms a 500 ms repeating tick;
		 * when countdown reaches zero, {@link backup_real} runs.
		 */
		public void backupDB()
		{
			GLib.debug("disk backup requested");
			if (new GLib.DateTime.now_local().to_unix() - this.last_backup > 20) {
				if (this.countdown_id != 0) {
					GLib.Source.remove(this.countdown_id);
					this.countdown_id = 0;
				}
				this.countdown = -1;
				GLib.debug("disk backup forced max age");
				this.backup_real();
				return;
			}
			if (this.countdown_id != 0) {
				this.countdown = 5;
				GLib.debug("disk backup coalesced countdown=%d", this.countdown);
				return;
			}
			GLib.debug("disk backup countdown armed");
			this.countdown_id = GLib.Timeout.add(500, () => {
				this.countdown--;
				if (this.countdown > 0) {
					return true;
				}
				this.countdown_id = 0;
				GLib.debug("disk backup countdown finished");
				this.backup_real();
				return false;
			});
			this.countdown = 5;
		}

		/**
		 * Write the in-memory database to {@link filename} now (mutex,
		 * Sqlite.Backup, atomic rename). Updates last_backup on success.
		 */
		public void backup_real()
		{
			if (this.db == null) {
				return;
			}
			GLib.debug("disk backup writing path=%s", this.filename);
			this.db_mutex.lock();
			try {
				var new_filename = this.filename + ".new";
				Sqlite.Database filedb;
				Sqlite.Database.open(new_filename, out filedb);
				var b = new Sqlite.Backup(filedb, "main", this.db, "main");
				b.step(-1);
				var new_file = GLib.File.new_for_path(new_filename);
				GLib.FileInfo info;
				try {
					info = new_file.query_info(
						GLib.FileAttribute.STANDARD_SIZE,
						GLib.FileQueryInfoFlags.NONE);
					if (info.get_size() == 0) {
						GLib.warning(
							"Backup file %s was not created properly (size: 0)",
							new_filename);
						GLib.FileUtils.remove(new_filename);
						return;
					}
				} catch (GLib.Error e) {
					GLib.warning(
						"Backup file %s was not created properly: %s",
						new_filename,
						e.message);
					GLib.FileUtils.remove(new_filename);
					return;
				}
				GLib.FileUtils.rename(new_filename, this.filename);
				this.is_dirty = false;
				this.last_backup = new GLib.DateTime.now_local().to_unix();
				GLib.debug("disk backup done path=%s", this.filename);
			} catch (GLib.Error e) {
				GLib.warning("Error during database backup: %s", e.message);
			} finally {
				this.db_mutex.unlock();
			}
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
			//GLib.debug("EXEC %s", q);
			db_mutex.lock();
			string errmsg;
			if (Sqlite.OK != db.exec(q, null, out errmsg)) {
				//GLib.debug("error %s", db.errmsg());
			}
			db_mutex.unlock();
		}
		
	}
}
		