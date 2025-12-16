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
 *
 * This code is based on the diff-match-patch library:
 * Copyright 2018 The diff-match-patch Authors.
 * https://github.com/google/diff-match-patch
 * Licensed under the Apache License, Version 2.0
 * Original algorithm by Neil Fraser (fraser@google.com)
 */

namespace OLLMcoder.Diff
{
	/**
	 * Applies patches to text.
	 * 
	 * Takes a list of patches and applies them to the given text,
	 * returning the modified text.
	 */
	public class PatchApplier : Object
	{
		/**
		 * At what point is no match declared (0.0 = perfection, 1.0 = very loose).
		 */
		public double match_threshold { get; set; default = 0.5; }
		
		/**
		 * How far to search for a match (0 = exact location, 1000+ = broad match).
		 */
		public int match_distance { get; set; default = 1000; }
		
		/**
		 * The number of bits in an int.
		 */
		public int match_max_bits { get; set; default = 32; }
		
		/**
		 * Apply patches to text.
		 * 
		 * @param patches List of patches to apply
		 * @param text Text to apply patches to
		 * @return Modified text after applying patches
		 * @throws Error if patch application fails
		 */
		public string apply(Gee.ArrayList<Patch> patches, string text) throws Error
		{
			if (patches.size == 0) {
				return text;
			}
			
			// Split text into lines
			var lines = text.split("\n");
			
			// Apply patches in reverse order to maintain line numbers
			// (applying from end to start prevents line number shifts)
			var sorted_patches = new Gee.ArrayList<Patch>();
			sorted_patches.add_all(patches);
			sorted_patches.sort((a, b) => {
				// Sort by old_line_start descending
				if (a.old_line_start > b.old_line_start) return -1;
				if (a.old_line_start < b.old_line_start) return 1;
				return 0;
			});
			
			foreach (var patch in sorted_patches) {
				this.apply_patch(patch, ref lines);
			}
			
			// Join lines back into text
			return string.joinv("\n", lines);
		}
		
		// Apply a single patch to the line array
		private void apply_patch(Patch patch, ref string[] lines) throws Error
		{
			// Convert 1-based line number to 0-based index
			int line_index = int.max(0, patch.old_line_start - 1);
			var old_count = patch.old_line_end - patch.old_line_start + 1;
			
			switch (patch.operation) {
				case PatchOperation.ADD:
					// Insert new_lines at old_line_start
					this.insert_lines(ref lines, int.min(line_index, lines.length), patch.new_lines());
					break;
					
				case PatchOperation.REMOVE:
					// Remove old_lines starting at old_line_start
					if (line_index >= lines.length) {
						throw new Error.literal(
							0,
							0,
							"Patch REMOVE: old_line_start " + patch.old_line_start.to_string() + " is beyond text length"
						);
					}
					// Try to find matching lines for fuzzy matching
					this.remove_lines(ref lines, this.find_match(lines, patch.old_lines(), line_index), old_count);
					break;
					
				case PatchOperation.REPLACE:
					// Remove old_lines and insert new_lines at old_line_start
					if (line_index >= lines.length) {
						// If beyond end, just add
						this.insert_lines(ref lines, lines.length, patch.new_lines());
						break;
					}
					// Try to find matching lines for fuzzy matching
					int actual_start = this.find_match(lines, patch.old_lines(), line_index);
					this.remove_lines(ref lines, actual_start, old_count);
					this.insert_lines(ref lines, actual_start, patch.new_lines());
					break;
			}
		}
		
		// Find matching lines with fuzzy matching if exact match fails
		private int find_match(string[] lines, string[] pattern_lines, int expected_start)
		{
			// First try exact match at expected location
			if (expected_start >= 0 && expected_start + pattern_lines.length <= lines.length) {
				for (int i = 0; i < pattern_lines.length; i++) {
					if (lines[expected_start + i] != pattern_lines[i]) {
						break;
					}
					if (i == pattern_lines.length - 1) {
						return expected_start;
					}
				}
			}
			
			// Try fuzzy matching within match_distance
			int search_start = int.max(0, expected_start - this.match_distance);
			int search_end = int.min(
				lines.length - pattern_lines.length,
				expected_start + this.match_distance
			);
			
			int best_match = -1;
			double best_score = double.MAX;
			
			for (int start = search_start; start <= search_end; start++) {
				if (start < 0 || start + pattern_lines.length > lines.length) {
					continue;
				}
				
				int matches = 0;
				for (int i = 0; i < pattern_lines.length; i++) {
					if (lines[start + i] == pattern_lines[i]) {
						matches++;
					}
				}
				
				double score = 1.0 - ((double)matches / pattern_lines.length);
				if (this.match_distance > 0) {
					score += (double)(expected_start - start).abs() / this.match_distance;
				}
				
				if (score < best_score && score <= this.match_threshold) {
					best_score = score;
					best_match = start;
				}
			}
			
			if (best_match != -1) {
				return best_match;
			}
			
			// Fallback to expected location (may fail, but we tried)
			return expected_start;
		}
		
		// Insert lines into the array
		private void insert_lines(ref string[] lines, int index, string[] new_lines)
		{
			if (new_lines.length == 0) {
				return;
			}
			
			var new_array = new string[lines.length + new_lines.length];
			
			// Copy lines before insertion point
			for (int i = 0; i < index; i++) {
				new_array[i] = lines[i];
			}
			
			// Insert new lines
			for (int i = 0; i < new_lines.length; i++) {
				new_array[index + i] = new_lines[i];
			}
			
			// Copy lines after insertion point
			for (int i = index; i < lines.length; i++) {
				new_array[i + new_lines.length] = lines[i];
			}
			
			lines = new_array;
		}
		
		// Remove lines from the array
		private void remove_lines(ref string[] lines, int start, int count)
		{
			if (count <= 0 || start < 0 || start >= lines.length) {
				return;
			}
			
			if (start + count > lines.length) {
				count = lines.length - start;
			}
			
			var new_array = new string[lines.length - count];
			
			// Copy lines before removal point
			for (int i = 0; i < start; i++) {
				new_array[i] = lines[i];
			}
			
			// Skip removed lines, copy rest
			for (int i = start + count; i < lines.length; i++) {
				new_array[i - count] = lines[i];
			}
			
			lines = new_array;
		}
	}
}

