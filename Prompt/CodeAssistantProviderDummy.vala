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
	 * Dummy implementation of CodeAssistantProviderInterface.
	 * 
	 * Returns empty strings and empty lists for all methods.
	 * Used as a fallback when no real provider is available.
	 */
	public class CodeAssistantProviderDummy : Object, CodeAssistantProviderInterface
	{
		/**
		 * Gets the workspace path.
		 * 
		 * @return Always returns empty string
		 */
		public string get_workspace_path()
		{
			return "";
		}
		
		/**
		 * Gets the list of currently open files.
		 * 
		 * @return Always returns empty list
		 */
		public Gee.ArrayList<string> get_open_files()
		{
			return new Gee.ArrayList<string>();
		}
		
		/**
		 * Gets the cursor position for a given file.
		 * 
		 * @param file The file path (ignored)
		 * @return Always returns empty string
		 */
		public string get_cursor_position(string file)
		{
			return "";
		}
		
		/**
		 * Gets the content of a specific line in a file.
		 * 
		 * @param file The file path (ignored)
		 * @param cursor_pos The cursor position (ignored)
		 * @return Always returns empty string
		 */
		public string get_line_content(string file, string cursor_pos)
		{
			return "";
		}
		
		/**
		 * Gets the full contents of a file.
		 * 
		 * @param file The file path (ignored)
		 * @return Always returns empty string
		 */
		public string get_file_contents(string file)
		{
			return "";
		}
		
		/**
		 * Gets the currently selected code.
		 * 
		 * @return Always returns empty string
		 */
		public string get_selected_code()
		{
			return "";
		}
	}
}

