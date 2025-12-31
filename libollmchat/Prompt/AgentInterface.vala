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
	 * Interface for providing context data to CodeAssistant prompts.
	 *
	 * Implementations of this interface provide access to workspace information,
	 * open files, cursor positions, file contents, and selected code.
	 */
	public interface AgentInterface : Object
	{
		/**
		 * Gets the workspace path.
		 *
		 * @return The workspace path, or empty string if not available
		 */
		public abstract string get_workspace_path();
		
		/**
		 * Gets the list of currently open files.
		 *
		 * @return A list of file paths, or empty list if none are open
		 */
		public abstract Gee.ArrayList<string> get_open_files();
		
		/**
		* Gets the cursor position for the currently active file.
		*
		* @return The cursor position (e.g., line number), or empty string if not available
		*/
		public abstract string get_current_cursor_position();
		
		/**
		* Gets the content of a specific line in the currently active file.
		*
		* @param cursor_pos The cursor position (e.g., line number)
		* @return The line content, or empty string if not available
		*/
		public abstract string get_current_line_content(string cursor_pos);
		
		/**
		 * Gets the full contents of a file.
		 *
		 * @param file The file path
		 * @return The file contents, or empty string if not available
		 */
		public abstract string get_file_contents(string file);
		
		/**
		 * Gets the currently selected code.
		 *
		 * @return The selected code text, or empty string if nothing is selected
		 */
		public abstract string get_selected_code();
	}
}

