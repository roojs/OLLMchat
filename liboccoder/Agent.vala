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
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMcoder
{
	/**
	 * Handler for CodeAssistant agent requests.
	 * 
	 * Extends the base Base to handle system message regeneration
	 * on each call (including replies). The system prompt must be regenerated
	 * to include current context (open files, workspace, etc.).
	 */
	public class Agent : OLLMchat.Agent.Base
	{
		/**
		 * Constructor.
		 * 
		 * @param factory The AgentFactory that created this agent
		 * @param session The session instance (for accessing Manager and tools)
		 */
		public Agent(OLLMchat.Agent.Factory factory, OLLMchat.History.SessionBase session)
		{
			base(factory, session);
		}
		
		/**
		 * Sends a Message object asynchronously with streaming support.
		 * 
		 * For CodeAssistant, this regenerates the system prompt on each call
		 * to include current context. Overrides base implementation to build
		 * complex system prompt with current context.o
		 * 
		 * @param message The message object to send (the user message that was just added to session)
		 * @param cancellable Optional cancellable for canceling the request
		 * @throws Error if the request fails
		 */
		public override async void send_async(OLLMchat.Message message, GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			if (this.session.project_path == "") {
				var af = this.factory as AgentFactory;
				if (af != null && af.project_manager.active_project != null) {
					this.session.project_path = af.project_manager.active_project.path;
				}
			}
			this.session.is_running = true;
			this.session.manager.agent_status_change();
			try {
				var messages = new Gee.ArrayList<OLLMchat.Message>();

				string system_content = this.factory.system_message(this);
				if (system_content != "") {
					var system_msg = new OLLMchat.Message("system", system_content);
					this.session.messages.add(system_msg);
					messages.add(system_msg);
				}

				var user_content = this.factory.generate_user_prompt(message.content);
				this.session.messages.add(new OLLMchat.Message("user", user_content));

				foreach (var msg in this.session.messages) {
					if (msg.role == "user"
						|| msg.role == "assistant" || msg.role == "tool") {
						messages.add(msg);
					}
				}

				yield this.fill_model();

				var response = yield this.chat_call.send(messages, cancellable);
			} finally {
				this.session.is_running = false;
				this.session.manager.agent_status_change();
				GLib.debug("OLLMcoder.Agent.send_async: is_running=false session %s", this.session.fid);
			}
		}
		
	}
}

