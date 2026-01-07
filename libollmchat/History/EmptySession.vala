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
	 * EmptySession represents a session that hasn't started yet (no messages sent).
	 *
	 * This is used to provide a consistent API where Manager always has a session.
	 * When a message is sent, EmptySession converts itself to a real Session.
	 * EmptySession is never saved to the database or added to the sessions list.
	 */
	public class EmptySession : SessionBase
	{
		public EmptySession(Manager manager)
		{
			base(manager);
			// Base constructor already creates chat, client, and sets model
			// Just update chat properties for EmptySession defaults
			if (this.model != "" && this.model != "placeholder") {
				this.chat.model = this.model;
				this.chat.think = true;  // Default to thinking for new chats
			}
		}
		
		public override string display_info {
			owned get { return "New Chat"; }
		}
		
		public override async void save_async(bool update_timestamp = true) { }  // No-op: EmptySession is never saved
		
		public override void saveToDB() { }  // No-op: EmptySession is never saved
		
		public override async void write() throws Error { }  // No-op: EmptySession is never written
		
		public override async void read() throws Error
		{
			throw new GLib.IOError.NOT_SUPPORTED("EmptySession cannot be read from file");
		}
		
		/**
		 * Sends a Message object to this session.
		 * 
		 * Converts EmptySession to a real Session when a message is sent.
		 * Creates a new Session, copies client properties, replaces this EmptySession
		 * in the manager, and then calls send() on the new Session.
		 * 
		 * @param message The message object to send
		 * @param cancellable Optional cancellable for canceling the request
		 * @throws Error if the request fails
		 */
		public override async void send(Message message, GLib.Cancellable? cancellable = null) throws Error
		{
			// Create client for new session, copying from EmptySession's client
			// FIXME remove client later
			var new_client = this.manager.new_client(this.client);
			
			// Update existing chat with new client instead of creating new chat
			// FIXME remove client
			this.client = new_client;
			
			// Convert EmptySession to real Session using updated chat
			// FIXME - agent needs making ? sesison should get old agent, not old chat
			var real_session = new Session(this.manager, this.chat) {
				agent_name = this.agent_name,
				updated_at_timestamp = (new DateTime.now_local()).to_unix()
			};
			
			// Replace EmptySession with real Session in manager
			this.manager.session = real_session;
			
			// Add session to manager.sessions and emit session_added signal immediately
			// This ensures the history widget updates right away
			GLib.debug("[EmptySession.send] Converting to Session: fid=%s, agent=%s, model=%s", 
				real_session.fid, real_session.agent_name, chat.model);
			this.manager.sessions.append(real_session);
			// FIXME - is this needed now?
			this.manager.session_added(real_session);
			GLib.debug("[EmptySession.send] Session added to manager.sessions and session_added emitted");
			
			real_session.activate();
			this.manager.session_activated(real_session);
			
			// Now call send() on the real session
			yield real_session.send(message, cancellable);
		}
		
		/**
		 * Converts EmptySession to a real Session when a message is sent.
		 *
		 * Creates a new Session, copies client properties, replaces this EmptySession
		 * in the manager, and then calls send_message() on the new Session.
		 */
		public override async Response.Chat send_message(string text, GLib.Cancellable? cancellable = null) throws Error
		{
			// Create client for new session, copying from EmptySession's client
			var new_client = this.manager.new_client(this.client);
			
			// Update existing chat with new client instead of creating new chat
			this.client = new_client;
			
			// Convert EmptySession to real Session using updated chat
			var real_session = new Session(this.manager, this.chat) {
				agent_name = this.agent_name,
				updated_at_timestamp = (new DateTime.now_local()).to_unix()
			};
			
			// Replace EmptySession with real Session in manager
			this.manager.session = real_session;
			
			// Add session to manager.sessions and emit session_added signal immediately
			// This ensures the history widget updates right away
			GLib.debug("[EmptySession.send_message] Converting to Session: fid=%s, agent=%s, model=%s", 
				real_session.fid, real_session.agent_name, chat.model);
			this.manager.sessions.append(real_session);
			// FIXME = might not be needed as sesison list gets updated by store
			this.manager.session_added(real_session);
			GLib.debug("[EmptySession.send_message] Session added to manager.sessions and session_added emitted");
			
			
			real_session.activate();
			this.manager.session_activated(real_session);
			
			// Now call send_message on the real session
			return yield real_session.send_message(text, cancellable);
		}
		
		public override async SessionBase? load() throws Error
		{
			// No-op: EmptySession doesn't need loading
			return this;
		}
		
		public override void cancel_current_request() { }  // No-op: EmptySession has no chat, so nothing to cancel
		
		protected override void on_message_created(Message m, ChatContentInterface? content_interface) { }  // No-op: Messages handled by real Session after conversion
		
		protected override void on_stream_chunk(string new_text, bool is_thinking, Response.Chat response) { }  // No-op: EmptySession doesn't handle stream_chunk
		
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			value = Value(pspec.value_type);
			return true;
		}
		
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			return null;
		}
	}
}

