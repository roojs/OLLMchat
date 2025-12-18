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

namespace OLLMfiles
{
	/**
	 * Base class for buffer operations with default no-op implementations.
	 * 
	 * Provides a default implementation that does nothing, allowing
	 * libocfiles to work without GTK dependencies. Concrete implementations
	 * (e.g., in liboccoder) can override these methods to provide actual
	 * buffer functionality.
	 */
	public class BufferProviderBase : Object
	{
		/**
		 * Detect programming language from file extension.
		 * 
		 * @param file The file to detect language for
		 * @return Language identifier (e.g., "vala", "python"), or null if not detected
		 */
		public virtual string? detect_language(File file) 
		{ 
			return null; 
		}
		
		/**
		 * Create a buffer for the file.
		 * 
		 * The buffer should be stored on the file object using set_data/get_data.
		 * 
		 * @param file The file to create a buffer for
		 */
		public virtual void create_buffer(File file) 
		{ 
		}
		
		/**
		 * Get text from the buffer, optionally limited to a line range.
		 * 
		 * @param file The file to get text from
		 * @param start_line Starting line number (0-based, inclusive)
		 * @param end_line Ending line number (0-based, inclusive), or -1 for all lines
		 * @return The buffer text, or empty string if not available
		 */
		public virtual string get_buffer_text(File file, int start_line = 0, int end_line = -1) 
		{ 
			return ""; 
		}
		
		/**
		 * Get the total number of lines in the buffer.
		 * 
		 * @param file The file to get line count for
		 * @return Line count, or 0 if not available
		 */
		public virtual int get_buffer_line_count(File file) 
		{ 
			return 0; 
		}
		
		/**
		 * Get the currently selected text and cursor position.
		 * 
		 * @param file The file to get selection from
		 * @param cursor_line Output parameter for cursor line number
		 * @param cursor_offset Output parameter for cursor character offset
		 * @return Selected text, or empty string if nothing is selected
		 */
		public virtual string get_buffer_selection(
			File file, 
			out int cursor_line, 
			out int cursor_offset) 
		{
			cursor_line = 0;
			cursor_offset = 0;
			return "";
		}
		
		/**
		 * Get the content of a specific line.
		 * 
		 * @param file The file to get line from
		 * @param line Line number (0-based)
		 * @return Line content, or empty string if not available
		 */
		public virtual string get_buffer_line(File file, int line) 
		{ 
			return ""; 
		}
		
		/**
		 * Get the current cursor position.
		 * 
		 * @param file The file to get cursor position from
		 * @param line Output parameter for cursor line number
		 * @param offset Output parameter for cursor character offset
		 */
		public virtual void get_buffer_cursor(File file, out int line, out int offset) 
		{
			line = 0;
			offset = 0;
		}
		
		/**
		 * Check if the file has a buffer.
		 * 
		 * @param file The file to check
		 * @return true if buffer exists, false otherwise
		 */
		public virtual bool has_buffer(File file) 
		{ 
			return false; 
		}
	}
}
