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

namespace OLLMchat.History
{
	/**
	 * Manager for chat history persistence.
	 * 
	 * Handles saving and loading chat sessions to/from disk and SQLite database.
	 * Manages the history directory structure and provides methods for session management.
	 */
	public class Manager : Object
	{
		public string history_dir { get; private set; }
		public Gee.ArrayList<Session> sessions { get; private set; default = new Gee.ArrayList<Session>(); }
		public SQ.Database db { get; private set; }
		
		/**
		 * Constructor.
		 * 
		 * @param directory Directory where history files are stored (must exist, caller is responsible)
		 */
		public Manager(string directory)
		{
			if (directory == "") {
				GLib.error("Manager: directory parameter cannot be empty");
			}
			
			// Use provided directory and append "history"
			this.history_dir = GLib.Path.build_filename(directory, "history");
			
			// Verify directory exists - caller is responsible for creating it
			var dir = GLib.File.new_for_path(this.history_dir);
			if (!dir.query_exists()) {
				GLib.error("Manager: history directory does not exist: %s", this.history_dir);
			}
			
			// Create database instance
			var db_filename = GLib.Path.build_filename(this.history_dir, "history.db");
			this.db = new SQ.Database(db_filename);
			
			// Initialize sessions table in database
			Session.initDB(this.db);
		}
		
		/**
		 * Register a Client to monitor for chat events.
		 * Connects to Client signals to detect when new chats are created or messages are added.
		 * 
		 * @param client The Client to monitor
		 */
		public void register_client(Client client)
		{
			// TODO: Connect to Client signals when integration is implemented (section 1.3)
			// For now, this is a placeholder
		}
		
		/**
		 * Load all chat sessions from SQLite database and store in manager.
		 */
		public void load_sessions()
		{
			this.sessions.clear();
			var sq = new SQ.Query<Session>(this.db, "session");
			sq.select("ORDER BY updated_at DESC", this.sessions);
		}
	}
}

