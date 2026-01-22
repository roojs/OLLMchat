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

namespace OLLMchatGtk
{
	/**
	 * Interface for clipboard metadata storage.
	 * 
	 * Allows SourceView to store file references when copying text,
	 * and ChatInput to retrieve file references when pasting text.
	 * Implementations are provided by libraries with file editing
	 * capabilities (e.g., occoder).
	 */
	public interface ClipboardMetadata : Object
	{
		/**
		 * Store clipboard metadata for a file reference.
		 * 
		 * @param file_path The path of the file
		 * @param start_line The starting line number (0-based)
		 * @param end_line The ending line number (0-based, inclusive)
		 * @param text The text that was copied (used to verify match on paste), can be null
		 */
		public abstract void store(string file_path, int start_line, int end_line, string? text);
		
		/**
		 * Check if clipboard text matches stored metadata and return a file reference.
		 * 
		 * @param clipboard_text The text from the clipboard
		 * @return Formatted file reference string (e.g., "file:path:123" or "file:path:123-456")
		 *         if metadata exists and text matches, null otherwise
		 */
		public abstract string? get_file_reference_for_clipboard_text(string clipboard_text);
	}
}

