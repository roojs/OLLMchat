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
	 * SessionPlaceholder represents a chat session loaded from the database
	 * but without the chat connected or messages loaded.
	 * 
	 * When load() is called, it creates a real Session, loads the JSON file,
	 * copies messages, and replaces itself in the manager.
	 */
	public class SessionPlaceholder : SessionBase
	{
		public override string fid { get; set; }
		
		public override string display_info {
			owned get {
				return "%s - %d %s".printf(
					this.model,
					this.total_messages,
					this.total_messages == 1 ? "message" : "messages"
				);
			}
		}
		
		
		/**
		 * Default constructor for placeholder session loaded from database.
		 * 
		 * Used with Object.new_with_properties. Manager will be set as a construct property.
		 */
		public SessionPlaceholder(Manager manager)
		{
			base(manager);
			// Manager will be set via Object.new_with_properties as a construct property
		}
		
		/**
		 * Sets the client for this placeholder.
		 * 
		 * Called after construction from database to set up the client.
		 * 
		 * @param client The client to set
		 */
		internal void set_client(Client client)
		{
			this.client = client;
		}
		
		/**
		 * Loads the session from JSON file and converts to a real Session.
		 * 
		 * This method:
		 * a) Creates a new Session with chat
		 * b) Loads the JSON file into a SessionJson
		 * c) Copies messages from SessionJson into Session
		 * d) Removes itself from manager.sessions and fires remove_chat signal
		 * e) Adds the new Session to manager.sessions and fires add_chat signal
		 * 
		 * @throws Error if loading fails
		 */
		public override async SessionBase? load() throws Error
		{
			GLib.debug("SessionPlaceholder.load");
			// a) Create a new Session with chat
			var real_session = new Session(this.manager, new Call.Chat(this.manager.new_client()));
			
			// copy the tools
			// Copy properties from placeholder to real session
			real_session.id = this.id;
            real_session.fid = this.fid;
			real_session.updated_at_timestamp = this.updated_at_timestamp;
			real_session.title = this.title;
			real_session.model = this.model;
			real_session.total_messages = this.total_messages;
			real_session.total_tokens = this.total_tokens;
			real_session.duration_seconds = this.duration_seconds;
			real_session.child_chats = this.child_chats;
			
			// b) Load the JSON file into a SessionJson
			// Build full file path
			var full_path = GLib.Path.build_filename(this.manager.history_dir, this.to_path() + ".json");
			GLib.debug("SessionPlaceholder.load: Loading JSON from: %s", full_path);
			
			var file = GLib.File.new_for_path(full_path);
			if (!file.query_exists()) {
				throw new GLib.FileError.NOENT("File not found: " + full_path);
			}
			
			// Read file contents
			uint8[] data;
			string etag;
			yield file.load_contents_async(null, out data, out etag);
			GLib.debug("SessionPlaceholder.load: Read %d bytes from JSON file", data.length);
			
			// Parse JSON
			var parser = new Json.Parser();
			try {
				parser.load_from_data((string)data, -1);
				GLib.debug("SessionPlaceholder.load: JSON parsed successfully");
			} catch (GLib.Error e) {
				GLib.debug("SessionPlaceholder.load: JSON parse failed: %s", e.message);
				throw new GLib.IOError.FAILED("Failed to parse JSON: " + e.message);
			}
			
			var root_node = parser.get_root();
			if (root_node == null || root_node.get_node_type() != Json.NodeType.OBJECT) {
				GLib.debug("SessionPlaceholder.load: Invalid JSON root node");
				throw new GLib.FileError.INVAL("Invalid JSON: root is not an object");
			}
			GLib.debug("SessionPlaceholder.load: JSON root node is valid object");
			
			// Deserialize JSON data into SessionJson
			var json_session = Json.gobject_deserialize(typeof(SessionJson), root_node) as SessionJson;
			if (json_session == null) {
				GLib.debug("SessionPlaceholder.load: Failed to deserialize SessionJson");
				throw new GLib.FileError.INVAL("Failed to deserialize SessionJson from JSON");
			}
			GLib.debug("SessionPlaceholder.load: SessionJson deserialized successfully (id=%lld, model='%s', title='%s', messages=%d)", 
				json_session.id, json_session.model, json_session.title, json_session.messages.size);
			
			// Copy properties from JSON to real session (in case they differ from DB)
			//real_session.id = json_session.id;
			//real_session.updated_at_timestamp = json_session.updated_at_timestamp;
			//real_session.title = json_session.title;
			//real_session.model = json_session.model;
			//real_session.child_chats = json_session.child_chats;
			
			// c) Copy messages from SessionJson into Session
			// First, restore all messages to session.messages (including special types)
			GLib.debug("SessionPlaceholder.load: Copying %d messages from SessionJson to Session", json_session.messages.size);
			int msg_index = 0;
			foreach (var msg in json_session.messages) {
				msg_index++;
				msg.message_interface = real_session.chat;
				real_session.messages.add(msg);
				
				// Debug: Print truncated content for each message
				string content_preview = msg.content.length > 20 ? msg.content.substring(0, 20) + "..." : msg.content;
				string thinking_preview = msg.thinking.length > 20 ? msg.thinking.substring(0, 20) + "..." : msg.thinking;
				GLib.debug("SessionPlaceholder.load: Copied message %d/%d (role='%s', content='%s', thinking='%s')", 
					msg_index, json_session.messages.size, msg.role, content_preview, thinking_preview);
			}

			// Debug: Print how many messages were loaded
			GLib.debug("SessionPlaceholder.load: Loaded %d messages from JSON into real_session.messages", real_session.messages.size);

			// Filter messages to populate chat.messages with only API-compatible messages
			// Filter out special session message types: "think-stream", "content-stream", "user-sent", "ui", "end-stream"
			// Only include standard roles: "system", "user", "assistant", "tool"
			int api_compatible_count = 0;
			foreach (var msg in real_session.messages) {
				switch (msg.role) {
					case "system":
					case "user":
					case "assistant":
					case "tool":
						real_session.chat.messages.add(msg);
						api_compatible_count++;
						break;
					default:
						// Skip non-standard roles
						break;
				}
			}
			GLib.debug("SessionPlaceholder.load: %d messages are API-compatible (added to chat.messages)", api_compatible_count);
			
			// d) Remove itself from manager.sessions and fire remove_chat signal
			this.manager.sessions.remove(this);
			this.manager.session_removed(this);
			
			
			// e) Add the new Session to manager.sessions and fire add_chat signal
			this.manager.sessions.add(real_session);
			this.manager.session_added(real_session);
			return real_session;
		}
		
		protected override void on_message_created(Message m) { }  // No-op: Messages handled by real Session after load()
		
		protected override void on_stream_chunk(string new_text, bool is_thinking, Response.Chat response) { }  // No-op: SessionPlaceholder doesn't handle signals
		
		public override void saveToDB() { }  // No-op: SessionPlaceholder is never saved (already in DB)
		
		public override async void save_async() { }  // No-op: SessionPlaceholder is never saved
		
		public override async void write() throws Error { }  // No-op: SessionPlaceholder is never written
		
		public override async void read() throws Error { }  // No-op: SessionPlaceholder doesn't read itself (use load() instead)
		
		public override async Response.Chat send_message(string text, GLib.Cancellable? cancellable = null) throws Error
		{
			throw new GLib.IOError.NOT_SUPPORTED("SessionPlaceholder cannot send messages");
		}
		
		public override void cancel_current_request() { }  // No-op: SessionPlaceholder has no active requests
		
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			value = Value(pspec.value_type);
			return true;
		}
		
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			// SessionPlaceholder is not serialized
			return null;
		}
	}
}

