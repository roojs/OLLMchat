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
		public Gee.ArrayList<SessionBase> sessions { get; private set; default = new Gee.ArrayList<SessionBase>(); }
		public SQ.Database db { get; private set; }
		public TitleGenerator? title_generator { get; set; default = null; }
		public Client base_client { get; private set; }
		public SessionBase? session { get; private set; default = null; }
		
		// Signal emitted when a new session is added (for UI updates)
		public signal void session_added(SessionBase session);
		
		// Signal emitted when a session is removed (for UI updates)
		public signal void session_removed(SessionBase session);
		
		// Signal emitted when a session is activated
		public signal void session_activated(SessionBase session);
		
		// Signals that relay client signals to UI (from active session)
		public signal void chat_send(Call.Chat chat);
		public signal void stream_chunk(string new_text, bool is_thinking, Response.Chat response);
		public signal void stream_content(string new_text, Response.Chat response);
		public signal void stream_start();
		public signal void tool_message(string message, Object? widget = null);
		
		 
		/**
		 * Constructor.
		 * 
		 * @param base_client Base client to use for creating new session clients
		 * @param directory Directory where history files are stored (will create history subdirectory if needed)
		 */
		public Manager(Client base_client, string directory)
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
			
			// Store base client
			this.base_client = base_client;

            this.session = new EmptySession(this);
			this.session.activate(); // contects signals alhtough to nowhere..
		}
		
		/**
		 * Creates a new client instance from the base client.
		 * Copies all properties and creates fresh tool instances.
		 * 
		 * @return A new Client instance with copied properties and fresh tools
		 */
		public Client new_client()
		{
			var client = new Client();
			
			// Copy all properties
			client.url = this.base_client.url;
			client.api_key = this.base_client.api_key;
			client.model = this.base_client.model;
			client.stream = this.base_client.stream;
			client.format = this.base_client.format;
			client.think = this.base_client.think;
			client.keep_alive = this.base_client.keep_alive;
			client.prompt_assistant = this.base_client.prompt_assistant; // Shared reference
			client.permission_provider = this.base_client.permission_provider; // Shared reference - MUST be shared
			client.seed = this.base_client.seed;
			client.temperature = this.base_client.temperature;
			client.top_p = this.base_client.top_p;
			client.top_k = this.base_client.top_k;
			client.num_predict = this.base_client.num_predict;
			client.repeat_penalty = this.base_client.repeat_penalty;
			client.num_ctx = this.base_client.num_ctx;
			client.stop = this.base_client.stop;
			client.timeout = this.base_client.timeout;
			
			// Copy available_models (shared model data)
			foreach (var entry in this.base_client.available_models.entries) {
				client.available_models.set(entry.key, entry.value);
			}
			
			// Create fresh tools using Object.new() with named parameters
			foreach (var tool in this.base_client.tools.values) {
				var tool_type = tool.get_type();
				var new_tool = (Tool.Interface) Object.new(tool_type, client: client);
				client.addTool(new_tool);
			}
			
			// Properties NOT copied (and why):
			// - streaming_response: Session-specific streaming state
			// - session: Not applicable to new client instance
			// - tools: Created fresh above (each session needs its own tool instances)
			
			return client;
		}
		
		/**
		 * Switches to a new session, deactivating the current one and activating the new one.
		 * 
		 * When switching to EmptySession, preserves model and tool states from the previous session.
		 * 
		 * @param session The session to switch to
		 */
		public void switch_to_session(SessionBase session)
		{
			// Store previous session's client for state preservation
			 
			// Deactivate current session
			this.session.deactivate();
			
			// If switching to EmptySession, copy model and tool states from previous session
			if (session is EmptySession) {
			 
				// Copy model
				session.client.model = this.session.client.model;
				session.client.think = this.session.client.think;
				// Copy tool active states (match by tool name)
				foreach (var prev_tool in this.session.client.tools.values) {
					if (!session.client.tools.has_key(prev_tool.name)) {
						continue; //should not happen
					}
					session.client.tools.get(prev_tool.name).active = prev_tool.active;
				}
			}
			
			// Activate new session
			this.session = session;
			session.activate();
			
			// Emit signal for UI updates
			this.session_activated(session);
		}
		
		 
		/**
		 * Creates a new session for a new chat.
		 * 
		 * @return A new Session instance with a fresh client
		 */
		public Session create_new_session()
		{
			var session = new Session(this, new Call.Chat(this.new_client()));
			this.sessions.add(session);
			this.session_added(session);
			
			// When the first chat is created, it will have a fid and will be tracked
			// via on_chat_send handler which will update sessions_by_fid
			
			return session;
		}
		
		/**
		 * Load all chat sessions from SQLite database and store in manager.
		 * Sessions are loaded as SessionPlaceholder instances until load() is called.
		 */
		public void load_sessions()
		{
			this.sessions.clear();
			var sq = new SQ.Query<SessionPlaceholder>(this.db, "session");
			sq.select("ORDER BY updated_at_timestamp DESC", this.sessions);
			
			// Set manager for all loaded sessions
			foreach (var session in this.sessions) {
				session.manager = this;
			}
		}
	}
}

