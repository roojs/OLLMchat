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
 *
 * This code is based on the diff-match-patch library:
 * Copyright 2018 The diff-match-patch Authors.
 * https://github.com/google/diff-match-patch
 * Licensed under the Apache License, Version 2.0
 */

namespace OLLMfiles.Diff
{
	/**
	 * Patch operation types.
	 */
	public enum PatchOperation {
		ADD,      // Pure addition
		REMOVE,   // Pure removal
		REPLACE   // Remove + Add (replacement)
	}
	
	/**
	 * Represents a patch operation with line numbers.
	 * 
	 * Patches can be:
	 * - ADD: Inserts new_lines at start_line
	 * - REMOVE: Removes old_lines starting at start_line
	 * - REPLACE: Removes old_lines and inserts new_lines at start_line
	 */
	public class Patch : Object
	{
		/**
		 * Operation type: ADD, REMOVE, or REPLACE.
		 */
		public PatchOperation operation { get; construct; }
		
		/**
		 * Starting line number for old lines (1-based, inclusive).
		 */
		public int old_line_start { get; construct; }
		
		/**
		 * Ending line number for old lines (1-based, inclusive).
		 */
		public int old_line_end { get; construct; }
		
		/**
		 * Starting line number for new lines (1-based, inclusive).
		 */
		public int new_line_start { get; construct; }
		
		/**
		 * Ending line number for new lines (1-based, inclusive).
		 */
		public int new_line_end { get; construct; }
		
		/**
		 * Reference to all old lines array.
		 */
		private string[]? all_old_lines;
		
		/**
		 * Reference to all new lines array.
		 */
		private string[]? all_new_lines;
		
		/**
		 * Get lines to remove (computed from range).
		 * 
		 * @return Array of lines to remove
		 */
		public string[] old_lines()
		{
			
			string[] ret = {};

			if (this.old_line_start > this.old_line_end) {
				return ret;
			}
			if (this.old_line_start < 1 || this.old_line_end > this.all_old_lines.length) {
				return ret;
			}
			ret = new string[this.old_line_end - this.old_line_start + 1];
			for (var i = 0; i < ret.length; i++) {
				ret[i] = this.all_old_lines[(this.old_line_start - 1) + i];
			}
			return ret;
		}
		
		/**
		 * Get lines to add (computed from range).
		 * 
		 * @return Array of lines to add
		 */
		public string[] new_lines()
		{
			string[] ret = {};

			if (this.new_line_start > this.new_line_end) {
				return ret;
			}
			if (this.new_line_start < 1 || this.new_line_end > this.all_new_lines.length) {
				return ret;
			}
			ret = new string[this.new_line_end - this.new_line_start + 1];
			for (var i = 0; i < ret.length; i++) {
				ret[i] = this.all_new_lines[(this.new_line_start - 1) + i];
			}
			return ret;
		}
		
		/**
		 * Get context lines around the patch.
		 * 
		 * @param offset Negative for lines before (e.g., -3), positive for lines after (e.g., +3)
		 * @return Array of context lines
		 */
		public string[] context(int offset)
		{
			string[] ret = {};

			if (offset == 0) {
				return ret;
			}
			
			var patch_start = this.old_line_start - 1; // Convert to 0-based
			var start_pos = offset < 0 ? int.max(0, patch_start + offset) : this.old_line_end;
			var end_pos = offset < 0 ? patch_start : int.min(this.all_old_lines.length, this.old_line_end + offset);
			
			if (end_pos <= start_pos) {
				return ret;
			}
			
			ret = new string[end_pos - start_pos];
			for (var i = 0; i < ret.length; i++) {
				ret[i] = this.all_old_lines[start_pos + i];
			}
			return ret;
		}
		
		/**
		 * Constructor.
		 * 
		 * @param op Operation type
		 * @param old_line_start Starting line number for old lines (1-based, inclusive)
		 * @param old_line_end Ending line number for old lines (1-based, inclusive)
		 * @param new_line_start Starting line number for new lines (1-based, inclusive)
		 * @param new_line_end Ending line number for new lines (1-based, inclusive)
		 * @param all_old_lines Reference to all old lines array
		 * @param all_new_lines Reference to all new lines array
		 */
		public Patch(PatchOperation op, 
			int old_line_start, 
			int old_line_end, 
			int new_line_start, 
			int new_line_end, 
			string[] all_old_lines, 
			string[] all_new_lines)
		{
			Object(
				operation: 			op, 
				old_line_start: 	old_line_start,
				old_line_end: 		old_line_end,
				new_line_start: 	new_line_start,
				new_line_end: 		new_line_end
			);
			this.all_old_lines = all_old_lines;
			this.all_new_lines = all_new_lines;
		}
	}
}

