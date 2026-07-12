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

namespace OLLMchat.Chatter
{
	/**
	 * Factory for the Chatter agent.
	 *
	 * Creates {@link Agent} instances and builds runtime prompt fragments
	 * such as the environment block for main-chat system messages.
	 */
	public class Factory : OLLMchat.Agent.Factory
	{
		public override string name { get; protected set; default = "chatter"; }
		public override string title { get; protected set; default = "Chatter"; }
		public override string long_title { get; protected set; default = "Chat with summarized history — compact context and session recall links."; }

		public override OLLMchat.Agent.Base create_agent(History.SessionBase session)
		{
			return new Agent(this, session);
		}

		/**
		 * Loads a prompt template from the chat-prompts gresource prefix.
		 *
		 * @param filename template file name (e.g. chatter_initial.md)
		 * @return loaded template with system and user halves parsed
		 */
		public Prompt.Template load_prompt(string filename) throws GLib.Error
		{
			var tpl = new Prompt.Template(filename) {
				source = "resource:///",
				base_dir = "chat-prompts"
			};
			tpl.load();
			return tpl;
		}

		/**
		 * Builds the ''environment'' block for main-chat system prompts.
		 *
		 * Includes date, OS, shell, and workspace path when available.
		 *
		 * @param session session supplying project_path for workspace
		 * @return markdown bullet list for prompt placeholders
		 */
		public string build_environment(History.SessionBase session)
		{
			var ret = "- **Date** - `" + new GLib.DateTime.now_local().format("%Y-%m-%d") + "`";
			var os_info = GLib.Environment.get_os_info("PRETTY_NAME");
			ret += "\n- **OS** - `" + (os_info != null && os_info != "" ? os_info : this.get_os_version()) + "`";
			var shell = this.shell != "" ? this.shell : GLib.Environment.get_variable("SHELL");
			if (shell != null && shell != "") {
				ret += "\n- **Shell** - `" + shell + "`";
			}
			if (session.project_path.strip() != "") {
				ret += "\n- **Workspace** - `" + session.project_path.strip() + "`";
			}
			return ret;
		}
	}
}
