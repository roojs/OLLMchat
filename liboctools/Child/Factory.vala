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
	 * Factory class that creates agent instances for agent tools.
	 *
	 * Each agent tool uses this factory to create agent instances that
	 * execute with the agent's instructions and allowed tools.
	 */
	public class Factory : OLLMchat.Agent.Factory
	{
		private Tool agent_tool;
		
		/**
		 * Creates a new Factory instance.
		 *
		 * @param agent_tool The agent tool instance containing all agent configuration
		 */
		public Factory(Tool agent_tool)
		{
			this.agent_tool = agent_tool;
			this.name = agent_tool.agent_name;
			this.title = agent_tool.agent_name;
		}
		
		/**
		 * Returns the system message (agent instructions).
		 *
		 * @param handler Optional agent handler (not used)
		 * @return The agent instructions
		 */
		public override string system_message(OLLMchat.Agent.Base? handler = null) throws GLib.Error
		{
			return this.agent_tool.agent_instructions;
		}
		
		/**
		 * Configures tools for the chat call.
		 *
		 * Filters tools to only include those listed in allowed_tools.
		 * If allowed_tools is empty, no tools are added (clears all tools).
		 *
		 * @param call The Chat call to configure tools for
		 */
		public override void configure_tools(OLLMchat.Call.Chat call)
		{
			// Clear existing tools
			call.tools.clear();
			
			// If no allowed tools specified, agent has no tools
			if (this.agent_tool.agent_tools.size == 0) {
				return;
			}
			
			// Get session from call.agent
			// call.agent is set by Agent.Base constructor before configure_tools() is called
			
			// Add only tools listed in allowed_tools
			foreach (var tool_name in this.agent_tool.agent_tools) {
				if (! call.agent.session.manager.tools.has_key(tool_name)) {
					GLib.warning("Agent tool '%s' requested tool '%s' which is not available", 
						this.name, tool_name);
					continue;
				}
				var tool =  call.agent.session.manager.tools.get(tool_name);
				call.add_tool(tool);
			}
		}
		
		/**
		 * Creates an agent instance for a session.
		 *
		 * @param session The session instance
		 * @return A new Agent instance
		 */
		public override OLLMchat.Agent.Base create_agent(OLLMchat.History.SessionBase session)
		{
			return new Agent(this, session, this.agent_tool.agent_tools);
		}
	}
}
