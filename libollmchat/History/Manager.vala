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
	 * Creates new clients for each session while sharing tools and configuration.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var manager = new History.Manager(history_dir, db, base_client, config);
	 *
	 * // Create new session
	 * var session = yield manager.new_session();
	 *
	 * // Get client for this session (shares tools/config)
	 * var client = manager.session.client;
	 *
	 * // Switch to existing session
	 * yield manager.switch_to_session(existing_session);
	 *
	 * // Save current session
	 * yield manager.save_session();
	 * }}}
	 */
	public class Manager : Object
	{
		public string history_dir { get; private set; }
		public Gee.ArrayList<SessionBase> sessions { 
			get; 
			private set; 
			default = new Gee.ArrayList<SessionBase>((a, b) => {
				return a.id == b.id;
				 
			});
		}
		public SQ.Database db { get; private set; }
		public TitleGenerator title_generator { get; private set; }
		public Client base_client { get; private set; }
		public Settings.Config2 config { get; private set; }
		public SessionBase session { get; internal set; }
		public Gee.HashMap<string, OLLMchat.Prompt.BaseAgent> agents { 
			get; private set; default = new Gee.HashMap<string, OLLMchat.Prompt.BaseAgent>(); 
		}
		
		// Signal emitted when a new session is added (for UI updates)
		public signal void session_added(SessionBase session);
		
		// Signal emitted when a session is removed (for UI updates)
		public signal void session_removed(SessionBase session);
		
		// Signal emitted when a session is replaced (for UI updates)
		// @param index The index in manager.sessions where the replacement occurred
		// @param session The new session that replaced the old one
		public signal void session_replaced(int index, SessionBase session);
		
		// Signal emitted when a session is activated
		public signal void session_activated(SessionBase session);
		
		// Signal emitted when an agent is activated (for UI updates)
		public signal void agent_activated(Prompt.BaseAgent agent);
		
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
		 * @param app ApplicationInterface instance (provides config and data_dir)
		 */
		public Manager(OLLMchat.ApplicationInterface app)
		{
			if (app.data_dir == "") {
				GLib.error("Manager: app.data_dir cannot be empty");
			}
			
			// Use provided directory and append "history"
			this.history_dir = GLib.Path.build_filename(app.data_dir, "history");
			
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
			
			// Store config
			this.config = app.config;
			
			// Create base client from default_model usage
			this.base_client = app.config.create_client("default_model");
			if (this.base_client == null) {
				GLib.error("Manager: failed to create base client from default_model");
			}
			
			this.base_client.stream = true;
			this.base_client.keep_alive = "5m";
			this.base_client.prompt_assistant = new Prompt.JustAsk();

			// Register JustAsk agent (always available as default)
			// MUST be registered before creating EmptySession, as EmptySession calls new_client()
			// which tries to get "just-ask" from this.agents
			this.agents.set("just-ask", this.base_client.prompt_assistant );

			this.session = new EmptySession(this);
			this.session.activate(); // contects signals alhtough to nowhere..
			
			// Set up title generator with a client configured for title generation
			var title_client = this.config.create_client("title_model");
			if (title_client == null) {
				// Fallback: use base_client's connection and model
				title_client = new OLLMchat.Client(this.base_client.connection) {
					stream = false,
					config = this.config,
					model = ""
				};
			}
			title_client.stream = false;
			
			this.title_generator = new TitleGenerator(title_client);
		}
		
		/**
		 * Creates a new client instance.
		 *
		 * If copy_from is provided, copies all properties from that client.
		 * Otherwise, copies from base_client.
		 * Always creates fresh tool instances.
		 *
		 * @param copy_from Optional client to copy properties from. If null, uses base_client.
		 * @return A new Client instance with copied properties and fresh tools
		 */
		public Client new_client(Client? copy_from = null)
		{
			var source = copy_from == null ? this.base_client : copy_from;
			
			
			// Share the same connection instance - connections are immutable configuration
			var client = new OLLMchat.Client(source.connection) {
				stream = source.stream,
				format = source.format,
				think = source.think,
				keep_alive = source.keep_alive,
				config = source.config,
				model = source.model,
				prompt_assistant = copy_from != null ? source.prompt_assistant : this.agents.get("just-ask"),
				permission_provider = source.permission_provider, // Shared reference - MUST be shared
				options = source.options.clone(),
				timeout = source.timeout
			};
			
			// Copy available_models (shared model data)
			foreach (var entry in source.available_models.entries) {
				client.available_models.set(entry.key, entry.value);
			}
			
			// Reuse the same tools, just set the client to the new value (leave active the same)
			foreach (var tool in source.tools.values) {
				client.addTool(tool);
			}
			
			// Properties NOT copied (and why):
			// - streaming_response: Session-specific streaming state
			// - session: Not applicable to new client instance
			// - tools: Reused above (just set client property)
			// - options: Will be loaded when Chat is created
			
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
		 * Uses the current session's agent_name and model if available, otherwise defaults to "just-ask".
		 *
		 * @return A new Session instance with a fresh client
		 */
		public Session create_new_session()
		{
			// Get agent name from current session, default to "just-ask"
			var agent_name = "just-ask";
			if (this.session != null && this.session.agent_name != "") {
				agent_name = this.session.agent_name;
			}
			
			// Create client with the agent
			var client = this.new_client();
			client.prompt_assistant = this.agents.get(agent_name);
			
			// Copy model from current session if available
			if (this.session != null &&
				this.session.client != null &&
				this.session.client.model != "") {
				client.model = this.session.client.model;
			}
			
			var session = new Session(this, new Call.Chat(client, client.model));
			session.agent_name = agent_name;
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

