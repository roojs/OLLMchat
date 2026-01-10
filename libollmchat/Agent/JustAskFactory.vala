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

namespace OLLMchat.Agent
{
	/**
	 * Just Ask factory - creates simple pass-through agents.
	 *
	 * Returns empty system prompt and passes user input through unchanged.
	 * This is the default factory for general chat interactions.
	 */
	public class JustAskFactory : Factory
	{
		/**
		 * Constructor.
		 */
		public JustAskFactory()
		{
			this.name = "just-ask";
			this.title = "Just Ask";
		}
		
		/**
		 * Creates an agent instance for a specific request.
		 */
		public override Base create_agent(History.SessionBase session)
		{
			return new JustAsk(this, session);
		}
		
		// Default Factory behavior already passes through user input
		// No need to override generate_system_prompt() or generate_user_prompt()
	}
}

