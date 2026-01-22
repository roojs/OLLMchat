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
	 * SessionPlaceholder represents a chat session loaded from the database
	 * but without the chat connected or messages loaded.
	 *
	 * When load() is called, it creates a real Session, loads the JSON file,
	 * copies messages, and replaces itself in the manager.
	 */
	public class SessionPlaceholder : SessionBase
	{
		
		public override string display_info {
			owned get {
				return "%s - %d %s".printf(
					this.model_usage.model,
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
		 * Converts this(a placeholder)int a real Session by loading it from JSON.
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
			GLib.debug("Converting SessionPlaceholder to Session: %s", this.to_string());
			
			// a) Create a new Session (Chat is created per request by AgentHandler)
			var real_session = new Session(this.manager) {
				id = this.id,
				fid = this.fid,
				updated_at_timestamp = this.updated_at_timestamp,
				title = this.title,
				model_usage = this.model_usage,
				agent_name = this.agent_name,
				total_messages = this.total_messages,
				total_tokens = this.total_tokens,
				duration_seconds = this.duration_seconds,
				child_chats = this.child_chats
			};
			
			// b) Load the JSON file into a SessionJson
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
			
			// Deserialize JSON data into SessionJson
			var json_session = Json.gobject_deserialize(typeof(SessionJson), root_node) as SessionJson;
			if (json_session == null) {
				throw new GLib.FileError.INVAL("Failed to deserialize SessionJson from JSON");
			}
			
			// Copy properties from JSON to real session (in case they differ from DB)
			//real_session.id = json_session.id;
			//real_session.updated_at_timestamp = json_session.updated_at_timestamp;
			//real_session.title = json_session.title;
			//real_session.child_chats = json_session.child_chats;
			// model_usage is reconstructed from DB model field, ignore JSON model_usage
			// agent_name is skipped during JSON deserialization, use database value (already set from placeholder)
			
			// Agent is managed separately, not stored on client
			// Agent selection is handled via agent_name in session
			
			// c) Copy messages from SessionJson into Session
			// First, restore all messages to session.messages (including special types)
			// Chat is created per request by AgentHandler, not stored on Session
			// Messages are stored in session.messages and will be used when Chat is created
			foreach (var msg in json_session.messages) {
				real_session.messages.add(msg);
			}
			
			// d) Find the index of this placeholder in manager.sessions
			uint index;
			if (!this.manager.sessions.find(this, out index)) {
				// Placeholder not found, just append the real session
				this.manager.sessions.append(real_session);
			} else {
				// e) Replace the placeholder with the real session in manager.sessions
				this.manager.sessions.replace_at(index, real_session);
			}
			GLib.debug("resulting  Session: %s", real_session.to_string());
			
			return real_session;
		}
		
		protected override void on_message_created(Message m) { }  // No-op: Messages handled by real Session after load()
		
		public override void saveToDB() { }  // No-op: SessionPlaceholder is never saved (already in DB)
		
		public override async void save_async(bool update_timestamp = true) { }  // No-op: SessionPlaceholder is never saved
		
		public override async void write() throws Error { }  // No-op: SessionPlaceholder is never written
		
		public override async void read() throws Error { }  // No-op: SessionPlaceholder doesn't read itself (use load() instead)
		
		/**
		 * Sends a Message object to this session.
		 * 
		 * SessionPlaceholder cannot send messages - it must be loaded first.
		 * 
		 * @param message The message object to send
		 * @param cancellable Optional cancellable for canceling the request
		 * @throws Error if the request fails
		 */
		public override async void send(Message message, GLib.Cancellable? cancellable = null) throws Error
		{
			throw new GLib.IOError.NOT_SUPPORTED("SessionPlaceholder cannot send messages - load() must be called first");
		}
		
		public override void cancel_current_request() { }  // No-op: SessionPlaceholder has no active requests
		
		/**
		 * Activates an agent for this placeholder session.
		 * 
		 * For SessionPlaceholder, this just updates the agent_name property.
		 * The AgentHandler will be created when load() is called to convert
		 * this placeholder to a real Session.
		 * 
		 * @param agent_name The name of the agent to activate
		 * @throws Error if agent not found
		 */
		public override void activate_agent(string agent_name) throws Error
		{
			// Verify agent exists in manager
			// you cant activate an agent on the placeholder
			// when it's moved into the window it becomdes a session - 
		}
		
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

