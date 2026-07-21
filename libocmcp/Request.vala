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
 * along with this library; if not, see <https://www.gnu.org/licenses/>.
 */

namespace OLLMmcp
{
	/**
	 * Executes one MCP tools/call with arguments from the agent tool call.
	 *
	 * Created only via {@link Tool.deserialize}; {@link Tool} is always set
	 * before {@link execute_request} runs.
	 */
	public class Request : OLLMchat.Tool.RequestBase
	{
		/** MCP tool arguments (passed through to tools/call). */
		public Json.Object arguments { get; set; default = new Json.Object(); }

		public Request(Json.Object arguments)
		{
			this.arguments = arguments;
		}

		public override bool build_perm_question()
		{
			// Sandbox / config gates network and writes (see 2.11.5).
			return false;
		}

		protected override async string execute_request() throws Error
		{
			return yield ((Tool) this.tool).client.call(
				((Tool) this.tool).factory.name,
				this.arguments
			);
		}
	}
}
