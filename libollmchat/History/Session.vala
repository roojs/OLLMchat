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
	 * Session is a wrapper around Call.Chat that provides history persistence.
	 *
	 * It uses SQ (SQLite) for database storage of metadata, and JSON files
	 * for complete session data including all messages. Properties are wrappers
	 * Messages come from session.messages. Model and other properties are on Session (Chat is created per request by AgentHandler)
	 * with a flag to include extra info during JSON encoding.
	 *
	 * == Example ==
	 *
	 * {{{
	 * // Create session from chat call
	 * var call = new Call.Chat(client, "llama3.2");
	 * var session = new History.Session(call, db);
	 *
	 * // Save session to disk and database
	 * yield session.save();
	 *
	 * // Load session later
	 * var loaded = History.Session.load(id, db, client, config);
	 * }}}
	 *
	 * Session requires a Call.Chat object in its constructor.
	 */
	public class Session : SessionBase
	{
		// Streaming state tracking
		private Message? current_stream_message = null;
		private bool current_stream_is_thinking = false;
		
			
		public override string display_info {
			owned get {
				// Count assistant messages (replies) from session messages
				int reply_count = 0;
				foreach (var msg in this.messages) {
					if (msg.role == "assistant") {
						reply_count++;
					}
				}
				
				return "%s - %d %s".printf(
					this.model,
					reply_count,
					reply_count == 1 ? "reply" : "replies"
				);
			}
		}	
		
	/**
	 * Constructor for Session.
	 * 
	 * Note: Chat is created per request by AgentHandler, not stored on Session.
	 *
	 * @param manager The history manager
	 */
	public Session(Manager manager)
	{
		base(manager);
		// Model is set by Manager after construction
		
		// Generate fid from current timestamp (format: YYYY-MM-DD-HH-MM-SS)
		var now = new DateTime.now_local();
		this.fid = now.format("%Y-%m-%d-%H-%M-%S");
		
		// Set agent handler when session is created (if agent_name is set)
		// Agent will be set later if agent_name is set after construction
		
		// Connect to config changed signal to update Chat when config changes
		this.manager.config.changed.connect(this.on_config_changed);
	}
		
		/**
		* Handler for message_created signal from this session's client.
		* Handles message persistence when a message is created.
		* FIXME = needs making logical after we remove get_chat
		* FIXME = on message created should not be getting a chat? - need to work out why that would happen
		*/
		protected override void on_message_created(Message m, ChatContentInterface? content_interface)
		{
			// Update chat properties if message_interface is a Chat (don't replace the object)
			// Support both old pattern (this.chat) and new pattern (refactor_get_chat() or from message)
			if (m.message_interface is Call.Chat) {
				var new_chat = (Call.Chat) m.message_interface;
			// Update properties on agent's chat if available (Chat is created per request by AgentHandler)
			if (this.agent != null && this.agent.chat != null) {
				var current_chat = this.agent.chat;
				current_chat.model = new_chat.model;
				current_chat.stream = new_chat.stream;
				current_chat.format = new_chat.format;
				current_chat.format_obj = new_chat.format_obj;
				current_chat.think = new_chat.think;
				current_chat.keep_alive = new_chat.keep_alive;
				current_chat.options = new_chat.options;
			}
				// Note: fid is no longer copied from chat - it's owned by Session
				// Note: client is not updated from chat (Phase 3: Chat no longer has client)
			}
			
			// Skip "done" messages - they're just signal messages and shouldn't be persisted to history
			if (m.role == "done") {
				// Still relay to Manager for UI (though it will be filtered out there too)
				this.manager.message_added(m, this);
				return;
			}
			
			// Add message to session.messages
			// Check if message is already in list (avoid duplicates)
			bool found = false;
			foreach (var existing_msg in this.messages) {
				if (existing_msg == m) {
					found = true;
					break;
				}
			}
			if (!found) {
				this.messages.add(m);
			}
			
			// Ensure session is tracked in Manager (SessionList will emit items_changed signal automatically)
			if (!this.manager.sessions.contains(this)) {
				this.manager.sessions.append(this);
			}
			
			// Relay to Manager for UI - pass this session, not content_interface
			this.manager.message_added(m, this);
			
			// Save session
			this.save_async.begin();
			this.notify_property("display_info");
			this.notify_property("display_title");
		}
			
		/**
		 * Called by AgentHandler when a streaming chunk is received.
		 * Handles persistence and relays to Manager signals.
		 */
		public override void handle_stream_chunk(string new_text, bool is_thinking, Response.Chat response)
		{
			// If session is inactive, increment unread count
			if (!this.is_active) {
				this.unread_count++;
				this.notify_property("unread_count");
			}
			
			// Capture streaming output
			if (new_text.length > 0) {
				// Check if stream type has changed
				if (this.current_stream_message == null || this.current_stream_is_thinking != is_thinking) {
					// Stream type changed or first chunk - create new stream message
					string stream_role = is_thinking ? "think-stream" : "content-stream";
					this.current_stream_message = new Message(this.agent.chat, stream_role, new_text);
					this.current_stream_is_thinking = is_thinking;
					this.messages.add(this.current_stream_message);
				} else {
					// Same stream type - append to existing message
					this.current_stream_message.content += new_text;
				}
			}
			
			// When response is done, finalize streaming
			if (response.done) {
				this.finalize_streaming(response);
			}
			
			// Relay to Manager signals (base class handles this)
			base.handle_stream_chunk(new_text, is_thinking, response);
		}
		
		/**
		 * Finalizes streaming when response is done.
		 */
		private void finalize_streaming(Response.Chat response)
		{
			// Create "end-stream" message to signal renderer
			var end_stream_msg = new Message(this.agent.chat, "end-stream", "");
			this.messages.add(end_stream_msg);
			
			// Finalize current stream message
			this.current_stream_message = null;
			this.current_stream_is_thinking = false;
			
			if (response.message == null || !response.message.is_llm) {
				this.save_async.begin();
				this.notify_property("display_info");
				this.notify_property("title");
				return;
			}
			// Add final assistant message if it exists and hasn't been added yet
				// Check if this message is already in our list (avoid duplicates)
			bool found = false;
			foreach (var existing_msg in this.messages) {
				if (existing_msg == response.message) {
					found = true;
					break;
				}
			}
			if (!found) {
				// Ensure message_interface is set
				response.message.message_interface = this.agent.chat;
				
				// Create a "done" message after the real message with summary
				var summary = response.get_summary();
				var done_msg = new Message(this.agent.chat, "done", summary);
			}
			
			
			this.save_async.begin();
			this.notify_property("display_info");
			this.notify_property("title");
		}
			
		/**
		 * Initialize database table for sessions.
		 */
		public static void initDB(SQ.Database db)
		{
			string errmsg;
			var query = "CREATE TABLE IF NOT EXISTS session (" +
				"id INTEGER PRIMARY KEY, " +
				"updated_at_timestamp INT64 NOT NULL DEFAULT 0, " +
				"title TEXT NOT NULL DEFAULT '', " +
				"model TEXT NOT NULL DEFAULT '', " +
				"agent_name TEXT NOT NULL DEFAULT 'just-ask', " +
				"total_messages INTEGER NOT NULL DEFAULT 0, " +
				"total_tokens INT64 NOT NULL DEFAULT 0, " +
				"duration_seconds INT64 NOT NULL DEFAULT 0, " +
				"fid TEXT NOT NULL" +
				");";
			if (Sqlite.OK != db.db.exec(query, null, out errmsg)) {
				GLib.warning("Failed to create session table: %s", db.db.errmsg());
			}
			
			// Add agent_name column if it doesn't exist (for existing databases)
			var alter_query = "ALTER TABLE session ADD COLUMN agent_name TEXT NOT NULL DEFAULT 'just-ask'";
			db.db.exec(alter_query, null, out errmsg);
			// Ignore error if column already exists
		}
		
		/**
		 * Save session to SQLite database.
		 */
		public override void saveToDB()
		{
			if (this.manager == null) {
				GLib.error("Session: manager is not set");
			}
			var sq = new SQ.Query<Session>(this.manager.db, "session");
			if (this.id < 0) {
				this.id = sq.insert(this);
			} else {
				sq.updateById(this);
			}
			// Backup in-memory database to disk
			this.manager.db.backupDB();
		}
		
		/**
		 * Save session to both DB and file asynchronously.
		 * Updates metadata and saves to both database and JSON file.
		 *
		 * @param update_timestamp If true, update the updated_at_timestamp to current time. Should be true only when there's actual chat activity.
		 */
		public override async void save_async(bool update_timestamp = true)
		{
			try {
				// Update timestamp only if requested (i.e., when there's actual chat activity)
				if (update_timestamp) {
					var now = new DateTime.now_local();
					this.updated_at_timestamp = now.to_unix();
				}
				
				// Update metadata
				this.total_messages = this.messages.size;
				// TODO: Calculate total_tokens and duration_seconds from response metadata
				
				// Generate title if not set
				if (this.title == "") {
					try {
						this.title = yield this.manager.title_generator.to_title(this);
					} catch (Error e) {
						GLib.warning("Failed to generate title: %s", e.message);
						this.title = "Untitled Chat";
					}
				}
				
				// Save to database
				this.saveToDB();
				
				// Save to JSON file
				yield this.write();
			} catch (Error e) {
				GLib.warning("Failed to save session: %s", e.message);
			}
		}
		
		/**
		 * Write session to JSON file.
		 * Uses this.fid and to_path() to determine where to write.
		 * Serializes the session including messages with history info (timestamp, hidden).
		 *
		 * @throws Error if write fails
		 */
		public override async void write() throws Error
		{
		 
			
			// Build full file path
			var full_path = GLib.Path.build_filename(this.manager.history_dir, this.to_path() + ".json");
			
			// Ensure directory exists
			var dir_path = GLib.Path.get_dirname(full_path);
			var dir = GLib.File.new_for_path(dir_path);
			if (!dir.query_exists()) {
				try {
					dir.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					throw new GLib.IOError.FAILED("Failed to create directory " + dir_path + ": " + e.message);
				}
			}
			
			// Serialize to JSON
			var json_node = Json.gobject_serialize(this);
			var generator = new Json.Generator();
			generator.pretty = true;
			generator.indent = 2;
			generator.set_root(json_node);
			
			// Write to file
			var file = GLib.File.new_for_path(full_path);
			var file_stream = yield file.replace_async(null, false, GLib.FileCreateFlags.NONE, GLib.Priority.DEFAULT, null);
			var data_stream = new GLib.DataOutputStream(file_stream);
			data_stream.put_string(generator.to_data(null));
			yield data_stream.close_async(GLib.Priority.DEFAULT, null);
			
			// Unset flag on messages (set during serialization)
			foreach (var msg in this.messages) {
				msg.include_history_info = false;
			}
		}
		
		/**
		 * Read session from JSON file.
		 * No-op for Session - sessions are loaded once via SessionPlaceholder.load() and never again.
		 *
		 * @throws Error if read fails
		 */
		public override async void read() throws Error
		{
			// No-op: Session is already loaded (via SessionPlaceholder.load())
		}
		
		/**
		 * Handle JSON property mapping and custom deserialization.
		 * No-op for Session - sessions are never deserialized (only SessionJson is used).
		 */
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			value = Value(pspec.value_type);
			return true;
		}
		
		/**
		 * Handle JSON property mapping for serialization.
		 */
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "fid":
				case "updated_at_timestamp":
				case "title":
				case "model":
				case "agent_name":
				case "total_messages":
				case "total_tokens":
				case "duration_seconds":
				case "child_chats":
					return default_serialize_property(property_name, value, pspec);
				
				case "messages":
					// Set flag on messages for extra info and set timestamps
					var messages_array = new Json.Array();
					foreach (var msg in this.messages) {
						msg.include_history_info = true;
						// Set timestamp if not already set
						if (msg.timestamp == "") {
							msg.timestamp = new DateTime.now_local().format("%Y-%m-%d %H:%M:%S");
						}
						messages_array.add_element(Json.gobject_serialize(msg));
						msg.include_history_info = false;
					}
					var node = new Json.Node(Json.NodeType.ARRAY);
					node.set_array(messages_array);
					return node;
				
				default:
					// Return null to exclude property from serialization
					// Runtime properties (chat, permission_provider, client, manager) are automatically skipped
					return null;
			}
		}
		
		
		/**
		 * Loads the session data if needed.
		 * No-op for Session (already loaded).
		 *
		 * @return This session (already loaded)
		 */
		public override async SessionBase? load() throws Error
		{
			// No-op: Session is already loaded
			return this;
		}
		
		/**
		 * Cancels the current request if one is active.
		 *
		 * Safe to call if no active request exists.
		 */
		public override void cancel_current_request()
		{
			// Cancel via agent's chat if available
			if (this.agent.chat.cancellable != null) {
				this.agent.chat.cancellable.cancel();
			}
		}
		
		/**
		 * Ensures the agent handler is set on this session.
		 * Creates the handler from agent_name if it doesn't exist.
		 * 
		 * @throws Error if agent not found or handler creation fails
		 */
		private void ensure_agent_handler() throws Error
		{
			// If agent handler already exists, nothing to do
			if (this.agent != null) {
				return;
			}
			
			// Get agent name (default to "just-ask" if not set)
			var agent_name = this.agent_name == "" ? "just-ask" : this.agent_name;
			
			// Get agent from manager
			var factory = this.manager.agent_factories.get(agent_name);
			if (factory == null) {
				throw new OllamaError.INVALID_ARGUMENT("Agent '%s' not found in manager", agent_name);
			}
			
			// Create handler from factory
			this.agent = factory.create_agent(this);
		}
		
		/**
		 * Activates an agent for this session.
		 * 
		 * Handles agent changes by creating a new AgentHandler. Messages are already
		 * stored in session.messages, so the new AgentHandler will have access to
		 * the full conversation history when building message arrays.
		 * 
		 * @param agent_name The name of the agent to activate
		 * @throws Error if agent not found or handler creation fails
		 */
		public override void activate_agent(string agent_name) throws Error
		{
			// Save reference to old AgentHandler (if exists)
			var old_agent = this.agent;
			
			// Update agent_name on session
			this.agent_name = agent_name;
			
			// Get agent from manager
			var factory = this.manager.agent_factories.get(agent_name);
			if (factory == null) {
				throw new OllamaError.INVALID_ARGUMENT("Agent '%s' not found in manager", agent_name);
			}
			
			// Create new handler from factory
			var agent = factory.create_agent(this);
			
			// Copy chat from old agent to new agent and connect agent property
			if (old_agent != null) {
				// Copy the chat instance from old agent
				agent.chat = old_agent.chat;
				// Connect the agent property to the new handler
				agent.chat.agent = agent;
			}
			
			this.agent = agent;
			
			
		// Trigger agent_activated signal for UI updates
		// Manager emits this signal, which Window listens to for widget management
		this.manager.agent_activated(factory);
	}
	
	/**
	 * Handler for config.changed signal.
	 * 
	 * Updates Chat's model and options when config changes.
	 * Config changes may update model_options, which affects model_usage.options.
	 * Also rebuilds tools when tool configuration changes.
	 */
	private void on_config_changed()
	{
		// Update Chat properties from model_usage when config changes
		// Agent always exists when config changes, so no null check needed
		if (this.agent != null) {
			this.agent.chat.model = this.model_usage.model;
			
			// Update connection
			if (this.model_usage.connection != "" && this.manager.config.connections.has_key(this.model_usage.connection)) {
				this.agent.chat.connection = this.manager.config.connections.get(this.model_usage.connection);
			}
			
			this.agent.chat.options = this.model_usage.options;
			
			// Rebuild tools when tool configuration changes (ensures Chat has latest tool config/active state)
			this.agent.rebuild_tools();
		}
	}
	
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
		public override async void send(Message message, GLib.Cancellable? cancellable = null) throws Error
		{
			// Add to session history
			this.messages.add(message);
			
			// Emit message_added signal to notify UI (new flow: Session.send() → Manager.message_added() → UI)
			// This is the explicit signal for the new flow, replacing the old add_message signal
			this.manager.message_added(message, this);
			
			// If not user message, we're done
			if (message.role != "user") {
				return;
			}
			
			// User message - ensure agent handler is set (create if needed)
			this.ensure_agent_handler();
			
			// Session has reference to AgentHandler
			if (this.agent != null) {
				yield this.agent.send_async(message, cancellable);
			} else {
				throw new OllamaError.INVALID_ARGUMENT("No agent available for session");
			}
		}
		
	}
}








