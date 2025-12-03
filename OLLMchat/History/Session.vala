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
	 */
	public class Session : Object, Json.Serializable
	{
		public int64 id { get; set; default = -1; }
		public Call.Chat chat { get; set; }
		public string updated_at { get; set; default = ""; }  // Format: Y-m-d H:i:s
		public string title { get; set; default = ""; }
		
		// File ID: Format Y-m-d-H-i-s (e.g., "2025-01-15-14-30-45")
		// Computed property that returns chat.fid
		public string fid {
			get { return this.chat.fid; }
			set {}
		} 
		
		// Wrapper properties around chat.client
		public string model {
			get { return this.chat.client.model; }
			set { this.chat.client.model = value; }
		}
		
		// Metadata flattened on session (not separate class)
		public int total_messages { get; set; default = 0; }
		public int64 total_tokens { get; set; default = 0; }
		public int64 duration_seconds { get; set; default = 0; }
		
		// Child chats as array of filename paths (placeholder - not currently used)
		// Format: "YYYY/mm/dd/h-i-s" (relative file path)
		public Gee.ArrayList<string> child_chats { get; set; default = new Gee.ArrayList<string>(); }
		
		// Manager reference for getting history directory
		private Manager manager;
		
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
		
		public Session(Call.Chat chat, Manager manager)
		{
			this.chat = chat;
			this.manager = manager;
			// fid is a computed property that returns chat.fid
		}
		
		/**
		 * Initialize database table for sessions.
		 */
		public static void initDB(SQ.Database db)
		{
			string errmsg;
			var query = "CREATE TABLE IF NOT EXISTS session (" +
				"id INTEGER PRIMARY KEY, " +
				"updated_at TEXT NOT NULL, " +
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
		public void saveToDB()
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
		}
		
		/**
		 * Save session to both DB and file asynchronously.
		 * Updates metadata and saves to both database and JSON file.
		 */
		public async void save_async()
		{
			try {
				// Update updated_at timestamp
				var now = new DateTime.now_local();
				this.updated_at = now.format("%Y-%m-%d %H:%M:%S");
				
				// Update metadata
				this.total_messages = this.messages.size;
				// TODO: Calculate total_tokens and duration_seconds from response metadata
				
				// Save to database
				this.saveToDB();
				
				// Save to JSON file
				yield this.write();
			} catch (Error e) {
				GLib.warning("Failed to save session: %s", e.message);
			}
		}
		
		// Messages wrapper - uses this.chat.messages
		public Gee.ArrayList<Message> messages {
			get { return this.chat.messages; }
		}
		
		/**
		 * Write session to JSON file.
		 * Uses this.fid and to_path() to determine where to write.
		 * Serializes the session including messages with history info (timestamp, hidden).
		 * 
		 * @throws Error if write fails
		 */
		public async void write() throws Error
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
			yield data_stream.put_string_async(generator.to_data(null), GLib.Priority.DEFAULT, null);
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
		public async void read() throws Error
		{
			 
			
			 
			
			// Build full file path
			var full_path = GLib.Path.build_filename(this.manager.history_dir, this.to_path() + ".json");
			
			var file = GLib.File.new_for_path(full_path);
			if (!file.query_exists()) {
				throw new GLib.IOError.NOENT("File not found: " + full_path);
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
				throw new GLib.IOError.INVAL("Invalid JSON: root is not an object");
			}
			
			// Deserialize into a new temporary Session object
			// Messages will be extracted in deserialize_property
			var temp_session = Json.gobject_deserialize(typeof(Session), root_node) as Session;
			if (temp_session == null) {
				throw new GLib.IOError.FAILED("Failed to deserialize session JSON");
			}
			
			// Extract messages from JSON (temp_session.chat is null, so deserialize_property skipped them)
			var root_obj = root_node.get_object();
			var messages_node = root_obj.get_member("messages");
			if (messages_node != null && messages_node.get_node_type() == Json.NodeType.ARRAY) {
				this.chat.messages.clear();
				var messages_array = messages_node.get_array();
				for (uint i = 0; i < messages_array.get_length(); i++) {
					var msg_node = messages_array.get_element(i);
					var msg = Json.gobject_deserialize(typeof(Message), msg_node) as Message;
					if (msg != null) {
						msg.message_interface = this.chat;
						this.chat.messages.add(msg);
					}
				}
			}
			// Database has: id, updated_at, title, model, total_messages, total_tokens, duration_seconds, fid
			// So we only copy: child_chats and messages
			this.child_chats = temp_session.child_chats;
			
			// Copy messages to this.chat.messages
			this.chat.messages.clear();
			foreach (var msg in temp_session.messages) {
				// Set the message_interface to this.chat
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
            
				// Negative test: if chat is null (temp Session), skip processing
			 
				
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
				case "updated_at":
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
	}
}








