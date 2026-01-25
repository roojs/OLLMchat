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
	 * Agent instance for agent tool execution.
	 *
	 * Filters tools based on the agent's allowed_tools list.
	 */
	public class Agent : OLLMchat.Agent.Base
	{
		private Gee.ArrayList<string> allowed_tools;
		
		/**
		 * Creates a new Agent instance.
		 *
		 * @param factory The factory that created this agent
		 * @param session The session instance
		 * @param allowed_tools List of tool names the agent can use
		 */
		public Agent(Factory factory, OLLMchat.History.SessionBase session, Gee.ArrayList<string> allowed_tools)
		{
			base(factory, session);
			this.allowed_tools = allowed_tools;
		}
		
	}
}
