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

namespace OLLMtools.SessionFetch
{
	/**
	 * Request handler for {{{session_fetch}}} tool calls.
	 */
	public class Request : OLLMchat.Tool.RequestBase
	{
		public string reference { get; set; default = ""; }

		public Request()
		{
		}

		protected override bool build_perm_question()
		{
			return false;
		}

		public override string to_summary()
		{
			return this.reference;
		}

		protected override async string execute_request() throws GLib.Error
		{
			if (this.reference == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("reference parameter is required");
			}

			var dash = this.reference.last_index_of("-");
			int index = -1;
			if (dash < 0 || !int.try_parse(this.reference.substring(dash + 1), out index)) {
				throw new GLib.IOError.INVALID_ARGUMENT("Invalid reference: " + this.reference);
			}

			var messages = this.agent.chat().agent.session.messages;
			if (index < 0 || index >= messages.size) {
				throw new GLib.IOError.INVALID_ARGUMENT("Reference out of range: " + this.reference);
			}

			var msg = messages.get(index);
			if (msg.role == "tool") {
				return msg.name + "\n" + msg.content;
			}
			if (msg.role == "assistant" && msg.tool_calls.size > 0) {
				var ret = "";
				foreach (var tool_call in msg.tool_calls) {
					ret += OLLMchat.Message.fenced(
						"json", Json.gobject_to_data(tool_call, null));
				}
				return ret;
			}
			return msg.content;
		}
	}
}
