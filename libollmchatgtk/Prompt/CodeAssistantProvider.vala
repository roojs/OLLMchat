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

namespace OLLMchatGtk.Prompt
{
	/**
	 * Real implementation of AgentInterface for CodeAssistant.
	 * 
	 * Tracks open files, active file, cursor positions, and provides
	 * access to file contents and selected code from the editor.
	 */
	public class CodeAssistantProvider : Object, OLLMchat.Prompt.AgentInterface
	{
		/**
		 * List of open files.
		 */
		private Gee.ArrayList<OpenFile> open_files {
			get;
			set;
			default = new Gee.ArrayList<OpenFile>((a, b) => {
				return a.filename == b.filename;
			});
		}
		
		/**
		 * Currently active file (null if none).
		 */
		private OpenFile? active_file = null;
		
		/**
		 * Workspace root path.
		 */
		private string workspace_path;
		
		/**
		 * Constructor.
		 * 
		 * @param workspace_path The workspace root path (empty string if not available)
		 */
		public CodeAssistantProvider(string workspace_path = "")
		{
			this.workspace_path = workspace_path;
		}
		
		/**
		 * Adds a file to the list of open files.
		 * 
		 * @param file The OpenFile object to add
		 */
		public void add_file(OpenFile file)
		{
			// Check if file already exists
			if (this.open_files.contains(file)) {
				return;
			}
			
			// Connect to notify['active'] signal
			file.active_monitor_id = file.notify["active"].connect(() => {
				if (!file.active) {
					// If this file was active and is now inactive, clear active_file
					if (this.active_file == file) {
						this.active_file = null;
					}
					return;
				}
				
				// Clear previous active file
				if (this.active_file != null && this.active_file != file) {
					this.active_file.active = false;
				}
				this.active_file = file;
			});
			
			this.open_files.add(file);
		}
		
		/**
		 * Removes a file from the list of open files.
		 * 
		 * @param file The OpenFile object to remove
		 */
		public void remove_file(OpenFile file)
		{
			if (!this.open_files.contains(file)) {
				return;
			}
			
			// Disconnect signal handler
			if (file.active_monitor_id != 0) {
				file.disconnect(file.active_monitor_id);
				file.active_monitor_id = 0;
			}
			
			// If this was the active file, clear it
			if (this.active_file == file) {
				this.active_file = null;
			}
			
			this.open_files.remove(file);
		}
		
		/**
		 * Gets the workspace path.
		 * 
		 * @return The workspace path, or empty string if not available
		 */
		public string get_workspace_path()
		{
			return this.workspace_path;
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
			var now = new DateTime.now_local();
			var one_day_ago = now.add_days(-1);
			
			// Filter files to only those modified within the last day
			var recent_files = new Gee.ArrayList<OpenFile>();
			foreach (var file in this.open_files) {
				var mtime = file.get_mtime();
				if (mtime > 0) {
					var file_time = new DateTime.from_unix_local(mtime);
					if (file_time.compare(one_day_ago) > 0) {
						recent_files.add(file);
					}
				}
			}
			
			// Sort files by mtime (most recent first)
			recent_files.sort((a, b) => {
				var a_mtime = a.get_mtime();
				var b_mtime = b.get_mtime();
				if (a_mtime > b_mtime) {
					return -1;
				} 
				 if (a_mtime < b_mtime) {
					return 1;
				}
				return 0;
			});
			
			// Limit to 15 most recent
			int count = 0;
			foreach (var file in recent_files) {
				if (count >= 15) {
					break;
				}
				result.add(file.filename);
				count++;
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
			if (this.active_file == null) {
				return "";
			}
			
			var line = this.active_file.get_cursor_position();
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
			if (this.active_file == null) {
				return "";
			}
			
			int line;
			if (!int.try_parse(cursor_pos, out line)) {
				return "";
			}
			
			return this.active_file.get_line_content(line);
		}
		
		/**
		 * Gets the full contents of a file.
		 * 
		 * @param file The file path
		 * @return The file contents, or empty string if not available
		 */
		public string get_file_contents(string file)
		{
			// Create a temporary OpenFile to use with index_of()
			var temp_file = new OpenFile(file);
			var index = this.open_files.index_of(temp_file);
			if (index < 0) {
				return "";
			}
			
			var open_file = this.open_files[index];
			
			// For active file, return full contents
			// For other files, return first 20 lines
			if (this.active_file.filename == open_file.filename) {
				return open_file.get_contents(200); // 200 = all lines
			} 
			return open_file.get_contents(20); // First 20 lines
			
		}
		
		/**
		 * Gets the currently selected code from the active file.
		 * 
		 * @return The selected code text, or empty string if nothing is selected
		 */
		public string get_selected_code()
		{
			if (this.active_file == null) {
				return "";
			}
			
			return this.active_file.get_selected_code();
		}
	}
}
