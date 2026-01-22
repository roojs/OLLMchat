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
	 * Base class for Session implementations.
	 *
	 * Contains shared functionality that doesn't depend on chat existing.
	 * Subclasses must implement abstract methods for chat-dependent operations.
	 * Provides common properties like id, title, and client management.
	 */
	public abstract class SessionBase : Object, Json.Serializable
	{
		public int64 id { get; set; default = -1; }
		
		public int64 updated_at_timestamp { get; set; default = 0; }  // Unix timestamp
		public string title { get; set; default = ""; }
		public string agent_name { get; set; default = "just-ask"; }
		public int unread_count { get; set; default = 0; }
		
		// Computed property for binding to widget visibility
		public bool has_unread {
			get { return this.unread_count > 0; }
		}
		
		public bool is_active { get; protected set; default = false; }
		public bool is_running { get;  set; default = false; } // agent can set this as runnig when doing tools
		
		
		// Backing field for model (stored in database, not serialized to filesystem)
		internal string model_usage_model = "";
		
		/**
		 * Model property - stored in DB for display, get returns model_usage.model
		 * 
		 * IMPORTANT: This property should ONLY be used in these scenarios:
		 * - Database read/write operations (SQ framework)
		 * - UI display when only DB data is loaded (SessionPlaceholder)
		 * 
		 * For all other code, ALWAYS work with model_usage directly.
		 * Never set or read this property outside of the above scenarios.
		 * 
		 * When set, stores in model_usage_model (for DB persistence)
		 * When get, returns model_usage.model (not model_usage_model)
		 */
		public string model {
			get {
				return this.model_usage.model;
			}
			set {
				this.model_usage_model = value;
			}
		}
		
		// ModelUsage property - stores full model configuration (connection, model, options)
		// Options are overlaid from config.model_options when activate_model() is called
		public Settings.ModelUsage model_usage { get; set; }
		
		// Display properties for UI
		public string display_title {
			owned get {
				// Return only first line for display in history widget
				if (this.title == "") {
					return "";
				}
				var lines = this.title.split("\n");
				return lines[0];
			}
		}
		
		public string display_date {
			owned get {
				if (this.updated_at_timestamp == 0) {
					return "";
				}
				
				var dt = new DateTime.from_unix_local(this.updated_at_timestamp);
				var now = new DateTime.now_local();
				var diff = now.difference(dt);
				var days = (int)(diff / TimeSpan.DAY);
				var hours = (int)(diff / TimeSpan.HOUR);
				var minutes = (int)(diff / TimeSpan.MINUTE);
				
				if (days > 7) {
					return dt.format("%b %d, %Y");
				}
				if (days > 0) {
					return days == 1 ? "Yesterday" : "%d days ago".printf(days);
				}
				if (hours > 0) {
					return hours == 1 ? "1 hour ago" : "%d hours ago".printf(hours);
				}
				if (minutes > 0) {
					return minutes == 1 ? "1 minute ago" : "%d minutes ago".printf(minutes);
				}
				return "Just now";
			}
		}
		
		// CSS classes for styling session rows in history browser
		// Not serialized - computed property based on session state
		public string[] css_classes {
			owned get {
				var classes = new string[] {};
				if (this.unread_count > 0) {
					classes += "oc-has-unread";
				}
				return classes;
			}
			set { }  // Empty setter - read-only computed property
		}
		
		// Metadata flattened on session (not separate class)
		public int total_messages { get; set; default = 0; }
		public int64 total_tokens { get; set; default = 0; }
		public int64 duration_seconds { get; set; default = 0; }
		
		// Child chats as array of filename paths (placeholder - not currently used)
		// Format: "YYYY/mm/dd/h-i-s" (relative file path)
		public Gee.ArrayList<string> child_chats { get; set; default = new Gee.ArrayList<string>(); }
		
		// Messages property - maintains separate list for serialization
		// This list includes all message types (standard + special session types)
		// Separate from chat.messages and used for serialization
		public Gee.ArrayList<Message> messages { get; set; default = new Gee.ArrayList<Message>(); }
		
		// Manager reference for getting history directory
		// Made a construct property so it can be set via Object.new_with_properties
		// Note: construct properties must be public in Vala
		public Manager manager { get; construct set; }
		
		// Signal handler IDs removed - agent usage now uses direct method calls from Chat
		// Note: Persistence may need to be handled differently (connect to Chat signals instead of Client signals)
		
		// File ID: Format Y-m-d-H-i-s (e.g., "2025-01-15-14-30-45")
		// Owned by Session, not Chat
		public string fid { get; protected set; }
		
		// Agent handler reference - set when session is created or AgentHandler is changed
		public OLLMchat.Agent.Base? agent { get; set; }
		
		
		// Abstract properties that depend on chat
		public abstract string display_info { owned get; }
		
		/**
		 * Constructor for base class.
		 *
		 * @param manager The history manager (can be set via construct property)
		 */
		protected SessionBase(Manager manager)
		{
			this.manager = manager;
			
			// Copy model_usage from manager's default_model_usage
			this.model_usage = manager.default_model_usage;
			
			// Note: Chat is created per request by AgentHandler, not stored on Session
			// Note: Permission provider is on Manager, accessed via agent.session.manager.permission_provider
		}
		
		/**
		 * Activates a model for this session.
		 * 
		 * Stores the ModelUsage and overlays options from config.model_options if available.
		 * Updates the session's model property and connection.
		 * 
		 * @param model_usage The ModelUsage to activate (connection, model, options)
		 */
		public void activate_model(Settings.ModelUsage model_usage)
		{
			// Clone the ModelUsage to avoid modifying the original
			var usage = new Settings.ModelUsage() {
				connection = model_usage.connection,
				model = model_usage.model,
				model_obj = model_usage.model_obj
			};
			
			// Start with options from the ModelUsage
			usage.options = model_usage.options.clone();
			
			// Overlay options from config.model_options if available (config options take precedence)
			if (this.manager.config.model_options.has_key(model_usage.model)) {
				var config_options = this.manager.config.model_options.get(model_usage.model);
				// Config options override ModelUsage options
				usage.options = config_options.clone();
			}
			
			// Store the ModelUsage
			this.model_usage = usage;
			
			// Update Chat properties if agent exists (agent always exists when activate_model is called)
				if (this.agent != null && this.agent.chat() != null) {
				// Update model
				this.agent.chat().model = usage.model;
				
				// Update connection
				if (usage.connection != "" && this.manager.config.connections.has_key(usage.connection)) {
					this.agent.chat().connection = this.manager.config.connections.get(usage.connection);
				}
				
				// Update options (no cloning - Chat just references the Options object)
				this.agent.chat().options = usage.options;
				
				// Update think parameter based on model capabilities
				bool supports_thinking = false;
				if (usage.model_obj != null) {
					supports_thinking = usage.model_obj.is_thinking;
				}
				this.agent.chat().think = supports_thinking;
			}
		}
		
		/**
		 * Reconstructs model_usage from the model_usage_model field (used when loading from database).
		 * 
		 * Searches for the model in available connections. If found, uses that connection.
		 * If not found, uses the default connection.
		 */
		public void reconstruct_model_usage_from_model()
		{
			// Search for model in connection_models
			var found_usage = this.manager.connection_models.find_model_by_name(this.model_usage_model);
			if (found_usage != null) {
				// Clone the found usage
				var usage = found_usage.clone();
				
				// Overlay options from config.model_options if available (config options take precedence)
				if (this.manager.config.model_options.has_key(this.model_usage_model)) {
					var config_options = this.manager.config.model_options.get(this.model_usage_model);
					usage.options = config_options.clone();
				}
				
				this.model_usage = usage;
				return;
			}
			
			// Model not found, create new ModelUsage with default connection
			var default_connection = this.manager.config.default_connection();
			var usage = new Settings.ModelUsage() {
				connection = default_connection != null ? default_connection.url : "",
				model = this.model_usage_model
			};
			
			// Overlay options from config.model_options if available
			if (this.manager.config.model_options.has_key(this.model_usage_model)) {
				var config_options = this.manager.config.model_options.get(this.model_usage_model);
				usage.options = config_options.clone();
			}
			
			this.model_usage = usage;
		}
		
		/**
		 * Activates this session, connecting client signals to relay to UI.
		 * Called when the session becomes the active session in the UI.
		 */
		public virtual void activate()
		{
			if (this.is_active) {
				return;
			}
			this.is_active = true;
			this.unread_count = 0; // Clear unread count when activated
			this.notify_property("has_unread");  // Notify has_unread when crossing from >0 to 0
			this.notify_property("css_classes");  // Notify css_classes change when unread_count cleared

			// Signal connections removed - agent usage now uses direct method calls from Chat
			// Chat always emits signals, and when agent is set, Chat also calls agent methods directly
			// AgentHandler relays to Session via direct method calls, Session relays to Manager signals
		}
		
		/**
		 * Deactivates this session, disconnecting client signals.
		 * Called when the session is no longer the active session in the UI.
		 */
		public void deactivate()
		{
			if (!this.is_active) {
				return;
			}
			this.is_active = false;

			// Signal disconnections removed - agent usage now uses direct method calls from Chat
		}
		
		/**
		 * Handler for message_created signal from this session's client.
		 * Handles message persistence and relays to Manager.
		 * Must be implemented by subclasses.
		 */
		protected abstract void on_message_created(Message m);
		
		/**
		 * Called by AgentHandler when streaming starts.
		 * Session relays to Manager signals.
		 */
		public void handle_stream_started()
		{
			this.manager.stream_start();
		}
		
		/**
		 * Called by AgentHandler when a streaming chunk is received.
		 * Session relays to Manager signals (Manager doesn't process, just relays to UI).
		 * 
		 * Note: Manager signals are just a relay point - Manager doesn't need to process
		 * these events, it just forwards them to UI components that are connected to Manager signals.
		 * 
		 * Subclasses can override to add persistence handling before relaying to Manager.
		 */
		public virtual void handle_stream_chunk(string new_text, bool is_thinking, Response.Chat response)
		{
			// Relay directly to Manager signals (Manager is just a relay point, no processing needed)
			this.manager.stream_chunk(new_text, is_thinking, response);
		}
		
		/**
		 * Called by AgentHandler when a tool sends a status message.
		 * Session relays to Manager signals.
		 */
		public void handle_tool_message(Message message)
		{
			this.manager.tool_message(message);
		}
		
		/**
		 * Adds a message to the session and relays it to the UI via Manager signal.
		 *
		 * This method is called by tools to add messages directly to the session.
		 * It adds the message to session.messages array and relays to UI via Manager's add_message signal.
		 * The session passes itself to the signal so the UI can access session.chat.
		 *
		 * @param message The message to add
		 */
		public void add_message(Message message)
		{
			// Add message to session.messages array
		
			this.messages.add(message);
			
			// Set running state to false when done message is received
			if (message.role == "done") {
				this.is_running = false;
				GLib.debug("Stopping running");
			}
			
			// Notify display_info when message count changes (affects reply count in UI)
			this.notify_property("display_info");
			
			// Relay to UI via Manager's message_added signal - pass this session, not content_interface
			// Only relay if session is active
			if (this.is_active) {
				this.manager.message_added(message, this);
			}
		}
		
		
		/**
		 * Convert file ID to path format.
		 * Converts ID format "Y-m-d-H-i-s" to path format "YYYY/mm/dd/h-i-s"
		 *
		 * @return File path relative to history directory
		 */
		public string to_path()
		{
			// Parse ID: "2025-01-15-14-30-45" -> "2025/01/15/14-30-45"
			var parts = this.fid.split("-");
			return parts[0] + "/" + parts[1] + "/" + parts[2] + "/" + parts[3] + "-" + parts[4] + "-" + parts[5];
		}
		
		
		/**
		 * Save session to SQLite database.
		 * Must be implemented by subclasses.
		 */
		public abstract void saveToDB();
		
		/**
		 * Save session to both DB and file asynchronously.
		 * Must be implemented by subclasses.
		 *
		 * @param update_timestamp If true, update the updated_at_timestamp to current time. Should be true only when there's actual chat activity.
		 */
		public abstract async void save_async(bool update_timestamp = true);
		
		/**
		 * Write session to JSON file.
		 * Must be implemented by subclasses.
		 *
		 * @throws Error if write fails
		 */
		public abstract async void write() throws Error;
		
		/**
		 * Read session from JSON file.
		 * Must be implemented by subclasses.
		 *
		 * @throws Error if read fails
		 */
		public abstract async void read() throws Error;
		
		/**
		 * Loads the session data if needed (e.g., for SessionPlaceholder).
		 * No-op for sessions that are already loaded.
		 *
		 * @return The loaded session (may be a new Session object for SessionPlaceholder, or this for already-loaded sessions)
		 * @throws Error if loading fails
		 */
		public abstract async SessionBase? load() throws Error;
		
		/**
		 * Sends a Message object to this session.
		 * 
		 * This is the new method for sending messages. Adds Message to session history
		 * and delegates to AgentHandler if message.role == "user".
		 * 
		 * @param message The message object to send
		 * @param cancellable Optional cancellable for canceling the request
		 * @throws Error if the request fails
		 */
		public abstract async void send(Message message, GLib.Cancellable? cancellable = null) throws Error;
		
		/**
		 * Cancels the current request if one is active.
		 * Must be implemented by subclasses.
		 */
		public abstract void cancel_current_request();
		
		/**
		 * Activates an agent for this session.
		 * 
		 * Handles agent changes by creating a new AgentHandler and copying
		 * any necessary state from the old AgentHandler to the new one.
		 * 
		 * @param agent_name The name of the agent to activate
		 * @throws Error if agent activation fails
		 */
		public abstract void activate_agent(string agent_name) throws Error;
		
		/**
		 * Returns a string representation of the session for debugging.
		 * 
		 * @return String with title, model, agent_name, and agent object status
		 */
		public string to_string()
		{
			var agent_name_str = this.agent_name ?? "(null)";
			return "title='" + this.title + "', " +
			       "model='" + this.model_usage.model + "', " +
			       "agent_name='" + agent_name_str + "', " +
			       "agent=" + (this.agent != null ? "Y" : "N");
		}
		
		/**
		 * Handle JSON property mapping and custom deserialization.
		 * Must be implemented by subclasses.
		 */
		public abstract bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node);
		
		/**
		 * Handle JSON property mapping for serialization.
		 * Must be implemented by subclasses.
		 */
		public abstract Json.Node serialize_property(string property_name, Value value, ParamSpec pspec);
	}
}

