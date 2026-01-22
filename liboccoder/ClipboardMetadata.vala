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
	 * Implementation of ClipboardMetadata interface for occoder library.
	 * 
	 * Stores clipboard metadata for file references when text is copied from SourceView.
	 * When pasted into ChatInput, it can be replaced with a file reference instead of the actual text.
	 */
	public class ClipboardMetadata : Object, OLLMchatGtk.ClipboardMetadata
	{
		/**
		 * The file that was copied from (may be null if only path is stored).
		 */
		private OLLMfiles.File? file = null;
		
		/**
		 * The file path that was copied from.
		 */
		private string file_path = "";
		
		/**
		 * The starting line number (0-based).
		 */
		private int start_line = -1;
		
		/**
		 * The ending line number (0-based, inclusive).
		 */
		private int end_line = -1;
		
		/**
		 * The text that was copied (used to verify match on paste).
		 * Can be null if no text was copied.
		 */
		private string? stored_text = null;
		
		/**
		 * Static instance for singleton pattern.
		 */
		private static ClipboardMetadata? instance = null;
		
		
		/**
		 * Store clipboard metadata for a file reference.
		 * 
		 * @param file_path The path of the file
		 * @param start_line The starting line number (0-based)
		 * @param end_line The ending line number (0-based, inclusive)
		 * @param text The text that was copied (used to verify match on paste), can be null
		 */
		public void store(string file_path, int start_line, int end_line, string? text)
		{
			// Find the file object from the path
			// Note: This requires access to ProjectManager, but we'll store the path for now
			// and look up the file when needed, or we can store a reference if we have it
			// For now, we'll need to get the file from somewhere - this is a limitation
			// that we'll need to address by passing the file object or having a way to look it up
			
			// Store the path and create a new instance
			instance = new ClipboardMetadata.from_path(file_path, start_line, end_line, text);
		}
		
		/**
		 * Private constructor from file path.
		 */
		private ClipboardMetadata.from_path(string file_path, int start_line, int end_line, string? text)
		{
			// We need to store the path and look up the file later, or accept that we only have the path
			// For now, let's store the path directly
			this.file_path = file_path;
			this.start_line = start_line;
			this.end_line = end_line;
			this.stored_text = text;
		}
		
		/**
		 * Store clipboard metadata for a file reference (internal method using File object).
		 * 
		 * @param file The file object that was copied from
		 * @param start_line The starting line number (0-based)
		 * @param end_line The ending line number (0-based, inclusive)
		 * @param text The text that was copied (used to verify match on paste), can be null
		 */
		public static void store_file(OLLMfiles.File file, int start_line, int end_line, string? text)
		{
			instance = new ClipboardMetadata.from_file(file, start_line, end_line, text);
		}
		
		/**
		 * Private constructor from file object.
		 */
		private ClipboardMetadata.from_file(OLLMfiles.File file, int start_line, int end_line, string? text)
		{
			this.file = file;
			this.file_path = file.path;
			this.start_line = start_line;
			this.end_line = end_line;
			this.stored_text = text;
		}
		
		/**
		 * Check if clipboard text matches stored metadata and return a file reference.
		 * 
		 * @param clipboard_text The text from the clipboard
		 * @return Formatted file reference string if metadata exists and text matches, null otherwise
		 */
		public string? get_file_reference_for_clipboard_text(string clipboard_text)
		{
			if (instance == null) {
				return null;
			}
			
			// Check if clipboard text matches what we stored
			if (instance.stored_text != clipboard_text) {
				return null;
			}
			
			// Return formatted reference
			var result = instance.format_reference();
			// Clear after retrieval (one-time use)
			instance = null;
			return result;
		}
		
		/**
		 * Clear stored metadata.
		 */
		public static void clear()
		{
			instance = null;
		}
		
		/**
		 * Format a file reference string.
		 * 
		 * @return Formatted string like "file:path:123" or "file:path:123-456"
		 */
		private string format_reference()
		{
			// Convert to 1-based line numbers for display
			var start = this.start_line + 1;
			var end = this.end_line + 1;
			
			if (start == end) {
				return "file:%s:%d".printf(this.file_path, start);
			} else {
				return "file:%s:%d-%d".printf(this.file_path, start, end);
			}
		}
	}
}

