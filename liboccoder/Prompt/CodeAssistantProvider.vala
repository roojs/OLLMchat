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
	 * Real implementation of AgentInterface for CodeAssistant.
	 * 
	 * Provides information about open files, active file, cursor positions,
	 * and file contents from the ProjectManager. This class does not manage
	 * files itself - it queries information from the manager.
	 */
	public class CodeAssistantProvider : Object, OLLMchat.Prompt.AgentInterface
	{
		/**
		 * ProjectManager instance for querying file information.
		 */
		private OLLMcoder.ProjectManager manager;
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public CodeAssistantProvider(OLLMcoder.ProjectManager manager)
		{
			this.manager = manager;
		}
		
		/**
		 * Gets the workspace path.
		 * 
		 * @return The workspace path, or empty string if not available
		 */
		public string get_workspace_path()
		{
			if (this.manager.active_project != null) {
				return this.manager.active_project.path;
			}
			return "";
		}
		
		/**
		 * Gets the list of currently open files, sorted by modification time (most recent first).
		 * Limited to 15 most recent files, ignoring files older than a day.
		 * 
		 * @return A list of file paths
		 */
		public Gee.ArrayList<string> get_open_files()
		{
			var result = new Gee.ArrayList<string>();
			if (this.manager.active_project != null) {
				var files = this.manager.active_project.project_files.get_recent_list(1);
				foreach (var file in files) {
					result.add(file.path);
				}
			}
			return result;
		}
		
		/**
		 * Gets the cursor position for the currently active file.
		 * 
		 * @return The cursor position (line number as string), or empty string if not available
		 */
		public string get_current_cursor_position()
		{
			if (this.manager.active_file == null) {
				return "";
			}
			
			var line = this.manager.active_file.get_cursor_position();
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
		public string get_current_line_content(string cursor_pos)
		{
			if (this.manager.active_file == null) {
				return "";
			}
			
			int line;
			if (!int.try_parse(cursor_pos, out line)) {
				return "";
			}
			
			return this.manager.active_file.get_line_content(line);
		}
		
		/**
		 * Gets the full contents of a file.
		 * 
		 * @param file The file path
		 * @return The file contents, or empty string if not available
		 */
		public string get_file_contents(string file)
		{
			// Find file by path in manager's file cache
			var file_base = this.manager.file_cache.get(file);
			if (file_base == null || !(file_base is OLLMcoder.Files.File)) {
				return "";
			}
			
			var found_file = file_base as OLLMcoder.Files.File;
			
			// For active file, return full contents
			// For other files, return first 20 lines
			if (this.manager.active_file != null && this.manager.active_file.path == found_file.path) {
				return found_file.get_contents(200); // 200 = all lines
			} 
			return found_file.get_contents(20); // First 20 lines
		}
		
		/**
		 * Gets the currently selected code from the active file.
		 * 
		 * @return The selected code text, or empty string if nothing is selected
		 */
		public string get_selected_code()
		{
			if (this.manager.active_file == null) {
				return "";
			}
			
			return this.manager.active_file.get_selected_code();
		}
	}
}

