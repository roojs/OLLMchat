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
	 * for complete session data including all messages.
	 * 
	 * Properties are wrappers around this.chat.client.model, etc.
	 * Messages come from this.chat.messages with a flag to include extra info during JSON encoding.
	 * 
	 * Session requires a Call.Chat object in its constructor.
	 */
	public class Session : SessionBase
	{
		public Call.Chat chat { get; set; }
		
		// Streaming state tracking
		private Message? current_stream_message = null;
		private bool current_stream_is_thinking = false;
		
		// File ID: Format Y-m-d-H-i-s (e.g., "2025-01-15-14-30-45")
		// Computed property that returns chat.fid
		public override string fid {
			get { return this.chat.fid; }
			set {}
		}
			
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
		 * Constructor requires a Call.Chat object.
		 * Client is created from chat.client.
		 * 
		 * @param manager The history manager
		 * @param chat The chat object (required)
		 */
		public Session(Manager manager, Call.Chat chat)
		{
			base(manager);
			this.chat = chat;
			this.client = chat.client;
		}
		
	/**
	 * Handler for message_created signal from this session's client.
	 * Handles message persistence when a message is created.
	 */
	protected override void on_message_created(Message m)
	{
		// Update chat reference if message_interface is a Chat
		if (m.message_interface is Call.Chat) {
			this.chat = (Call.Chat) m.message_interface;
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
		
		// Ensure session is tracked in Manager
		if (!this.manager.sessions.contains(this)) {
			this.manager.sessions.add(this);
			this.manager.session_added(this);
		}
		
		// Relay to Manager for UI
		this.manager.message_created(m);
		
		// Save session
		this.save_async.begin();
		this.notify_property("display_info");
		this.notify_property("display_title");
	}
		
	/**
	 * Handler for stream_chunk signal from this session's client.
	 * Handles unread tracking and session saving.
	 */
	protected override void on_stream_chunk(string new_text, bool is_thinking, Response.Chat response)
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
				this.current_stream_message = new Message(this.chat, stream_role, new_text);
				this.current_stream_is_thinking = is_thinking;
				this.messages.add(this.current_stream_message);
			} else {
				// Same stream type - append to existing message
				this.current_stream_message.content += new_text;
			}
		}
		
		// When response is done, finalize streaming
		if (response.done) {
			// Create "end-stream" message to signal renderer
			var end_stream_msg = new Message(this.chat, "end-stream", "");
			this.messages.add(end_stream_msg);
			
			// Finalize current stream message
			this.current_stream_message = null;
			this.current_stream_is_thinking = false;
			
			// Emit message_created for final assistant message if it exists and hasn't been emitted yet
			if (response.message != null && response.message.is_llm) {
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
					response.message.message_interface = this.chat;
					// Emit message_created signal
					this.client.message_created(response.message);
				}
			}
			
			this.save_async.begin();
			this.notify_property("display_info");
			this.notify_property("title");
		}
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
				"total_messages INTEGER NOT NULL DEFAULT 0, " +
				"total_tokens INT64 NOT NULL DEFAULT 0, " +
				"duration_seconds INT64 NOT NULL DEFAULT 0, " +
				"fid TEXT NOT NULL" +
				");";
			if (Sqlite.OK != db.db.exec(query, null, out errmsg)) {
				GLib.warning("Failed to create session table: %s", db.db.errmsg());
			}
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
		 */
		public override async void save_async()
		{
			try {
				// Update timestamp
				var now = new DateTime.now_local();
				this.updated_at_timestamp = now.to_unix();
				
				// Update metadata
				this.total_messages = this.messages.size;
				// TODO: Calculate total_tokens and duration_seconds from response metadata
				
				// Generate title if not set
				if (this.title == "" && this.manager.title_generator == null) {
					this.title = "Unknown Chat";
					foreach (var msg in this.messages) {
						// Use "user-sent" messages for title (raw user text before prompt engine modification)
						// Fall back to "user" messages if no "user-sent" messages exist
						if (msg.role == "user-sent") {
							 
							this.title = msg.content;
							break;
						
						} 
						 if (msg.role == "user") {
							// Fallback to regular user messages
						 
							this.title = msg.content;
							break;
							
						}
					}
				} 
				if (this.title == "") {
					// Use generator to create title
					try {
						this.title = yield this.manager.title_generator.to_title(this.chat);
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
					return null;
			}
		}
		
		/**
		 * Sends a message using this session's client.
		 * 
		 * Sets streaming mode and either continues an existing conversation with reply()
		 * or starts a new conversation with chat().
		 * 
		 * @param text The message text to send
		 * @param cancellable Optional cancellable for canceling the request
		 * @return The response from the chat API
		 * @throws Error if the request fails
		 */
		public override async Response.Chat send_message(string text, GLib.Cancellable? cancellable = null) throws Error
		{
			// Set streaming
			this.client.stream = true;
			
			// Check if we should use reply() or chat()
			if (this.chat.streaming_response != null &&
				this.chat.streaming_response.done &&
				this.chat.streaming_response.call != null) {
				// Use reply to continue conversation
				this.chat.cancellable = cancellable;
				return yield this.chat.streaming_response.reply(text);
			}
			
			// First message - use regular chat()
			var response = yield this.client.chat(text, cancellable);
			
			// Store cancellable reference
			if (response.call != null && response.call is Call.Chat) {
				var chat = (Call.Chat) response.call;
				chat.cancellable = cancellable;
			}
			
			return response;
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
			if (this.chat.cancellable != null) {
				this.chat.cancellable.cancel();
			}
		}
		
	}
}








