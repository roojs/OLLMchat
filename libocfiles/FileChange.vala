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
	 * Represents a single edit operation with range and replacement.
	 * 
	 * Line numbers are 1-based (inclusive start, exclusive end).
	 */
	public class FileChange : Object
	{
		/**
		 * Starting line number (1-based, inclusive).
		 */
		public int start { get; set; default = -1; }
		
		/**
		 * Ending line number (1-based, exclusive).
		 */
		public int end { get; set; default = -1; }
		
		/**
		* Replacement text to insert at the specified range.
		*/
		public string replacement { get; set; default = ""; }
		
		/**
	 	* Normalize indentation of replacement text based on base indentation.
		* 
		* Removes minimum leading whitespace from all lines, then prepends base_indent.
		* 
		* @param base_indent The base indentation string to prepend to each line
		*/
		public void normalize_indentation(string base_indent)
		{
			if (this.replacement.length == 0) {
				return;
			}
			
			var lines = this.replacement.split("\n");
			
			// Find minimum leading whitespace
			int min_indent = int.MAX;
			foreach (var line in lines) {
				if (line.strip().length == 0) {
					continue;
				}
				// Use chug to find prefix length
				var prefix_length = line.length - line.chug().length;
				if (prefix_length < min_indent) {
					min_indent = prefix_length;
				}
			}
			
			string[] ret = {};
			
			foreach (var line in lines) {
				ret += base_indent + (
					(min_indent == int.MAX || line.strip().length == 0) ? "" : 
						line.substring(min_indent));
			}
			
			this.replacement = string.joinv("\n", ret);
		}
	}
}

