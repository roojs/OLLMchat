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
		public SessionList sessions {  get;  private set;  default = new SessionList(); }
		public SQ.Database db { get; private set; }
		public TitleGenerator title_generator { get; private set; }
		public Settings.ModelUsage? default_model_usage { get; private set; }
		public Settings.Config2 config { get; private set; }
		public SessionBase session { get; internal set; }
		public Gee.HashMap<string, OLLMchat.Agent.Factory> agent_factories { 
			get; private set; default = new Gee.HashMap<string, OLLMchat.Agent.Factory>(); 
		}
		public Gee.HashMap<string, Tool.BaseTool> tools { 
			get; private set; default = new Gee.HashMap<string, Tool.BaseTool>(); 
		}
		public Settings.ConnectionModels connection_models { get; private set; }
		
		/**
		 * Permission provider for tool execution.
		 *
		 * Handles permission requests when tools need to access files or execute commands.
		 * Set by Window when creating the manager. Shared across all sessions.
		 *
		 * @since 1.2.7.9
		 */
		public OLLMchat.ChatPermission.Provider permission_provider { get; set;
			 default = new OLLMchat.ChatPermission.Dummy(); }
		
		// Signal emitted when a session is removed (for UI updates)
		public signal void session_removed(SessionBase session);
		
		// Signal emitted when a session is activated
		public signal void session_activated(SessionBase session);
		
		// Signal emitted when an agent is activated (for UI updates)
		public signal void agent_activated(Agent.Factory agent);
		
		// Signals that relay client signals to UI (from active session)
		public signal void chat_send(Call.Chat chat);
		public signal void stream_chunk(string new_text, bool is_thinking, Response.Chat response);
		public signal void stream_content(string new_text, Response.Chat response);
		public signal void stream_start();
		public signal void tool_message(OLLMchat.Message message);
		
		/**
		 * Emitted when a new message is added to a session.
		 * 
		 * This is the signal for the new flow:
		 * - Session.send() adds message to session and emits this signal
		 * - UI connects to this signal to update the display
		 * 
		 * @param message The message that was added
		 * @param session The session the message was added to (may be null for messages not yet associated with a session)
		 */
		public signal void message_added(Message message, SessionBase? session);
		
		 
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
			
			// Create ConnectionModels instance
			this.connection_models = new Settings.ConnectionModels(this.config);
			
			// Store default_model_usage (base_client created lazily when needed)
			this.default_model_usage = app.config.usage.get("default_model") as Settings.ModelUsage;
			if (this.default_model_usage == null || this.default_model_usage.connection == "" || 
				!app.config.connections.has_key(this.default_model_usage.connection)) {
				GLib.error("Manager: failed to get default_model usage or connection");
			}
			
			// Phase 3: Client no longer has stream/keep_alive properties
			// These are set on Chat objects when they are created

			// Register JustAsk agent (always available as default)
			var just_ask_agent = new Agent.JustAskFactory();
			this.agent_factories.set("just-ask", just_ask_agent);

			this.session = new EmptySession(this);
			//FIXME = tjos emeds removing
			this.session.activate(); // contects signals alhtough to nowhere..
			
			// Set up title generator with manager reference
			// TitleGenerator will handle missing title_model configuration by returning default titles
			this.title_generator = new TitleGenerator(this);
		}
		
		/**
		 * Ensures that the default_model_usage is valid and the model exists on the server.
		 * 
		 * Verifies that the model specified in default_model_usage is available on the connection.
		 * This should be called after Manager is created to ensure the model can be used.
		 * 
		 * Note: Empty servers (servers without models) should be handled in bootstrap flow (see 1.4.1-bootstrap empty server).
		 * 
		 * @throws Error if the model cannot be verified or does not exist
		 */
		public async void ensure_model_usage() throws Error
		{
			if (this.default_model_usage == null) {
				throw new GLib.IOError.FAILED("Manager: default_model_usage is null");
			}
			
			// Verify the model exists and can be used
			if (!(yield this.default_model_usage.verify_model(this.config))) {
				throw new GLib.IOError.FAILED(
					"Manager: default_model '%s' not found on connection '%s'. " +
					"Please ensure the model is available on your server.",
					this.default_model_usage.model,
					this.default_model_usage.connection
				);
			}
		}
		
		/**
		 * Registers a single tool and stores it on Manager.
		 * 
		 * @param tool The tool instance to register
		 */
		public void register_tool(OLLMchat.Tool.BaseTool tool)
		{
			// Binding tool.active to config.tools[name].enabled (single source of truth) does not work
			// in the current setup; the previous sync (config → tool.active on load and on settings close)
			// was not a good design. To be considered later.
			this.tools.set(tool.name, tool);
			GLib.debug("Manager.register_tool: Registered tool '%s'", tool.name);
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
		 * Uses the current session's agent_name and model_usage if available, otherwise defaults.
		 *
		 * @return A new EmptySession instance
		 */
		public EmptySession create_new_session()
		{
			GLib.debug("create_new_session: before - %s", this.session.to_string());
			
			// Get agent name from current session, default to "just-ask"
			var agent_name = "just-ask";
			if (this.session != null && this.session.agent_name != "") {
				agent_name = this.session.agent_name;
			}
			
			// Create EmptySession (converts to Session when first message is sent)
			var empty_session = new EmptySession(this);
			// Copy model_usage from current session if available, otherwise uses default from base constructor
			if (this.session != null) {
				empty_session.activate_model(this.session.model_usage);
			}
			empty_session.agent_name = agent_name;
			
			GLib.debug("create_new_session: after - %s", empty_session.to_string());
			
			return empty_session;
		}
		
		/**
		 * Gets the active agent for the current session.
		 * 
		 * Returns the agent based on the current session's agent_name.
		 * The client for the agent should be obtained from the session separately.
		 * 
		 * @return The active agent, or null if not found
		 */
		public OLLMchat.Agent.Factory? get_active_agent()
		{
			return this.agent_factories.get(this.session.agent_name == "" ? "just-ask"
				 : this.session.agent_name);
		}
		
		/**
		 * Load all chat sessions from SQLite database and store in manager.
		 * Sessions are loaded as SessionPlaceholder instances until load() is called.
		 */
		public void load_sessions()
		{
			this.sessions.remove_all();
			
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
				// Skip sessions with no messages
				if (placeholder.total_messages == 0) {
					continue;
				}
				// Verify the session file exists and has content before adding
				var file = placeholder.session_file();
				if (!file.query_exists()) {
					continue;
				}
				var info = file.query_info(GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE, null);
				if (info.get_size() == 0) {
					continue;
				}
				// Check if model exists in connection_models before adding
				if (this.connection_models.find_model_by_name(placeholder.model_usage_model) == null) {
					// Model not found, skip this placeholder
					continue;
				}
				placeholder.reconstruct_model_usage_from_model();

				this.sessions.append(placeholder);
			}
		}
		
		/**
		 * Sends a message to a session.
		 * 
		 * This is the new entry point for UI to send messages. UI creates Message objects
		 * and calls this method, which routes to session.send().
		 * 
		 * @param session The session to send the message to
		 * @param user_message The message object to send
		 * @param cancellable Optional cancellable for canceling the request
		 * @throws Error if send fails
		 */
		public async void send(SessionBase session, Message user_message, GLib.Cancellable? cancellable = null) throws Error
		{
			// Delegate to session
			yield session.send(user_message, cancellable);
		}
		
		/**
		 * Activates an agent for a session identified by fid.
		 * 
		 * This is the entry point for UI to change agents. UI calls this method,
		 * which routes to session.activate_agent() to handle the agent change,
		 * including copying chat/messages from old AgentHandler to new AgentHandler.
		 * 
		 * @param fid The session identifier (file ID)
		 * @param agent_name The name of the agent to activate
		 * @throws Error if session not found or agent activation fails
		 */
		public void activate_agent(string fid, string agent_name) throws Error
		{
			// Find session by fid using SessionList fid_map lookup
			var session = this.sessions.get_by_fid(fid);
			if (session == null) {
				throw new OllmError.INVALID_ARGUMENT("Session with fid '%s' not found", fid);
			}
			
			// Delegate to session
			session.activate_agent(agent_name);
		}
		
		
	}
}

