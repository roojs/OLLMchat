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
	 * Request handler for ''session_fetch'' tool calls.
	 */
	public class Request : OLLMchat.Tool.RequestBase
	{
		public string reference { get; set; default = ""; }

		public Request()
		{
		}

		public override bool build_perm_question()
		{
			return false;
		}

		public override string to_summary()
		{
			return this.reference;
		}

		protected override async string execute_request() throws GLib.Error
		{
			var messages = this.agent.chat().agent.session.messages;
			if (this.reference == "index") {
				var index_md = "";
				for (var i = 0; i < messages.size; i++) {
					var msg = messages.get(i);
					var preview = msg.content.split("\n")[0];
					if (preview.length > 100) {
						preview = preview.substring(0, 100) + "…";
					}
					switch (msg.role) {
						case "user-sent":
						case "user":
							index_md += "user-%d: %s\n".printf(i, preview);
							break;

						case "think-stream":
							index_md += "think-%d: %s\n".printf(i, preview);
							break;

						case "content-stream":
							if (msg.content.strip() == "") {
								break;
							}
							index_md += "agent-%d: %s\n".printf(i, preview);
							break;

						case "assistant":
							if (msg.tool_calls.size == 0) {
								break;
							}
							index_md += "tool-%d: (tool call)\n".printf(i);
							break;

						case "tool":
							index_md += "tool-%d: %s%s\n".printf(i,
								msg.name != "" ? msg.name + ": " : "", preview);
							break;
					}
				}
				return index_md != "" ? index_md : "(no session messages)";
			}

			var dash = this.reference.last_index_of("-");
			var index = -1;
			if (dash < 0
			    || !int.try_parse(this.reference.substring(dash + 1), out index)
			    || index < 0
			    || index >= messages.size) {
				throw new GLib.IOError.INVALID_ARGUMENT("Invalid or out-of-range reference: " + this.reference
					+ " — call session_fetch with reference \"index\" to list available tags");
			}
			var msg = messages.get(index);
			if (msg.role == "tool") {
				return msg.name + "\n" + msg.content;
			}
			if (msg.role != "assistant" || msg.tool_calls.size == 0) {
				return msg.content;
			}
			var ret = "";
			foreach (var tool_call in msg.tool_calls) {
				ret += OLLMchat.Message.fenced(
					"json", Json.gobject_to_data(tool_call, null));
			}
			return ret;
		}
	}
}
