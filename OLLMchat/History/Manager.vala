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
		public TitleGenerator? title_generator { get; set; default = null; }
		
		// Signal emitted when a new session is added (for UI updates)
		public signal void session_added(Session session);
		
		// HashMap to track sessions by fid
		private Gee.HashMap<string, Session> sessions_by_fid = new Gee.HashMap<string, Session>();
		
		/**
		 * Constructor.
		 * 
		 * @param directory Directory where history files are stored (will create history subdirectory if needed)
		 */
		public Manager(string directory)
		{
			if (directory == "") {
				GLib.error("Manager: directory parameter cannot be empty");
			}
			
			// Use provided directory and append "history"
			this.history_dir = GLib.Path.build_filename(directory, "history");
			
			// Create directory if it doesn't exist
			var dir = GLib.File.new_for_path(this.history_dir);
			if (!dir.query_exists()) {
				try {
					dir.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					GLib.error("Manager: failed to create history directory %s: %s", this.history_dir, e.message);
				}
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
			// Connect to chat_send signal to detect new chat sessions
			client.chat_send.connect((chat) => {
				// Check if session already exists for this chat
				var existing_session = this.sessions_by_fid.get(chat.fid);
				if (existing_session != null) {
					// Session already exists - save it to update title/reply count
					existing_session.save_async.begin();
					// Notify that display properties may have changed
					existing_session.notify_property("display_info");
					existing_session.notify_property("display_title");
					return;
				}
				
				// Create new session with chat and manager
				var session = new Session(chat, this);
				
				// Store in HashMap
				this.sessions_by_fid.set(chat.fid, session);
				
				// Add to sessions list
				this.sessions.add(session);
				
				// Emit signal for UI updates (HistoryBrowser can listen to this)
				this.session_added(session);
				
				// Write initial session to DB and file
				session.save_async.begin();
			});
			
			// Connect to stream_chunk to detect response completion
			client.stream_chunk.connect((new_text, is_thinking, response) => {
				// Save when response is done (not streaming, but toolcalls or done response)
				if (!response.done) {
					return;
				}
				// Get session by fid from the chat object
				var session = this.sessions_by_fid.get(response.call.fid);
				if (session == null) {
					return;
				}
				// Save session to DB and file
				session.save_async.begin();
				// Notify that display properties may have changed (reply count updated)
				session.notify_property("display_info");
				session.notify_property("title");
			});
		}
		
		/**
		 * Load all chat sessions from SQLite database and store in manager.
		 */
		public void load_sessions()
		{
			this.sessions.clear();
			var sq = new SQ.Query<Session>(this.db, "session");
			sq.select("ORDER BY updated_at_timestamp DESC", this.sessions);
		}
	}
}

