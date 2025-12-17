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
	public class CodeAssistant : OLLMagent.BaseAgent
	{
		/**
		 * The provider for context data.
		 */
		private CodeAssistantProvider? provider;
		
		/**
		 * Database instance for ProjectManager (optional).
		 * Set this to enable project/file persistence.
		 */
		public SQ.Database? db { get; set; default = null; }
		
		/**
		 * Cached widget instance (lazy initialization).
		 */
		private OLLMcoder.SourceView? widget = null;
		
		/**
		 * Cached ProjectManager instance (created on demand if widget doesn't exist).
		 */
		private OLLMcoder.ProjectManager? cached_manager = null;
		
		/**
		 * Constructor.
		 * 
		 * @param provider The provider for context data. If null, no context will be provided.
		 */
		public CodeAssistant(CodeAssistantProvider? provider = null)
		{
			this.name = "code-assistant";
			this.title = "Coding Assistant";
			this.provider = provider;
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
			
			if (this.provider != null) {
				var workspace_path = this.provider.get_workspace_path();
				if (workspace_path != "") {
					result += "Workspace Path: " + workspace_path + "\n";
				}
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
			GLib.debug("CodeAssistant.generate_context_section: Starting context generation");
			GLib.debug("CodeAssistant.generate_context_section: widget=%s, provider=%s, db=%s, cached_manager=%s",
				this.widget != null ? "exists" : "null",
				this.provider != null ? "exists" : "null",
				this.db != null ? "exists" : "null",
				this.cached_manager != null ? "exists" : "null");
			
			// Try to initialize provider if widget exists but provider is null
			if (this.provider == null && this.widget != null && this.widget.manager != null) {
				GLib.debug("CodeAssistant.generate_context_section: Creating provider from widget.manager");
				this.provider = new CodeAssistantProvider(this.widget.manager);
				this.cached_manager = this.widget.manager; // Cache the manager reference
				GLib.debug("CodeAssistant.generate_context_section: Provider created from widget, active_project=%s, active_file=%s",
					this.widget.manager.active_project != null ? this.widget.manager.active_project.path : "null",
					this.widget.manager.active_file != null ? this.widget.manager.active_file.path : "null");
			}
			
			// If provider is still null, try to create it from cached manager or create a new ProjectManager
			if (this.provider == null && this.db != null) {
				OLLMcoder.ProjectManager? manager = null;
				
				// Use cached manager if available
				if (this.cached_manager != null) {
					GLib.debug("CodeAssistant.generate_context_section: Using cached_manager");
					manager = this.cached_manager;
				} else if (this.widget != null && this.widget.manager != null) {
					GLib.debug("CodeAssistant.generate_context_section: Using widget.manager");
					// Use widget's manager if widget exists
					manager = this.widget.manager;
					this.cached_manager = manager;
				} else {
					GLib.debug("CodeAssistant.generate_context_section: Creating new ProjectManager from db");
					// Create a new ProjectManager from db (lazy initialization)
					manager = new OLLMcoder.ProjectManager(this.db);
					this.cached_manager = manager;
					// Load projects from database
					manager.load_projects_from_db();
					GLib.debug("CodeAssistant.generate_context_section: Loaded %u projects from db", manager.projects.get_n_items());
					// Try to restore active state synchronously (best effort)
					// Note: restore_active_state is async, but we'll try to get what we can
					// The active project/file should be loaded from DB with is_active flags
				}
				
				if (manager != null) {
					this.provider = new CodeAssistantProvider(manager);
					GLib.debug("CodeAssistant.generate_context_section: Provider created, active_project=%s, active_file=%s",
						manager.active_project != null ? manager.active_project.path : "null",
						manager.active_file != null ? manager.active_file.path : "null");
				}
			}
			
			if (this.provider == null) {
				GLib.debug("CodeAssistant.generate_context_section: provider is null, returning empty context");
				return "";
			}
			
			var workspace_path = this.provider.get_workspace_path();
			var cursor_pos = this.provider.get_current_cursor_position();
			GLib.debug("CodeAssistant.generate_context_section: provider exists, workspace_path='%s', cursor_pos='%s'",
				workspace_path, cursor_pos);
			
			var result = "<additional_data>\n" +
				"Below are some helpful pieces of information about the current state:\n\n";
			
			// Current file (from provider)
			var open_files = this.provider.get_open_files();
			GLib.debug("CodeAssistant.generate_context_section: get_open_files() returned %d files", open_files.size);
			if (open_files.size > 0) {
				foreach (var file_path in open_files) {
					GLib.debug("CodeAssistant.generate_context_section: Open file: %s", file_path);
				}
				
				var current_file = open_files[0];
				var cursor_pos_str = this.provider.get_current_cursor_position();
				
				GLib.debug("CodeAssistant.generate_context_section: Current file: %s, cursor_pos: %s", current_file, cursor_pos_str);
				
				result += "<current_file>\n" +
					"Path: " + current_file + "\n";
				if (cursor_pos_str != "") {
					result += "Line: " + cursor_pos_str + "\n";
				}
				var line_content = this.provider.get_current_line_content(cursor_pos_str);
				GLib.debug("CodeAssistant.generate_context_section: Line content length: %zu", line_content.length);
				if (line_content != "") {
					result += "Line Content: `" + line_content + "`\n";
				}
				result += "</current_file>\n\n";
			} else {
				GLib.debug("CodeAssistant.generate_context_section: No open files found");
			}
			
			// Attached files (all open files with their contents)
			if (open_files.size > 0) {
				result += "<attached_files>\n";
				foreach (var file in open_files) {
					GLib.debug("CodeAssistant.generate_context_section: Getting contents for file: %s", file);
					var contents = this.provider.get_file_contents(file);
					GLib.debug("CodeAssistant.generate_context_section: File contents length: %zu", contents.length);
					if (contents != "") {
						var line_count = contents.split("\n").length;
						result += "<file_contents path=\"" + file + "\" lines=\"1-" + line_count.to_string() + "\">\n" +
							contents +
							"\n</file_contents>\n";
					} else {
						GLib.debug("CodeAssistant.generate_context_section: File contents is empty for: %s", file);
					}
				}
				result += "</attached_files>\n\n";
			}
			
			// Manually added selection (selected code)
			var selection = this.provider.get_selected_code();
			GLib.debug("CodeAssistant.generate_context_section: Selection length: %zu", selection.length);
			if (selection != "") {
				result += "<manually_added_selection>\n" +
					selection +
					"\n</manually_added_selection>\n\n";
			}
			
			result += "</additional_data>";
			
			GLib.debug("CodeAssistant.generate_context_section: Context section length: %zu", result.length);
			if (result.length < 200) {
				GLib.debug("CodeAssistant.generate_context_section: Context preview: %s", result);
			} else {
				GLib.debug("CodeAssistant.generate_context_section: Context preview (first 200 chars): %s", result.substring(0, 200));
			}
			
			return result;
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
				// Ensure provider is set even if widget was cached
				if (this.provider == null && this.widget.manager != null) {
					this.provider = new CodeAssistantProvider(this.widget.manager);
					this.cached_manager = this.widget.manager; // Update cached reference
				}
				return this.widget as Object;
			}
			
			// Database is required for ProjectManager
			if (this.db == null) {
				return null;
			}
			
			// Run migration if database file doesn't exist
			var db_file = GLib.File.new_for_path(this.db.filename);
			if (!db_file.query_exists()) {
				// Database file doesn't exist - run migration
				var project_manager = new OLLMcoder.ProjectManager(this.db);
				var migrator = new OLLMcoder.ProjectMigrate(project_manager);
				migrator.migrate_all();
				// Save migrated data to database file
				this.db.backupDB();
			}
			
			// Create ProjectManager with database
			var project_manager = new OLLMcoder.ProjectManager(this.db);
			
			// Create SourceView with ProjectManager
			this.widget = new OLLMcoder.SourceView(project_manager);
			
			// Cache the manager reference
			this.cached_manager = project_manager;
			
			// Initialize widget (load projects, restore state, apply UI state)
			yield this.initialize_widget();
			
			// Create provider from widget's manager so context can be included in prompts
			if (this.provider == null && this.widget.manager != null) {
				this.provider = new CodeAssistantProvider(this.widget.manager);
				this.cached_manager = this.widget.manager; // Update cached reference
			}
			
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

