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
		
		// File ID: Format Y-m-d-H-i-s (e.g., "2025-01-15-14-30-45")
		// Computed property that returns chat.fid
		public override string fid {
			get { return this.chat.fid; }
			set {}
		}
		
		public override string display_info {
			owned get {
				// Count assistant messages (replies)
				int reply_count = 0;
				foreach (var msg in this.chat.messages) {
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
		 * Handler for chat_send signal from this session's client.
		 * Handles session creation and updates when a chat is sent.
		 */
		protected override void on_chat_send(Call.Chat chat)
		{
			// Update chat reference
			this.chat = chat;
			
			// Ensure session is tracked in Manager
			if (!this.manager.sessions.contains(this)) {
				this.manager.sessions.add(this);
				this.manager.session_added(this);
			}
			
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
			
			// Save when response is done
			if (response.done) {
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
						// Skip system and assistant messages, only use user messages for title
						if (msg.role == "user") {
							// Use original_content if available (before prompt engine modification), otherwise use content
							var title_text = (msg.original_content != "") ? msg.original_content : msg.content;
							if (title_text.strip().length > 0) {
								this.title = title_text;
								break;
							}
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
		
		// Messages wrapper - uses this.chat.messages
		public override Gee.ArrayList<Message> messages {
			owned get {
				return this.chat.messages;
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
		 * Uses this.fid and to_path() to determine where to read from.
		 * Loads into a temporary Session object using Json.Serializable,
		 * copies messages from loaded object to this.chat.messages,
		 * then disposes of the temporary object.
		 * 
		 * @throws Error if read fails
		 */
		public override async void read() throws Error
		{
			 
			
			 
			
			// Build full file path
			var full_path = GLib.Path.build_filename(this.manager.history_dir, this.to_path() + ".json");
			
			var file = GLib.File.new_for_path(full_path);
			if (!file.query_exists()) {
				throw new GLib.FileError.NOENT("File not found: " + full_path);
			}
			
			// Read file contents
			uint8[] data;
			string etag;
			yield file.load_contents_async(null, out data, out etag);
			
			// Parse JSON
			var parser = new Json.Parser();
			try {
				parser.load_from_data((string)data, -1);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to parse JSON: " + e.message);
			}
			
			var root_node = parser.get_root();
			if (root_node == null || root_node.get_node_type() != Json.NodeType.OBJECT) {
				throw new GLib.FileError.INVAL("Invalid JSON: root is not an object");
			}
			
			// Deserialize into a new temporary Session object
			// We need to create a temporary session with manager/client to deserialize properly
			var temp_session = Json.gobject_deserialize(typeof(Session), root_node) as Session;
			if (temp_session == null) {
				throw new GLib.FileError.INVAL("Failed to deserialize Session from JSON");
			}
			
			// Copy properties from temporary session
			this.id = temp_session.id;
			this.updated_at_timestamp = temp_session.updated_at_timestamp;
			this.title = temp_session.title;
			this.model = temp_session.model;
			this.child_chats = temp_session.child_chats;
			
			// Copy messages from temporary session to this.chat.messages
			this.chat.messages.clear();
			foreach (var msg in temp_session.chat.messages) {
				msg.message_interface = this.chat;
				this.chat.messages.add(msg);
			}
			 
		}
		
		/**
		 * Handle JSON property mapping and custom deserialization.
		 */
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name != "messages") {
                value = Value(pspec.value_type);
                return true;
            }
            
				 
				
            this.chat.messages.clear();
            var array = property_node.get_array();
            for (uint i = 0; i < array.get_length(); i++) {
                var element_node = array.get_element(i);
                var msg = Json.gobject_deserialize(typeof(Message), element_node) as Message;
                this.chat.messages.add(msg);
                 
            } 
            // Return a dummy value since messages aren't a settable property
            value = Value(typeof(Gee.ArrayList));
            value.set_object(new Gee.ArrayList<Message>());
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
		 */
		public override async void load() throws Error
		{
			// No-op: Session is already loaded
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








