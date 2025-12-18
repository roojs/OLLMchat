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
	 * Provides context data for CodeAssistant prompts.
	 * 
	 * Provides information about open files, active file, cursor positions,
	 * and file contents from the ProjectManager. This class does not manage
	 * files itself - it queries information from the manager.
	 */
	public class CodeAssistantProvider : Object
	{
		/**
		 * ProjectManager instance for querying file information.
		 */
		private OLLMfiles.ProjectManager manager;
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public CodeAssistantProvider(OLLMfiles.ProjectManager manager)
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
		 * Always includes the active file if it exists, even if not in recent list.
		 * 
		 * @return A list of file paths
		 */
		public Gee.ArrayList<string> get_open_files()
		{
			GLib.debug("CodeAssistantProvider.get_open_files: Starting, active_project=%s, active_file=%s",
				this.manager.active_project != null ? this.manager.active_project.path : "null",
				this.manager.active_file != null ? this.manager.active_file.path : "null");
			
			var result = new Gee.ArrayList<string>();
			if (this.manager.active_project == null) {
				GLib.debug("CodeAssistantProvider.get_open_files: No active project");
				// Even if no active project, include active file if it exists
				if (this.manager.active_file != null) {
					GLib.debug("CodeAssistantProvider.get_open_files: Adding active_file (no project): %s", this.manager.active_file.path);
					result.add(this.manager.active_file.path);
				} else {
					GLib.debug("CodeAssistantProvider.get_open_files: No active file either");
				}
				return result;
			}
			
			GLib.debug("CodeAssistantProvider.get_open_files: Getting recent list from project: %s", this.manager.active_project.path);
			var files = this.manager.active_project.project_files.get_recent_list(1);
			GLib.debug("CodeAssistantProvider.get_open_files: get_recent_list returned %d files", files.size);
			
			// Limit to 15 most recent
			var limited_files = files.size > 15 ? files.slice(0, 15) : files;
			foreach (var file in limited_files) {
				GLib.debug("CodeAssistantProvider.get_open_files: Adding recent file: %s (is_open=%s, last_modified=%lld)",
					file.path, file.is_open.to_string(), file.last_modified);
				result.add(file.path);
			}
			
			// Always include active file if it exists and not already in the list
			if (this.manager.active_file != null) {
				bool found = false;
				foreach (var path in result) {
					if (path == this.manager.active_file.path) {
						found = true;
						break;
					}
				}
				if (!found) {
					GLib.debug("CodeAssistantProvider.get_open_files: Adding active_file (not in recent list): %s", this.manager.active_file.path);
					// Insert at beginning since it's the current file
					result.insert(0, this.manager.active_file.path);
				} else {
					GLib.debug("CodeAssistantProvider.get_open_files: Active file already in list: %s", this.manager.active_file.path);
				}
			}
			
			GLib.debug("CodeAssistantProvider.get_open_files: Returning %d files", result.size);
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
			GLib.debug("CodeAssistantProvider.get_file_contents: Looking for file: %s", file);
			GLib.debug("CodeAssistantProvider.get_file_contents: file_cache size: %u", this.manager.file_cache.size);
			
			// Find file by path in manager's file cache
			var file_base = this.manager.file_cache.get(file);
			if (file_base == null) {
				GLib.debug("CodeAssistantProvider.get_file_contents: File not found in cache: %s", file);
				return "";
			}
			
			if (!(file_base is OLLMfiles.File)) {
				GLib.debug("CodeAssistantProvider.get_file_contents: File in cache is not a File type: %s", file_base.get_type().name());
				return "";
			}
			
			var found_file = file_base as OLLMfiles.File;
			GLib.debug("CodeAssistantProvider.get_file_contents: File found, is_active=%s, path=%s",
				found_file.is_active.to_string(), found_file.path);
			
			// For active file, return full contents
			// For other files, return first 20 lines
			if (this.manager.active_file != null && this.manager.active_file.path == found_file.path) {
				GLib.debug("CodeAssistantProvider.get_file_contents: Returning full contents (active file)");
				return found_file.get_contents(200); // 200 = all lines
			} 
			GLib.debug("CodeAssistantProvider.get_file_contents: Returning first 20 lines");
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
