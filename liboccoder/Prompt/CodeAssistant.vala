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

namespace OLLMcoder.Prompt
{
	/**
	 * Code Assistant prompt generator.
	 * 
	 * Combines static sections from resources with dynamic context
	 * to create complete system prompts for code-assistant agents.
	 */
	public class CodeAssistant : OLLMchat.Prompt.BaseAgent
	{
		/**
		 * The provider for context data.
		 */
		private CodeAssistantProvider provider;
		
		/**
		 * ProjectManager instance for project/file management.
		 */
		public OLLMfiles.ProjectManager project_manager { get; private set; }
		
		/**
		 * Cached widget instance (lazy initialization).
		 */
		private OLLMcoder.SourceView? widget = null;
		
		/**
		 * Constructor.
		 * 
		 * Automatically sets shell from SHELL environment variable, falling back to /usr/bin/bash.
		 * The shell property is public and can be overridden after construction if needed.
		 * 
		 * @param project_manager The ProjectManager instance (required)
		 */
		public CodeAssistant(OLLMfiles.ProjectManager project_manager)
		{
			this.name = "code-assistant";
			this.title = "Coding Assistant";
			this.project_manager = project_manager;
			this.provider = new CodeAssistantProvider(project_manager);
			// Set shell from environment variable, with fallback
			this.shell = GLib.Environment.get_variable("SHELL") ?? "/usr/bin/bash";
		}
		
		/**
		 * Returns the active project's path as the working directory for commands.
		 * Falls back to home directory if no project is selected.
		 */
		public override string get_working_directory()
		{
			if (this.project_manager.active_project != null) {
				return this.project_manager.active_project.path;
			}
			return GLib.Environment.get_home_dir();
		}
		
		/**
		 * Generates the complete system prompt for a code-assistant agent.
		 * 
		 * @return Complete system prompt string
		 */
		protected override string generate_system_prompt() throws Error
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
				var cursor_pos_str = this.provider.get_current_cursor_position();
				
				result += "<current_file>\n" +
					"Path: " + current_file + "\n";
				if (cursor_pos_str != "") {
					result += "Line: " + cursor_pos_str + "\n";
				}
				var line_content = this.provider.get_current_line_content(cursor_pos_str);
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
						var line_count = contents.split("\n").length;
						result += "<file_contents path=\"" + file + "\" lines=\"1-" + line_count.to_string() + "\">\n" +
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
		 * 
		 * Returns a CodeAssistantHandler which handles system message regeneration
		 * on each call to include current context.
		 */
		public override Object create_handler(OLLMchat.History.SessionBase session)
		{
			// CodeAssistantHandler is in the same namespace
			return new CodeAssistantHandler(this, session);
		}
		
		/**
		 * Gets the UI widget for this agent.
		 * 
		 * Creates and returns a SourceView with ProjectManager on first call,
		 * waits for initialization to complete before returning.
		 * Reuses the same instance on subsequent calls (lazy initialization).
		 * 
		 * @return The SourceView widget cast as Object, or null if database is not available
		 */
		public override async Object? get_widget()
		{
			// Return cached widget if already created
			if (this.widget != null) {
				return this.widget as Object;
			}
			
			// Database is required for migration check
			if (this.project_manager.db == null) {
				return null;
			}
			
			// Run migration if database file doesn't exist
			var db_file = GLib.File.new_for_path(this.project_manager.db.filename);
			if (!db_file.query_exists()) {
				// Database file doesn't exist - run migration
				var migrator = new OLLMfiles.ProjectMigrate(this.project_manager);
				// Start migration (async, but we don't wait - migration will save to DB when done)
				migrator.migrate_all.begin();
				// Note: migrate_all() will call backupDB() when it completes
			}
			
			// Create SourceView with ProjectManager
			this.widget = new OLLMcoder.SourceView(this.project_manager);
			
			// Initialize widget (load projects, restore state, apply UI state)
			yield this.initialize_widget();
			
			// Return widget (cast as Object)
			return this.widget as Object;
		}
		
		/**
		 * Initializes the widget asynchronously.
		 * 
		 * Loads projects from database, restores active state, and applies UI state.
		 */
		private async void initialize_widget()
		{
			// FIXME = intialize first.. and shwo...
			try {
				// Load projects from database
				this.widget.manager.load_projects_from_db();
				
				// Restore active state (sets manager.active_project and manager.active_file)
				yield this.widget.manager.restore_active_state();
				
				// Apply UI state (opens project/file in editor)
				yield this.widget.apply_manager_state();
			} catch (GLib.Error e) {
				GLib.warning("Failed to initialize CodeAssistant widget: %s", e.message);
			}
		}
	}
}

