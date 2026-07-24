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
	 * Tool for recalling stored session messages by Chatter reference tag.
	 */
	public class Tool : OLLMchat.Tool.BaseTool
	{
		public override string name { get { return "session_fetch"; } }
		public override string title { get { return "Session Fetch Tool"; } }
		public override Type config_class() { return typeof(OLLMchat.Settings.BaseToolConfig); }
		public override string example_call {
			get {
				return "{\"name\": \"session_fetch\", \"arguments\": {\"reference\": \"user-12\"}}";
			}
		}
		public override string description { get {
			return """
Retrieve a stored session message by reference tag, or list every available tag with a one-line preview.""";
		} }
		public override string parameter_description { get {
			return """
@param reference string Tag to fetch (user-12, agent-16, tool-19, …), or "index" to list all tags.""";
		} }

		public Tool()
		{
			base();
		}

		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(Request), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}
