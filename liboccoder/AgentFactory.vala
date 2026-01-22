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

namespace OLLMcoder
{
	/**
	 * Code Assistant factory.
	 * 
	 * Combines static sections from resources with dynamic context
	 * to create complete system prompts for code-assistant agents.
	 */
	public class AgentFactory : OLLMchat.Agent.Factory
	{
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
		public AgentFactory(OLLMfiles.ProjectManager project_manager)
		{
			this.name = "code-assistant";
			this.title = "Coding Assistant";
			this.project_manager = project_manager;
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
		 * Gets the workspace path.
		 * 
		 * Overrides Factory default to return active project path from ProjectManager.
		 * 
		 * @return The workspace path, or empty string if not available
		 */
		public override string get_workspace_path()
		{
			if (this.project_manager.active_project != null) {
				return this.project_manager.active_project.path;
			}
			return "";
		}
		
		/**
		 * Gets the list of currently open files, sorted by modification time (most recent first).
		 * Limited to 15 most recent files, ignoring files older than a day.
		 * Always includes the active file if it exists, even if not in recent list.
		 * 
		 * @return A list of file paths
		 */
		public override Gee.ArrayList<string> get_open_files()
		{
			GLib.debug("AgentFactory.get_open_files: Starting, active_project=%s, active_file=%s",
				this.project_manager.active_project != null ? this.project_manager.active_project.path : "null",
				this.project_manager.active_file != null ? this.project_manager.active_file.path : "null");
			
			var result = new Gee.ArrayList<string>();
			if (this.project_manager.active_project == null) {
				GLib.debug("AgentFactory.get_open_files: No active project");
				// Even if no active project, include active file if it exists
				if (this.project_manager.active_file != null) {
					GLib.debug("AgentFactory.get_open_files: Adding active_file (no project): %s", this.project_manager.active_file.path);
					result.add(this.project_manager.active_file.path);
				} else {
					GLib.debug("AgentFactory.get_open_files: No active file either");
				}
				return result;
			}
			
			GLib.debug("AgentFactory.get_open_files: Getting recent list from project: %s", this.project_manager.active_project.path);
			var files = this.project_manager.active_project.project_files.get_recent_list(1);
			GLib.debug("AgentFactory.get_open_files: get_recent_list returned %d files", files.size);
			
			// Limit to 15 most recent
			var limited_files = files.size > 15 ? files.slice(0, 15) : files;
			foreach (var file in limited_files) {
				GLib.debug("AgentFactory.get_open_files: Adding recent file: %s (is_active=%s, last_modified=%lld)",
					file.path, file.is_active.to_string(), file.last_modified);
				result.add(file.path);
			}
			
			// Always include active file if it exists and not already in the list
			if (this.project_manager.active_file != null) {
				bool found = false;
				foreach (var path in result) {
					if (path == this.project_manager.active_file.path) {
						found = true;
						break;
					}
				}
				if (!found) {
					GLib.debug("AgentFactory.get_open_files: Adding active_file (not in recent list): %s", this.project_manager.active_file.path);
					// Insert at beginning since it's the current file
					result.insert(0, this.project_manager.active_file.path);
				} else {
					GLib.debug("AgentFactory.get_open_files: Active file already in list: %s", this.project_manager.active_file.path);
				}
			}
			
			GLib.debug("AgentFactory.get_open_files: Returning %d files", result.size);
			return result;
		}
		
		/**
		 * Gets the cursor position for the currently active file.
		 * 
		 * @return The cursor position (line number as string), or empty string if not available
		 */
		public override string get_current_cursor_position()
		{
			if (this.project_manager.active_file == null) {
				return "";
			}
			
			var line = this.project_manager.active_file.get_cursor_position();
			if (line < 0) {
				return "";
			}
			
			return line.to_string();
		}
		
		/**
		 * Gets the content of a specific line in the currently active file.
		 * 
		 * @param cursor_pos The cursor position (line number as string)
		 * @return The line content, or empty string if not available
		 */
		public override string get_current_line_content(string cursor_pos)
		{
			if (this.project_manager.active_file == null) {
				return "";
			}
			
			int line;
			if (!int.try_parse(cursor_pos, out line)) {
				return "";
			}
			
			return this.project_manager.active_file.get_line_content(line);
		}
		
		/**
		 * Gets the full contents of a file.
		 *
		 * Content is read only via the File (buffer). Uses active file when path matches, else
		 * get_file_from_active_project. create_buffer is always called (no-op if buffer exists).
		 * Returns "Problem loading file contents: &lt;path&gt;" if the file is not found. No disk fallback.
		 *
		 * @param file The file path
		 * @return The file contents, or an error message if not available
		 */
		public override string get_file_contents(string file)
		{
			GLib.debug("AgentFactory.get_file_contents: Looking for file: %s", file);

 
			if (this.project_manager.active_file != null 
					&& this.project_manager.active_file.path == file) {
			 
				
				return this.project_manager.active_file.get_contents(200);
			}
			var found_file = this.project_manager.get_file_from_active_project(file);
			if (found_file == null) {
				GLib.critical("Problem loading file contents: %s", file);
				return "Problem loading file contents: " + file;
			}
			this.project_manager.buffer_provider.create_buffer(found_file);
			return found_file.get_contents(20);
		}
		
		/**
		 * Gets the currently selected code from the active file.
		 * 
		 * @return The selected code text, or empty string if nothing is selected
		 */
		public override string get_selected_code()
		{
			if (this.project_manager.active_file == null) {
				return "";
			}
			
			return this.project_manager.active_file.get_selected_code();
		}
		
		/**
		 * Generates the complete system prompt for a code-assistant agent.
		 * 
		 * Overrides Factory.system_message() to generate system prompt with current context.
		 * This includes: introduction, communication rules, tool calling,
		 * search/reading rules, code changes rules, debugging, external APIs,
		 * user info (OS, workspace, shell), and citation format.
		 * 
		 * @param handler Optional Base instance (can access session, client, etc.)
		 * @return Complete system prompt string
		 * @throws Error if system message generation fails
		 */
		public override string system_message(OLLMchat.Agent.Base? handler = null) throws Error
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
		public override string generate_user_prompt(string user_query) throws Error
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
		 * Generates the user info section for system prompt.
		 * 
		 * Coder-specific implementation that includes OS version, workspace path, and shell.
		 * This is specific to code assistants and not needed for simple agents like JustAsk.
		 */
		private string generate_user_info_section()
		{
			var result = "<user_info>\n";
			result += "OS Version: " + this.get_os_version() + "\n";
			
			// Add current date
			var now = new DateTime.now_local();
			var date_str = now.format("%Y-%m-%d");
			result += "Current Date: " + date_str + "\n";
			
			var workspace_path = this.get_workspace_path();
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
		 * Format content with line numbers (e.g. "1: first line", "2: second line").
		 *
		 * @param content The content string
		 * @param start_line_number The starting line number (1-based)
		 * @return Content with line numbers prefixed
		 */
		private string format_with_line_numbers(string content, int start_line_number = 1)
		{
			if (content == null || content == "") {
				return "";
			}
			var lines = content.split("\n");
			var parts = new string[lines.length];
			for (int i = 0; i < lines.length; i++) {
				parts[i] = "%d: %s".printf(start_line_number + i, lines[i]);
			}
			return string.joinv("\n", parts);
		}

		/**
		 * Generates the context data section from application state.
		 * 
		 * Matches Cursor's format with <current_file>, <attached_files>, and <manually_added_selection>.
		 * File contents are shown with line numbers to make it easier to identify which lines to edit.
		 */
		private string generate_context_section()
		{
			
			var result = "<additional_data>\n" +
				"Below are some helpful pieces of information about the current state:\n\n";
			
			// Current file = active file when set, otherwise first in open list
			var open_files = this.get_open_files();
			string? current_file_path = null;
			if (this.project_manager.active_file != null) {
				current_file_path = this.project_manager.active_file.path;
			} else if (open_files.size > 0) {
				current_file_path = open_files[0];
			}

			if (current_file_path != null) {
				var cursor_pos_str = this.get_current_cursor_position();
				var contents = this.get_file_contents(current_file_path);
				var numbered = this.format_with_line_numbers(contents, 1);

				result += "<current_file>\n" +
					"File path: " + current_file_path + "\n";
				if (cursor_pos_str != "") {
					result += "Cursor is at this Line: " + cursor_pos_str + "\n";
				}
				result += "Content of the file with line numbers:\n\n" +
					(numbered != "" ? numbered + "\n" : "") +
					"</current_file>\n\n";
			}

			// Attached files: other open files only (exclude current/active), when any exist
			var attached_count = 0;
			foreach (var path in open_files) {
				if (path == current_file_path) {
					continue;
				}
				var contents = this.get_file_contents(path);
				if (contents == "") {
					continue;
				}
				if (attached_count == 0) {
					result += "<attached_files>\n";
				}
				attached_count++;
				var line_count = contents.split("\n").length;
				var numbered = this.format_with_line_numbers(contents, 1);
				result += "<file_contents path=\"" + path + "\" lines=\"1-" + line_count.to_string() + "\">\n" +
					"File contents with line numbers (e.g. 1: …) to make it easier to identify which lines to edit.\n\n" +
					numbered +
					"\n</file_contents>\n";
			}
			if (attached_count > 0) {
				result += "</attached_files>\n\n";
			}
			
			// Manually added selection (selected code)
			var selection = this.get_selected_code();
			if (selection != "") {
				result += "<manually_added_selection>\n" +
					selection +
					"\n</manually_added_selection>\n\n";
			}
			
			result += "</additional_data>";
			
			return result;
		}
		
		/**
		 * Creates an agent instance for a specific request.
		 * 
		 * Returns an Agent which handles system message regeneration
		 * on each call to include current context.
		 */
		public override OLLMchat.Agent.Base create_agent(OLLMchat.History.SessionBase session)
		{
			// Agent is in the same namespace
			return new Agent(this, session);
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
				GLib.warning("Failed to initialize AgentFactory widget: %s", e.message);
			}
		}
	}
}

