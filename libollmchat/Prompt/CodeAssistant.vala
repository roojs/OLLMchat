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

namespace OLLMchat.Prompt
{
	/**
	 * Code Assistant prompt generator.
	 *
	 * Combines static sections from resources with dynamic context
	 * to create complete system prompts for code-assistant agents.
	 */
	public class CodeAssistant : BaseAgent
	{
		/**
		 * The provider for context data.
		 */
		private AgentInterface provider;
		
		/**
		 * Constructor.
		 *
		 * @param provider The provider for context data. If null, a dummy provider will be used.
		 */
		public CodeAssistant(AgentInterface? provider = null)
		{
			this.name = "code-assistant";
			this.title = "Coding Assistant";
			this.provider = provider ?? new CodeAssistantDummy();
		}
		
		/**
		 * Generates the complete system prompt for a code-assistant agent.
		 * 
		 * Overrides BaseAgent.system_message() to generate system prompt with current context.
		 * This includes: introduction, communication rules, tool calling,
		 * search/reading rules, code changes rules, debugging, external APIs,
		 * user info (OS, workspace, shell), and citation format.
		 * 
		 * @param handler Optional AgentHandler instance (can access session, client, etc.)
		 * @return Complete system prompt string
		 * @throws Error if system message generation fails
		 */
		public override string system_message(OLLMchat.Prompt.AgentHandler? handler = null) throws Error
		{
			return this.generate_introduction() + "\n\n" +
				"<communication>\n" +
				this.load_section("communication") +
				"\n</communication>\n\n" +
				this.load_section("tool_calling") + "\n\n" +
				"<search_and_reading>\n" +
				this.load_section("search_and_reading") +
				"\n</search_and_reading>\n\n" +
				"<making_code_changes>\n" +
				this.load_section("making_code_changes") +
				"\n</making_code_changes>\n\n" +
				this.load_section("debugging") + "\n\n" +
				this.load_section("calling_external_apis") + "\n\n" +
				this.generate_user_info_section() + "\n\n" +
				this.load_section("citation_format");
		}
		
		/**
		 * Generates the user prompt with additional context data.
		 *
		 * Based on Cursor's implementation, this includes:
		 * - <additional_data> section with <current_file>, <attached_files>, <manually_added_selection>
		 * - <user_query> tag with the actual user query
		 *
		 * @param user_query The actual user query/message
		 * @return User prompt string with additional context
		 */
		protected override string generate_user_prompt(string user_query) throws Error
		{
			return this.generate_context_section() + "\n\n" +
				"<user_query>\n" +
				user_query +
				"\n</user_query>";
		}
		
		/**
		 * Generates the introduction section with model name replacement.
		 */
		private string generate_introduction() throws Error
		{
			return this.load_section("introduction").replace("$(model_name)", "an AI");
		}
		
		/**
		 * Generates the user info section using the provider.
		 */
		protected override string generate_user_info_section()
		{
			var result = "<user_info>\n";
			result += "OS Version: " + this.get_os_version() + "\n";
			
			var workspace_path = this.provider.get_workspace_path();
			if (workspace_path != "") {
				result += "Workspace Path: " + workspace_path + "\n";
			}
			
			if (this.shell != "") {
				result += "Shell: " + this.shell + "\n";
			}
			result += "</user_info>";
			return result;
		}
		
		/**
		 * Generates the context data section from application state.
		 *
		 * Matches Cursor's format with <current_file>, <attached_files>, and <manually_added_selection>.
		 */
		private string generate_context_section()
		{
			var result = "<additional_data>\n" +
				"Below are some helpful pieces of information about the current state:\n\n";
			
			// Current file (from provider)
			var open_files = this.provider.get_open_files();
			if (open_files.size > 0) {
				var current_file = open_files[0];
				var cursor_pos = this.provider.get_current_cursor_position();
				
				result += "<current_file>\n" +
					"Path: " + current_file + "\n";
				if (cursor_pos != "") {
					result += "Line: " + cursor_pos + "\n";
				}
				var line_content = this.provider.get_current_line_content(cursor_pos);
				if (line_content != "") {
					result += "Line Content: `" + line_content + "`\n";
				}
				result += "</current_file>\n\n";
			}
			
			// Attached files (all open files with their contents)
			if (open_files.size > 0) {
				result += "<attached_files>\n";
				foreach (var file in open_files) {
					var contents = this.provider.get_file_contents(file);
					if (contents != "") {
						result += "<file_contents path=\"" + file + "\" lines=\"1-" + contents.split("\n").length.to_string() + "\">\n" +
							contents +
							"\n</file_contents>\n";
					}
				}
				result += "</attached_files>\n\n";
			}
			
			// Manually added selection (selected code)
			var selection = this.provider.get_selected_code();
			if (selection != "") {
				result += "<manually_added_selection>\n" +
					selection +
					"\n</manually_added_selection>\n\n";
			}
			
			result += "</additional_data>";
			
			return result;
		}
		
		/**
		 * Creates a handler for a specific request.
		 */
		public override Object create_handler(History.SessionBase session)
		{
			return new AgentHandler(this, session);
		}
		
	}
}

