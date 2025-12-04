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
	 */
	public abstract class SessionBase : Object, Json.Serializable
	{
		public int64 id { get; set; default = -1; }
		public Client client { get; protected set; }
		
		public int64 updated_at_timestamp { get; set; default = 0; }  // Unix timestamp
		public string title { get; set; default = ""; }
		public int unread_count { get; set; default = 0; }
		public bool is_active { get; protected set; default = false; }
		
		// Wrapper properties around client
		public string model {
			get { return this.client.model; }
			set { this.client.model = value; }
		}
		
		// Display properties for UI
		public string display_title {
			get { return this.title; }
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
		internal Manager manager { get; set; }
		
		// Signal handler IDs for disconnection (UI relay signals)
		protected ulong chat_send_id = 0;
		protected ulong stream_chunk_id = 0;
		protected ulong stream_content_id = 0;
		protected ulong stream_start_id = 0;
		protected ulong tool_message_id = 0;
		protected ulong message_created_id = 0;
		
		// Abstract properties that depend on chat
		public abstract string fid { get; set; }
		public abstract string display_info { owned get; }
		
		/**
		 * Constructor for base class.
		 * 
		 * @param manager The history manager
		 */
		protected SessionBase(Manager manager)
		{
			this.manager = manager;
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
			
			// Connect client signals to Manager handlers (for persistence)
			this.client.stream_chunk.connect(this.on_stream_chunk);
			
			// Connect message_created signal to handler
			this.message_created_id = this.client.message_created.connect(this.on_message_created);
			
			// Connect client signals to relay to UI via Manager
			this.chat_send_id = this.client.chat_send.connect((chat) => {
				this.manager.chat_send(chat);
			});
			this.stream_chunk_id = this.client.stream_chunk.connect((new_text, is_thinking, response) => {
				this.manager.stream_chunk(new_text, is_thinking, response);
			});
			this.stream_content_id = this.client.stream_content.connect((new_text, response) => {
				this.manager.stream_content(new_text, response);
			});
			this.stream_start_id = this.client.stream_start.connect(() => {
				this.manager.stream_start();
			});
			this.tool_message_id = this.client.tool_message.connect((message) => {
				this.manager.tool_message(message);
			});
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
			
			// Disconnect client signals from Manager handlers
			this.client.stream_chunk.disconnect(this.on_stream_chunk);
			this.client.message_created.disconnect(this.on_message_created);
			
			// Disconnect client signals from UI relay
			this.client.disconnect(this.chat_send_id);
			this.client.disconnect(this.stream_chunk_id);
			this.client.disconnect(this.stream_content_id);
			this.client.disconnect(this.stream_start_id);
			this.client.disconnect(this.tool_message_id);
			this.client.disconnect(this.message_created_id);
		}
		
		/**
		 * Handler for message_created signal from this session's client.
		 * Handles message persistence and relays to Manager.
		 * Must be implemented by subclasses.
		 */
		protected abstract void on_message_created(Message m);
		
		/**
		 * Handler for stream_chunk signal from this session's client.
		 * Handles unread tracking and session saving.
		 * Must be implemented by subclasses.
		 */
		protected abstract void on_stream_chunk(string new_text, bool is_thinking, Response.Chat response);
		
		
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
		 */
		public abstract async void save_async();
		
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
		 * @throws Error if loading fails
		 */
		public abstract async void load() throws Error;
		
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
		 * Cancels the current request if one is active.
		 * Must be implemented by subclasses.
		 */
		public abstract void cancel_current_request();
		
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

