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
	 * Base class for agent factories.
	 *
	 * Provides common functionality for loading resource sections
	 * based on agent name. Can be used directly as a default implementation
	 * that returns empty system prompt and passes through user input.
	 *
	 * == Example ==
	 *
	 * {{{
	 * // Use as default (no modifications)
	 * var factory = new Agent.Factory();
	 *
	 * // Generate system and user prompts
	 * string system_prompt = factory.system_message(null);
	 * string user_prompt = factory.generate_user_prompt("User question");
	 *
	 * // Or create custom factory
	 * public class MyFactory : Agent.Factory {
	 *     public override string system_message(Base? handler = null) throws Error {
	 *         return "You are a helpful assistant.";
	 *     }
	 * }
	 * }}}
	 */
	public class Factory : Object
	{
		/**
		 * The name of the agent (e.g., "code-assistant").
		 * Used to derive the resource path.
		 */
		public string name { get; protected set; default = ""; }
		
		/**
		 * Display name for UI (e.g., "Code Assistant", "Just Ask").
		 */
		public string title { get; protected set; default = ""; }
		
		/**
		 * User's shell (optional, can be set after construction).
		 */
		public string shell { get; set; default = ""; }
		
		/**
		 * Base path for resources.
		 */
		private const string RESOURCE_BASE_PREFIX = "/ollmchat-agents";
		
		/**
		 * Constructor.
		 */
		public Factory()
		{
		}
		
		/**
		 * Creates an agent instance for a specific request.
		 * 
		 * This method must be overridden in subclasses.
		 * 
		 * @param session The session instance (for accessing Manager and tools)
		 * @return A new agent instance (extends Base)
		 */
		public virtual Object create_agent(History.SessionBase session)
		{
			// This must be overridden
			assert_not_reached();
		}
		
		/**
		 * Gets the workspace path.
		 * 
		 * Default implementation returns empty string. Subclasses can override
		 * to return the active workspace/project path.
		 * 
		 * @return Workspace path, or empty string if not available
		 */
		public virtual string get_workspace_path()
		{
			return "";
		}
		
		/**
		 * Gets OS version directly (implemented here, not a signal).
		 */
		protected string get_os_version()
		{
			// Try to read from /proc/version or use Environment
			try {
				string contents;
				if (GLib.FileUtils.get_contents("/proc/version", out contents)) {
					// Extract kernel version from /proc/version
					var parts = contents.split(" ");
					if (parts.length >= 3) {
						return @"$(parts[0]) $(parts[2])";
					}
				}
			} catch {
				// Fall through to default
			}
			return "linux";
		}
		
		/**
		 * Loads a static section from resources.
		 *
		 * @param section_name Name of the section file (without .md extension)
		 * @return Contents of the resource file
		 */
		protected string load_section(string section_name) throws GLib.Error
		{
			// Try resource:// URI first (bundled resources)
			var resource_path = GLib.Path.build_filename(
				RESOURCE_BASE_PREFIX,
				this.name,
				section_name + ".md"
			);
			var file = GLib.File.new_for_uri(@"resource://$(resource_path)");
			
			if (file.query_exists()) {
				try {
					uint8[] data;
					string etag;
					file.load_contents(null, out data, out etag);
					return (string)data;
				} catch (GLib.Error e) {
					throw new GLib.IOError.FAILED(@"Failed to load resource $(resource_path): $(e.message)");
				}
			}
			
			// Fallback to config directory (if available)
			// Note: This requires BuilderApplication which may not be available in standalone build
			// For now, only use resource:// URI
			
			throw new GLib.IOError.NOT_FOUND(
				"Resource section '"+ section_name + "' not found for agent '" + 
					this.name +"'");
		}
		
		/**
		 * Gets the working directory for command execution.
		 *
		 * Agents that have a context-specific working directory (e.g., a selected project)
		 * should override this method to return that directory path.
		 * Default implementation returns empty string (use current directory).
		 *
		 * @return Working directory path, or empty string to use current directory
		 */
		public virtual string get_working_directory()
		{
			return "";
		}
		
		/**
		 * Gets the UI widget for this agent, if any.
		 *
		 * Agents with UI should override this method to return their widget.
		 * Default implementation returns null (agents without UI).
		 *
		 * @return The UI widget cast as Object, or null if agent has no UI
		 */
		public virtual async Object? get_widget()
		{
			return null;
		}
		
		/**
		 * Generates the user prompt.
		 * Default implementation returns the input text as-is.
		 *
		 * @param user_input The user's input text
		 * @return User prompt string
		 */
		protected virtual string generate_user_prompt(string user_input) throws GLib.Error
		{
			return user_input;
		}
		
		/**
		 * Configures tools for the chat call.
		 * 
		 * Phase 3: Tools are stored on Manager, not Client. Agents should get tools
		 * from Manager and add them to Chat via call.add_tool().
		 * 
		 * Default implementation does nothing. Subclasses should override to add
		 * tools from Manager to the Chat call.
		 * 
		 * @param call The Chat call to configure tools for
		 */
		public virtual void configure_tools(OLLMchat.Call.Chat call)
		{
			// Default implementation: no tools added
			// Subclasses should override to add tools from Manager to Chat
		}
		
		/**
		 * Generates the system message for the agent.
		 * 
		 * Default implementation returns empty string (for simple agents like JustAsk).
		 * Subclasses can override to generate system prompt with current context.
		 * For CodeAssistant, this should include open files, workspace, etc.
		 * 
		 * @param handler Optional Base instance (can access session, client, etc.)
		 * @return System message content, or empty string if no system message needed
		 * @throws Error if system message generation fails
		 */
		public virtual string system_message(Base? handler = null) throws GLib.Error
		{
			return "";
		}
		
		/**
		 * Gets the list of currently open files.
		 * 
		 * Default implementation returns empty list. Subclasses can override
		 * to return the list of open files from their context provider.
		 * 
		 * @return A list of file paths
		 */
		public virtual Gee.ArrayList<string> get_open_files()
		{
			return new Gee.ArrayList<string>();
		}
		
		/**
		 * Gets the cursor position for the currently active file.
		 * 
		 * Default implementation returns empty string. Subclasses can override
		 * to return the cursor position from their context provider.
		 * 
		 * @return The cursor position (line number as string), or empty string if not available
		 */
		public virtual string get_current_cursor_position()
		{
			return "";
		}
		
		/**
		 * Gets the content of a specific line in the currently active file.
		 * 
		 * Default implementation returns empty string. Subclasses can override
		 * to return the line content from their context provider.
		 * 
		 * @param cursor_pos The cursor position (line number as string)
		 * @return The line content, or empty string if not available
		 */
		public virtual string get_current_line_content(string cursor_pos)
		{
			return "";
		}
		
		/**
		 * Gets the full contents of a file.
		 * 
		 * Default implementation returns empty string. Subclasses can override
		 * to return the file contents from their context provider.
		 * 
		 * @param file The file path
		 * @return The file contents, or empty string if not available
		 */
		public virtual string get_file_contents(string file)
		{
			return "";
		}
		
		/**
		 * Gets the currently selected code from the active file.
		 * 
		 * Default implementation returns empty string. Subclasses can override
		 * to return the selected code from their context provider.
		 * 
		 * @return The selected code text, or empty string if nothing is selected
		 */
		public virtual string get_selected_code()
		{
			return "";
		}
	}
}

