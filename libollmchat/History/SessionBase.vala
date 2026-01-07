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
	 * Base class for Session implementations.
	 *
	 * Contains shared functionality that doesn't depend on chat existing.
	 * Subclasses must implement abstract methods for chat-dependent operations.
	 * Provides common properties like id, title, and client management.
	 */
	public abstract class SessionBase : Object, Json.Serializable
	{
		public int64 id { get; set; default = -1; }
		public Client client { get; protected set; }
		public Call.Chat? chat { get; set; }
		
		// Permission provider for tool execution (default: reject everything)
		internal OLLMchat.ChatPermission.Provider? refactor_permission_provider = null;
		
		/**
		 * Permission provider for tool execution.
		 *
		 * Handles permission requests when tools need to access files or execute commands.
		 * Defaults to a reject-all provider if not set.
		 *
		 * @since 1.0
		 */
		public OLLMchat.ChatPermission.Provider? permission_provider {
			get { return refactor_permission_provider; }
			set { 
				refactor_permission_provider = value;
				// Also set on Chat if it exists
				if (this.chat != null) {
					this.chat.permission_provider = value;
				}
			}
		}
		
		public int64 updated_at_timestamp { get; set; default = 0; }  // Unix timestamp
		public string title { get; set; default = ""; }
		public string agent_name { get; set; default = "just-ask"; }
		public int unread_count { get; set; default = 0; }
		public bool is_active { get; protected set; default = false; }
		
		// Model property - stored on Session since Client no longer has model (Phase 3)
		public string model { get; set; default = ""; }
		
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
		
		// Signal handler IDs for disconnection
		// Manager handlers (for persistence)
		protected ulong stream_chunk_handler_id = 0;
		// UI relay signals
		// chat_send_id removed - callers handle state directly after calling send()
		protected ulong stream_chunk_id = 0;
		protected ulong stream_content_id = 0;
		protected ulong stream_start_id = 0;
		protected ulong tool_message_id = 0;
		
		// File ID: Format Y-m-d-H-i-s (e.g., "2025-01-15-14-30-45")
		// Owned by Session, not Chat
		public string fid { get; protected set; }
		
		// Agent handler reference - set when session is created or AgentHandler is changed
		public OLLMchat.Prompt.AgentHandler? agent { get; set; }
		
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
			
			// Create client for this session
			this.client = manager.new_client();
			
			// Get model from config or use default
			var model = manager.config.get_default_model();
			model = model == "" ? "placeholder" : model;
		 
			
			// Create chat with default properties
			this.chat = new Call.Chat(this.client.connection, model) {
				stream = true,  // Default to streaming
				think = false
			};
			// Get options from config if available and update chat
			// usage.get() can return null if key doesn't exist, and cast can return null if wrong type
			var default_usage = manager.config.usage.get("default_model") as Settings.ModelUsage;
			this.chat.options = default_usage != null ? default_usage.options : new Call.Options();

			// Copy tools from Manager to Chat (Phase 3: tools stored on Manager)
			foreach (var tool in manager.tools.values) {
				this.chat.add_tool(tool);
			}
			
			// Store model on session
			this.model = model;
			
			// Initialize permission provider to default (Dummy allows READ, denies WRITE/EXECUTE)
			this.refactor_permission_provider = new OLLMchat.ChatPermission.Dummy();
			this.chat.permission_provider = this.refactor_permission_provider;
		}
		
		/**
		 * Activates this session, connecting client signals to relay to UI.
		 * Called when the session becomes the active session in the UI.
		 */
		public void activate()
		{
			if (this.is_active) {
				return;
			}
			this.is_active = true;
			this.unread_count = 0; // Clear unread count when activated
			if (this.client == null) {
				return;
			}

			
			// Connect client signals to Manager handlers (for persistence)
			this.stream_chunk_handler_id = this.client.stream_chunk.connect((new_text, is_thinking, response) => {
				this.on_stream_chunk(new_text, is_thinking, response);
			});
			
			// message_created connection removed - signal no longer exists on Client
			// Messages are now added directly via session.add_message() which relays to UI via Manager
			
			// Connect client signals to relay to UI via Manager
			// chat_send connection removed - callers handle state directly after calling send()
			this.stream_chunk_id = this.client.stream_chunk.connect((new_text, is_thinking, response) => {
				this.manager.stream_chunk(new_text, is_thinking, response);
				// Relay stream_content for non-thinking chunks (replaces stream_content signal)
				if (!is_thinking) {
					this.manager.stream_content(new_text, response);
				}
			});
			// stream_content connection removed - replaced with stream_chunk + is_thinking check above
			this.stream_start_id = this.client.stream_start.connect(() => {
				this.manager.stream_start();
			});
			this.tool_message_id = this.client.tool_message.connect((message) => {
				GLib.debug("SessionBase.tool_message handler: Received tool_message from client (role=%s, content='%.50s', manager=%p, session=%p)", 
					message.role, message.content, this.manager, this);
				if (this.manager == null) {
					GLib.debug("SessionBase.tool_message handler: ERROR - manager is null!");
					return;
				}
				this.manager.tool_message(message);
				GLib.debug("SessionBase.tool_message handler: Relayed to manager.tool_message signal");
			});
		}
		
		/**
		 * Deactivates this session, disconnecting client signals.
		 * Called when the session is no longer the active session in the UI.
		 */
		public void deactivate()
		{
			// Check if already deactivated (stream_chunk_handler_id will be 0 if not connected)
			if (this.stream_chunk_handler_id == 0) {
				return;
			}
			
			if (!this.is_active) {
				return;
			}
			this.is_active = false;

			if (this.client == null) {
				return;
			}

			// Disconnect client signals from Manager handlers (check if connected first)
			if (this.stream_chunk_handler_id != 0 && GLib.SignalHandler.is_connected(this.client, this.stream_chunk_handler_id)) {
				this.client.disconnect(this.stream_chunk_handler_id);
			}
			
			// Disconnect client signals from UI relay (check if connected first)
			// chat_send_id removed - no longer connecting to this signal
			// message_created_id removed - signal no longer exists on Client
			if (this.stream_chunk_id != 0 && GLib.SignalHandler.is_connected(this.client, this.stream_chunk_id)) {
				this.client.disconnect(this.stream_chunk_id);
			}
			// stream_content_id removed - no longer connecting to this signal
			if (this.stream_start_id != 0 && GLib.SignalHandler.is_connected(this.client, this.stream_start_id)) {
				this.client.disconnect(this.stream_start_id);
			}
			if (this.tool_message_id != 0 && GLib.SignalHandler.is_connected(this.client, this.tool_message_id)) {
				this.client.disconnect(this.tool_message_id);
			}
			
			// Reset all IDs to 0
			this.stream_chunk_handler_id = 0;
			// chat_send_id removed - no longer connecting to this signal
			this.stream_chunk_id = 0;
			// stream_content_id removed - no longer connecting to this signal
			this.stream_start_id = 0;
			this.tool_message_id = 0;
		}
		
		/**
		 * Handler for message_created signal from this session's client.
		 * Handles message persistence and relays to Manager.
		 * Must be implemented by subclasses.
		 */
		protected abstract void on_message_created(Message m, ChatContentInterface? content_interface);
		
		/**
		 * Handler for stream_chunk signal from this session's client.
		 * Handles unread tracking and session saving.
		 * Must be implemented by subclasses.
		 */
		protected abstract void on_stream_chunk(string new_text, bool is_thinking, Response.Chat response);
		
		/**
		 * Adds a message to the session and relays it to the UI via Manager signal.
		 *
		 * This method is called by tools to add messages directly to the session.
		 * It adds the message to session.messages array and relays to UI via Manager's add_message signal.
		 * The session passes itself to the signal so the UI can access session.client and session.chat.
		 *
		 * @param message The message to add
		 */
		public void add_message(Message message)
		{
			// Add message to session.messages array
		
			this.messages.add(message);
			
			
			// Relay to UI via Manager's add_message signal - pass this session, not content_interface
			this.manager.add_message(message, this);
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
		 * Sends a message using this session's client.
		 * Must be implemented by subclasses.
		 *
		 * @param text The message text to send
		 * @param cancellable Optional cancellable for canceling the request
		 * @return The response from the chat API
		 * @throws Error if the request fails
		 */
		public abstract async Response.Chat send_message(string text, GLib.Cancellable? cancellable = null) throws Error;
		
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

