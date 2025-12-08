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
		public SessionBase session { get; internal set; }
		
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
		public signal void tool_message(OLLMchat.Message message);
		public signal void message_created(Message m, ChatContentInterface? content_interface);
		
		 
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
			
			// Reuse the same tools, just set the client to the new value (leave active the same)
			foreach (var tool in this.base_client.tools.values) {
				//tool.active = this.session.client.tools.get(tool.name).active;
				client.addTool(tool);
			}
			
			// Properties NOT copied (and why):
			// - streaming_response: Session-specific streaming state
			// - session: Not applicable to new client instance
			// - tools: Reused above (just set client property)
			
			return client;
		}
		
		/**
		 * Switches to a new session, deactivating the current one and activating the new one.
		 * 
		 * When switching to EmptySession, preserves model and tool states from the previous session.
		 * Loads the session if needed (e.g., for SessionPlaceholder).
		 * 
		 * @param session The session to switch to
		 * @throws Error if loading fails
		 */
		public async void switch_to_session(SessionBase session) throws Error
		{
			// Store previous session's client for state preservation
			 
			// Deactivate current session
			this.session.deactivate();
			
			// Load session data if needed (no-op for already loaded sessions)
			// For SessionPlaceholder, this returns a new Session object
			// For Session, this returns the same session
			SessionBase? loaded_session = yield session.load();
			
			if (loaded_session == null) {
				throw new GLib.IOError.FAILED("Session load returned null");
			}
			
			// If switching to EmptySession, copy model and tool states from previous session
			 
			  
			// Activate new session
			this.session = loaded_session;
			loaded_session.activate();
			
			// Emit signal for UI updates
			this.session_activated(loaded_session);
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
			
			// Prepare property names and values for Object.new_with_properties
			// We pass manager so SessionPlaceholder can access it during construction
			string[] property_names = { "manager" };
			Value[] property_values = { Value(typeof(Manager)) };
			property_values[0].set_object(this);
			
			var sq = new SQ.Query<SessionPlaceholder>.with_properties(this.db, "session", property_names, property_values);
			
			var placeholder_list = new Gee.ArrayList<SessionPlaceholder>();
			sq.select("ORDER BY updated_at_timestamp DESC", placeholder_list);
			
			// Add placeholders to sessions list and set manager
			foreach (var placeholder in placeholder_list) {
				this.sessions.add(placeholder);
			}
		}
	}
}

