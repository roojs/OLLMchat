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
			// Chat is created per request by AgentHandler, not stored on Session
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
			
			// Convert EmptySession to real Session (Chat is created per request by AgentHandler)
			var real_session = new Session(this.manager) {
				agent_name = this.agent_name,
				updated_at_timestamp = (new DateTime.now_local()).to_unix()
			};
			
			// Replace EmptySession with real Session in manager
			this.manager.session = real_session;
			
			// Add session to manager.sessions and emit session_added signal immediately
			// This ensures the history widget updates right away
			GLib.debug("[EmptySession.send] Converting to Session: fid=%s, agent=%s, model=%s", 
				real_session.fid, real_session.agent_name, real_session.model);
			this.manager.sessions.append(real_session);
			// FIXME - is this needed now?
			this.manager.session_added(real_session);
			GLib.debug("[EmptySession.send] Session added to manager.sessions and session_added emitted");
			
			real_session.activate();
			this.manager.session_activated(real_session);
			
			// Now call send() on the real session
			yield real_session.send(message, cancellable);
		}
		
		
		public override async SessionBase? load() throws Error
		{
			// No-op: EmptySession doesn't need loading
			return this;
		}
		
		public override void cancel_current_request() { }  // No-op: EmptySession has no chat, so nothing to cancel
		
		/**
		 * Activates an agent for this empty session.
		 * 
		 * Creates the AgentHandler for the specified agent. The handler will be
		 * available when the session converts to a real Session.
		 * 
		 * @param agent_name The name of the agent to activate
		 * @throws Error if agent not found or handler creation fails
		 */
		public override void activate_agent(string agent_name) throws Error
		{
			// Save reference to old AgentHandler (if exists)
			
			// Update agent_name on session
			if (this.agent_name == agent_name) {
				return;
			}
			// Get agent from manager
			var base_agent = this.manager.agents.get(agent_name);
			if (base_agent == null) {
				throw new OllamaError.INVALID_ARGUMENT("Agent '%s' not found in manager", agent_name);
			}
			
			// Create handler from agent
			var handler = base_agent.create_handler(this.client, this) as Prompt.AgentHandler;
			
			handler.chat = this.agent.chat; 
			
			// Set new agent handler on session
			this.agent = handler;
			this.agent_name = agent_name;

			
			// Trigger agent_activated signal for UI updates
			this.manager.agent_activated(base_agent);
		}
		
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

