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

namespace OLLMtools.Child
{
	/**
	 * Request handler for agent tool execution.
	 *
	 * Creates an agent session, sends the query, and returns the result.
	 */
	public class Request : OLLMchat.Tool.RequestBase
	{
		/**
		 * The query parameter from the tool call.
		 */
		public string query { get; set; default = ""; }
		
		/**
		 * Reference to the agent tool that created this request.
		 */
		private Tool agent_tool;
		
		/**
		 * Default constructor.
		 */
		public Request()
		{
		}
		
		/**
		 * Builds permission question for agent tool execution.
		 *
		 * Agent tools don't require permission checks, so this always returns false.
		 *
		 * @return false (no permission required)
		 */
		protected override bool build_perm_question()
		{
			// Agent tools don't require permission checks
			return false;
		}
		
		/**
		 * Executes the agent tool request.
		 *
		 * Creates an agent session, activates it, sends the query,
		 * and returns the final response.
		 *
		 * @return The final response content from the agent
		 * @throws Error if execution fails
		 */
		protected override async string execute_request() throws GLib.Error
		{
			// Get the agent tool from this.tool
			this.agent_tool = (Tool) this.tool;
			
			// Get the Base agent from chat().agent (this.agent is Interface, chat().agent is Base)
			var base_agent = this.agent.chat().agent;
			if (base_agent == null) {
				throw new GLib.IOError.FAILED("Agent tool requires an agent with session");
			}
			
			// Store original session before agent tool execution
			var original_session = base_agent.session;
			var manager = original_session.manager;
			
			// Create agent factory for this agent
			var factory = new Factory(this.agent_tool);
			
			// Create session for agent execution
			var agent_session = this.create_agent_session(factory);
			
			// Activate agent tool session so its messages/streaming reach the UI
			// Note: This will deactivate the original session, but we'll restore it after
			var was_original_active = original_session.is_active;
			if (was_original_active) {
				original_session.deactivate();
			}
			agent_session.activate();
			
			// Create agent instance (this creates Chat internally)
			var agent = factory.create_agent(agent_session);
			
			// Replace placeholders in instructions if needed
			var instructions = this.replace_placeholders(factory.system_message(agent));
			
			// Create user message with query
			var user_message = new OLLMchat.Message("user", this.query);
			
			// Get cancellable from outer session's chat to propagate cancellation
			// This supports nested agent tools: if outer session is cancelled, all nested
			// agent tools will also be cancelled (each agent tool passes its cancellable down)
			var outer_cancellable = this.agent.chat().cancellable;
			
			// Send message through session (standard agent flow)
			// Agent tool session is now active, so streaming goes to UI
			// Pass outer session's cancellable so cancellation propagates through nested calls
			yield agent_session.send(user_message, outer_cancellable);
			
			// Get final response from session messages
			// The agent will have added assistant message to session.messages
			string result = "";
			foreach (var msg in agent_session.messages) {
				if (msg.role == "assistant" && msg.content != "") {
					result = msg.content;
					break;
				}
			}
			
			// Restore original session state after agent tool completes
			agent_session.deactivate();
			if (was_original_active) {
				original_session.activate();
			}
			
			return result;
		}
		
		/**
		 * Creates a session for agent tool execution.
		 *
		 * Creates a real session that:
		 * - Is registered with Manager (has access to tools, config, etc.)
		 * - Is logged and tracked (messages stored in session.messages)
		 * - Is saved to database (full history tracking)
		 * - Is NOT added to manager.sessions list (hidden from UI session list)
		 * - Works with standard agent infrastructure (session-agent-chatcall)
		 *
		 * The session is a real Session, just not visible in the user's session list.
		 * We prevent it from being added to manager.sessions by setting a flag that
		 * Session.on_message_created() checks before adding to the list.
		 *
		 * @param factory The agent factory
		 * @return A session for agent execution (hidden from UI)
		 */
		private OLLMchat.History.SessionBase create_agent_session(Factory factory)
		{
			// Get manager from current session (via chat().agent.session.manager)
			var base_agent = this.agent.chat().agent;
			if (base_agent == null) {
				throw new GLib.IOError.FAILED("Agent tool requires an agent with session");
			}
			var manager = base_agent.session.manager;
			
			// Create real Session (not temporary - it's logged and saved)
			var session = new OLLMchat.History.Session(manager) {
				agent_name = factory.name,
				model_usage = this.get_model_usage_for_agent()
			};
			
			// Mark as agent tool session (UI will filter these out from session list)
			// TODO: Add tool_session property to SessionBase in Phase 2
			// For now, we'll skip this and handle it in Phase 5
			// session.tool_session = true;
			
			// Save to database (so it's logged)
			session.saveToDB();
			
			// Session will be added to manager.sessions normally when messages are created
			// UI will filter out sessions where tool_session == true
			
			return session;
		}
		
		/**
		 * Gets model usage for agent tool execution.
		 *
		 * Uses agent's model preference from config if available, otherwise uses current session's model.
		 *
		 * @return ModelUsage for the agent session
		 */
		private OLLMchat.Settings.ModelUsage get_model_usage_for_agent()
		{
			// Get Base agent from chat().agent
			var base_agent = this.agent.chat().agent;
			if (base_agent == null) {
				throw new GLib.IOError.FAILED("Agent tool requires an agent with session");
			}
			
			// Check if agent tool has model_usage configured
			var manager = base_agent.session.manager;
			// TODO: Check config for agent tool's model_usage in Phase 5
			// For now, use current session's model_usage
			
			// Fall back to current session's model_usage
			return base_agent.session.model_usage;
		}
		
		/**
		 * Replaces placeholders in instructions with actual values.
		 *
		 * @param instructions The instructions string with placeholders
		 * @return Instructions with placeholders replaced
		 */
		private string replace_placeholders(string instructions)
		{
			// TODO: Replace placeholders like {workspace_path}, {open_files}, etc.
			// with actual values from current context
			return instructions;
		}
	}
}
