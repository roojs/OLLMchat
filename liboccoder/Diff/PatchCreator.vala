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

/*
 * STRING HANDLING IN VALA - IMPORTANT NOTES:
 *
 * The original JavaScript code uses UTF-16 strings where:
 *   - .length returns character count (UTF-16 code units)
 *   - substring(start, end) works on CHARACTER positions
 *   - charAt(index) works on CHARACTER positions
 *
 * Vala strings are UTF-8 encoded, which requires different handling:
 *   - .length returns BYTE count (not character count)
 *   - substring(offset, len): offset is BYTE offset, len is BYTE length (both in bytes)
 *     See: https://valadoc.org/glib-2.0/string.substring.html
 *   - char_count() returns the number of characters (not bytes)
 *   - index_of_nth_char(n) converts character position to byte offset
 *   - get_char(byte_offset) gets a character at a byte offset
 *
 * KEY DIFFERENCE: JavaScript substring() uses character positions, but Vala substring() uses
 * byte offsets. This is why we must convert character counts to byte offsets.
 *
 * NAMING CONVENTIONS IN THIS FILE:
 *   - Variables ending in _byte_offset or _byte: byte offsets (for use with substring())
 *   - Variables ending in _char_pos or _char_count: character positions/counts
 *   - Variables ending in _length: usually character counts (from diff_common_prefix/suffix)
 *   - When a function returns a "length" (like diff_common_prefix), it's a CHARACTER count
 *   - Always convert character counts to byte offsets before using substring()
 *
 * EXAMPLE CONVERSION:
 *   int char_count = diff_common_prefix(text1, text2);  // Returns CHARACTER count
 *   int byte_offset = text1.index_of_nth_char(char_count);  // Convert to BYTE offset
 *   string result = text1.substring(byte_offset);  // substring() requires BYTE offset
 */

namespace OLLMcoder.Diff
{
	// Internal use only - diff operations
	private enum DiffOperation
	{
		DELETE = -1,
		EQUAL = 0,
		INSERT = 1
	}
	
	// Internal use only - diff tuple
	private class Diff : Object
	{
		public DiffOperation operation { get; set; }
		public string text { get; set; }
		
		public Diff(DiffOperation op, string text)
		{
			this.operation = op;
			this.text = text;
		}
	}
	
	// Internal use only - half-match result
	private class HalfMatchResult
	{
		public bool success = false;
		public string longtext_prefix = "";
		public string longtext_suffix = "";
		public string shorttext_prefix = "";
		public string shorttext_suffix = "";
		public string common_middle = "";
		
		public void swap()
		{
			var temp_prefix = this.longtext_prefix;
			var temp_suffix = this.longtext_suffix;
			this.longtext_prefix = this.shorttext_prefix;
			this.longtext_suffix = this.shorttext_suffix;
			this.shorttext_prefix = temp_prefix;
			this.shorttext_suffix = temp_suffix;
		}
	}
	
	/**
	 * Creates patches from two text inputs.
	 * 
	 * Computes the differences between text1 and text2 and returns
	 * a list of patches with line numbers.
	 */
	public class PatchCreator : Object
	{
		/**
		 * Number of seconds to map a diff before giving up (0 for infinity).
		 */
		public double diff_timeout { get; set; default = 1.0; }
		
		/**
		 * Chunk size for context length.
		 */
		public int patch_margin { get; set; default = 4; }
		
		/**
		 * Create patches from two texts.
		 * 
		 * @param text1 Original text
		 * @param text2 Modified text
		 * @return List of patches with line numbers
		 */
		public Gee.ArrayList<Patch> create_patches(string text1, string text2)
		{
			var patches = new Gee.ArrayList<Patch>();
			
			// Split texts into lines
			string[] lines1 = text1.split("\n");
			string[] lines2 = text2.split("\n");
			
			// Compute diff between line arrays
			var diffs = this.diff_main_lines(lines1, lines2);
			
			// Convert diffs to patches
			this.convert_diffs_to_patches(diffs, lines1, patches);
			
			return patches;
		}
		
		// Convert diffs to patches with line numbers
		private void convert_diffs_to_patches(Gee.ArrayList<Diff> diffs, string[] original_lines, Gee.ArrayList<Patch> patches)
		{
			var line_pos = 0;  // Current position in original_lines (0-based)
			var i = 0;
			
			while (i < diffs.size) {
				if (diffs.get(i).operation == DiffOperation.EQUAL) {
					// Skip equal lines
					line_pos += diffs.get(i).text.split("\n").length;
					i++;
					continue;
				}
				
				// Collect consecutive DELETE operations
				var delete_lines = new Gee.ArrayList<string>();
				var delete_start = line_pos;
				while (i < diffs.size && diffs.get(i).operation == DiffOperation.DELETE) {
					foreach (var line in diffs.get(i).text.split("\n")) {
						delete_lines.add(line);
					}
					line_pos += diffs.get(i).text.split("\n").length;
					i++;
				}
				
				// Collect consecutive INSERT operations
				var insert_lines = new Gee.ArrayList<string>();
				while (i < diffs.size && diffs.get(i).operation == DiffOperation.INSERT) {
					foreach (var line in diffs.get(i).text.split("\n")) {
						insert_lines.add(line);
					}
					i++;
				}
				
				// Create appropriate patch
				if (delete_lines.size > 0 && insert_lines.size > 0) {
					// REPLACE operation
					patches.add(new Patch(
						PatchOperation.REPLACE,
						delete_start + 1,  // Convert to 1-based
						delete_lines.to_array(),
						insert_lines.to_array()
					));
					continue;
				}
				
				if (delete_lines.size > 0) {
					// REMOVE operation
					patches.add(new Patch(
						PatchOperation.REMOVE,
						delete_start + 1,  // Convert to 1-based
						delete_lines.to_array(),
						new string[0]
					));
					continue;
				}
				
				if (insert_lines.size > 0) {
					// ADD operation
					patches.add(new Patch(
						PatchOperation.ADD,
						line_pos + 1,  // Convert to 1-based
						new string[0],
						insert_lines.to_array()
					));
				}
			}
		}
		
		// Main diff function for line arrays
		private Gee.ArrayList<Diff> diff_main_lines(string[] lines1, string[] lines2)
		{
			// Convert line arrays to single strings with newlines
			var sb1 = new StringBuilder();
			foreach (var line in lines1) {
				sb1.append(line);
				sb1.append("\n");
			}
			
			var sb2 = new StringBuilder();
			foreach (var line in lines2) {
				sb2.append(line);
				sb2.append("\n");
			}
			
			// Set deadline
			if (this.diff_timeout <= 0) {
				return this.diff_main(sb1.str, sb2.str, true, int64.MAX);
			}
			
			int64 deadline = GLib.get_real_time() + (int64)(this.diff_timeout * 1000000);
			return this.diff_main(sb1.str, sb2.str, true, deadline);
		}
		
		// Main diff function
		private Gee.ArrayList<Diff> diff_main(string text1, string text2, bool check_lines, int64 deadline)
		{
			// GLib.debug("DEBUG: diff_main entry: text1.length=%d, text2.length=%d, check_lines=%s", text1.length, text2.length, check_lines.to_string());
			// Check for equality (speedup)
			if (text1 == text2) {
				var diffs = new Gee.ArrayList<Diff>();
				if (text1.length > 0) {
					diffs.add(new Diff(DiffOperation.EQUAL, text1));
				}
				return diffs;
			}
			
			// Trim off common prefix (speedup)
			int prefix_length = this.diff_common_prefix(text1, text2);
			var prefix_byte_offset = text1.index_of_nth_char(prefix_length);
			prefix_byte_offset = prefix_byte_offset > -1 ? prefix_byte_offset : text1.length;
			string text1_after_prefix = text1.substring(prefix_byte_offset);
			string text2_after_prefix = text2.substring(prefix_byte_offset);
			
			// Trim off common suffix (speedup)
			var suffix_length = this.diff_common_suffix(text1_after_prefix, text2_after_prefix);
			var text1_char_count = text1_after_prefix.char_count();
			var text2_char_count = text2_after_prefix.char_count();
			// Ensure suffix_length doesn't exceed string lengths
			suffix_length = int.min(suffix_length, int.min(text1_char_count, text2_char_count));
			var suffix_char_pos = int.max(0, text1_char_count - suffix_length);
			var suffix_byte_offset = int.min(int.max(0, text1_after_prefix.index_of_nth_char(suffix_char_pos)), 
                int.min(text1_after_prefix.length, text2_after_prefix.length));
			string text1_middle = text1_after_prefix.substring(0, suffix_byte_offset);
			string text2_middle = text2_after_prefix.substring(0, suffix_byte_offset);
			
			// Compute the diff on the middle block
			var diffs = this.diff_compute(text1_middle, text2_middle, check_lines, deadline);
			
			// Restore the prefix and suffix
			if (prefix_length > 0) {
				var prefix_byte_offset2 = text1.index_of_nth_char(prefix_length);
				prefix_byte_offset2 = prefix_byte_offset2 > -1 ? prefix_byte_offset2 : text1.length;
				diffs.insert(0, new Diff(DiffOperation.EQUAL, text1.substring(0, prefix_byte_offset2)));
			}
			if (suffix_length > 0) {
				int suffix_start_char = text1_after_prefix.char_count() - suffix_length;
				var suffix_start_byte = text1_after_prefix.index_of_nth_char(suffix_start_char);
				suffix_start_byte = suffix_start_byte > -1 ? suffix_start_byte : 0;
				diffs.add(new Diff(DiffOperation.EQUAL, text1_after_prefix.substring(suffix_start_byte)));
			}
			
			this.diff_cleanup_merge(diffs);
			return diffs;
		}
		
		// Find differences between two texts (assumes no common prefix/suffix)
		private Gee.ArrayList<Diff> diff_compute(string text1, string text2, bool check_lines, int64 deadline)
		{
			// GLib.debug("DEBUG: diff_compute entry: text1.length=%d, text2.length=%d, check_lines=%s", text1.length, text2.length, check_lines.to_string());
			var diffs = new Gee.ArrayList<Diff>();
			
			if (text1.length == 0) {
				// Just add some text (speedup)
				if (text2.length > 0) {
					diffs.add(new Diff(DiffOperation.INSERT, text2));
				}
				return diffs;
			}
			
			if (text2.length == 0) {
				// Just delete some text (speedup)
				diffs.add(new Diff(DiffOperation.DELETE, text1));
				return diffs;
			}
			
			string longtext = text1.length > text2.length ? text1 : text2;
			string shorttext = text1.length > text2.length ? text2 : text1;
			
			var i = longtext.index_of(shorttext);
			if (i != -1) {
				// Shorter text is inside the longer text (speedup)
				diffs.add(new Diff(DiffOperation.INSERT, longtext.substring(0, i)));
				diffs.add(new Diff(DiffOperation.EQUAL, shorttext));
				// Bounds check before substring
				var suffix_start = i + shorttext.length;
				if (suffix_start <= longtext.length) {
					diffs.add(new Diff(DiffOperation.INSERT, longtext.substring(suffix_start)));
				} else {
					diffs.add(new Diff(DiffOperation.INSERT, ""));
				}
				// Swap insertions for deletions if diff is reversed
				if (text1.length > text2.length) {
					diffs.get(0).operation = DiffOperation.DELETE;
					diffs.get(2).operation = DiffOperation.DELETE;
				}
				return diffs;
			}
			
			if (shorttext.length == 1) {
				// Single character string
				diffs.add(new Diff(DiffOperation.DELETE, text1));
				diffs.add(new Diff(DiffOperation.INSERT, text2));
				return diffs;
			}
			
			// Check to see if the problem can be split in two
			var hm = this.diff_half_match(text1, text2);
			if (hm.success) {
				// A half-match was found
				// Map longtext/shorttext back to text1/text2 based on which is longer
				string text1_prefix, text1_suffix, text2_prefix, text2_suffix;
				if (text1.length > text2.length) {
					text1_prefix = hm.longtext_prefix;
					text1_suffix = hm.longtext_suffix;
					text2_prefix = hm.shorttext_prefix;
					text2_suffix = hm.shorttext_suffix;
				} else {
					text1_prefix = hm.shorttext_prefix;
					text1_suffix = hm.shorttext_suffix;
					text2_prefix = hm.longtext_prefix;
					text2_suffix = hm.longtext_suffix;
				}
				var diffs_a = this.diff_main(text1_prefix, text2_prefix, check_lines, deadline);
				var diffs_b = this.diff_main(text1_suffix, text2_suffix, check_lines, deadline);
				// Merge the results
				diffs_a.add(new Diff(DiffOperation.EQUAL, hm.common_middle));
				diffs_a.add_all(diffs_b);
				return diffs_a;
			}
			
			if (check_lines && text1.length > 100 && text2.length > 100) {
				// GLib.debug("DEBUG: diff_compute calling diff_line_mode");
				return this.diff_line_mode(text1, text2, deadline);
			}
			
			// GLib.debug("DEBUG: diff_compute calling diff_bisect");
			return this.diff_bisect(text1, text2, deadline);
		}
		
		// Determine the common prefix of two strings (returns character count)
		private int diff_common_prefix(string text1, string text2)
		{
			// Quick check for common null cases
			if (text1.length == 0 || text2.length == 0) {
				return 0;
			}
			int text1_byte_offset = text1.index_of_nth_char(0);
			int text2_byte_offset = text2.index_of_nth_char(0);
			if (text1_byte_offset == -1 || text2_byte_offset == -1 || text1.get_char(text1_byte_offset) != text2.get_char(text2_byte_offset)) {
				return 0;
			}
			
			// Binary search on character count
			int char_min = 0;
			int char_max = int.min(text1.char_count(), text2.char_count());
			int char_mid = char_max;
			
			while (char_min < char_mid) {
				int text1_mid_byte = text1.index_of_nth_char(char_mid);
				int text2_mid_byte = text2.index_of_nth_char(char_mid);
				if (text1_mid_byte == -1 || text2_mid_byte == -1) {
					char_max = char_mid;
					char_mid = (char_max - char_min) / 2 + char_min;
					continue;
				}
				if (text1.substring(0, text1_mid_byte) == text2.substring(0, text2_mid_byte)) {
					char_min = char_mid;
				} else {
					char_max = char_mid;
				}
				char_mid = (char_max - char_min) / 2 + char_min;
			}
			
			return char_mid;
		}
		
		// Determine the common suffix of two strings (returns character count)
		private int diff_common_suffix(string text1, string text2)
		{
			// Quick check for common null cases
			if (text1.length == 0 || text2.length == 0) {
				return 0;
			}
			int text1_char_count = text1.char_count();
			int text2_char_count = text2.char_count();
			// Check last character
			int text1_last_char_byte = text1.index_of_nth_char(text1_char_count - 1);
			int text2_last_char_byte = text2.index_of_nth_char(text2_char_count - 1);
			if (text1_last_char_byte == -1 || text2_last_char_byte == -1 || 
			    text1.get_char(text1_last_char_byte) != text2.get_char(text2_last_char_byte)) {
				return 0;
			}
			
			// Binary search on character count
			int char_min = 0;
			int char_max = int.min(text1_char_count, text2_char_count);
			int char_mid = char_max;
			
			while (char_min < char_mid) {
				int text1_start_char = text1_char_count - char_mid;
				int text2_start_char = text2_char_count - char_mid;
				int text1_start_byte = text1.index_of_nth_char(text1_start_char);
				int text2_start_byte = text2.index_of_nth_char(text2_start_char);
				if (text1_start_byte == -1 || text2_start_byte == -1) {
					char_max = char_mid;
					char_mid = (char_max - char_min) / 2 + char_min;
					continue;
				}
				if (text1.substring(text1_start_byte) == text2.substring(text2_start_byte)) {
					char_min = char_mid;
				} else {
					char_max = char_mid;
				}
				char_mid = (char_max - char_min) / 2 + char_min;
			}
			
			return char_mid;
		}
		
		// Do the two texts share a substring which is at least half the length of the longer text?
		private HalfMatchResult diff_half_match(string text1, string text2)
		{
			var result = new HalfMatchResult();
			
			if (this.diff_timeout <= 0) {
				// Don't risk returning a non-optimal diff if we have unlimited time
				return result;
			}
			
			string longtext = text1.length > text2.length ? text1 : text2;
			string shorttext = text1.length > text2.length ? text2 : text1;
			
			if (longtext.length < 4 || shorttext.length * 2 < longtext.length) {
				return result;  // Pointless
			}
			
			// First check if the second quarter is the seed for a half-match
			var longtext_char_count = longtext.char_count();
			var hm1 = this.diff_half_match_i(longtext, shorttext, int.min((longtext_char_count + 3) / 4, longtext_char_count - 1));
			// Check again based on the third quarter
			var hm2 = this.diff_half_match_i(longtext, shorttext, int.min((longtext_char_count + 1) / 2, longtext_char_count - 1));
			
			if (!hm1.success && !hm2.success) {
				return result;
			}
			
			var hm = new HalfMatchResult();
			if (!hm2.success) {
				hm = hm1;
			} else if (!hm1.success) {
				hm = hm2;
			} else {
				// Both matched. Select the longest
				hm = hm1.common_middle.length > hm2.common_middle.length ? hm1 : hm2;
			}
			
			// A half-match was found, sort out the return data
			if (text1.length > text2.length) {
				// longtext is text1, shorttext is text2 - values already match
				hm.success = true;
				return hm;
			} else {
				// longtext is text2, shorttext is text1 - need to swap
				hm.success = true;
				hm.swap();
				return hm;
			}
		}
		
		// Does a substring of shorttext exist within longtext such that the substring is at least half the length of longtext?
		// i is a CHARACTER position (not byte offset)
		private HalfMatchResult diff_half_match_i(string longtext, string shorttext, int i)
		{
			var longtext_char_count = longtext.char_count();
			var shorttext_char_count = shorttext.char_count();
			
			// Check bounds (character position)
			if (i < 0 || i >= longtext_char_count) {
				return new HalfMatchResult();
			}
			
			// Convert character position to byte offset for substring operations
			var i_byte_offset = longtext.index_of_nth_char(i);
			if (i_byte_offset < 0) {
				return new HalfMatchResult();
			}
			
			// Start with a 1/4 length substring at position i as a seed (using character count)
			var seed_char_end = int.min(i + longtext_char_count / 4, longtext_char_count);
			if (seed_char_end <= i) {
				return new HalfMatchResult();
			}
			var seed_end_byte = longtext.index_of_nth_char(seed_char_end);
			seed_end_byte = seed_end_byte > -1 ? seed_end_byte : longtext.length;
			var seed = longtext.substring(i_byte_offset, seed_end_byte - i_byte_offset);
			var j_byte = -1;
			var result = new HalfMatchResult();
			
			while ((j_byte = shorttext.index_of(seed, j_byte + 1)) != -1) {
				// Convert j byte offset to character position
				var j_char_pos = shorttext.substring(0, j_byte).char_count();
				if (j_char_pos < 0 || j_char_pos >= shorttext_char_count || i >= longtext_char_count) {
					continue;
				}
				
				// Convert character positions to byte offsets for substring calls
				var i_byte = longtext.index_of_nth_char(i);
				i_byte = i_byte > -1 ? i_byte : longtext.length;
				var j_byte_pos = shorttext.index_of_nth_char(j_char_pos);
				j_byte_pos = j_byte_pos > -1 ? j_byte_pos : shorttext.length;
				
				var prefix_length = this.diff_common_prefix(longtext.substring(i_byte), shorttext.substring(j_byte_pos));
				var suffix_length = this.diff_common_suffix(longtext.substring(0, i_byte), shorttext.substring(0, j_byte_pos));
				
				if (result.common_middle.length < suffix_length + prefix_length &&
				    j_char_pos >= suffix_length && j_char_pos + prefix_length <= shorttext_char_count &&
				    i >= suffix_length && i + prefix_length <= longtext_char_count) {
					// Convert character positions to byte offsets, using int.max/int.min to handle -1 and clamp
					var shorttext_suffix_start_byte = int.max(0, shorttext.index_of_nth_char(
						int.max(0, j_char_pos - suffix_length)));
					var shorttext_prefix_end_byte = int.min(
						int.max(0, shorttext.index_of_nth_char(
							int.min(j_char_pos + prefix_length, shorttext_char_count))),
						shorttext.length);
					var longtext_suffix_start_byte = int.max(0, longtext.index_of_nth_char(
						int.max(0, i - suffix_length)));
					var longtext_prefix_end_byte = int.min(
						int.max(0, longtext.index_of_nth_char(
							int.min(i + prefix_length, longtext_char_count))),
						longtext.length);
					
					// Calculate middle part: from (j_char_pos - suffix_length) to j_char_pos
					var shorttext_middle_start_byte = shorttext_suffix_start_byte;
					var shorttext_middle_end_byte = j_byte_pos;
					if (shorttext_middle_start_byte > shorttext_middle_end_byte) {
						continue; // Invalid range, skip this match
					}
					
					// Calculate prefix part: from j_char_pos to (j_char_pos + prefix_length)
					var shorttext_prefix_start_byte = j_byte_pos;
					var shorttext_prefix_end_byte2 = shorttext_prefix_end_byte;
					if (shorttext_prefix_start_byte > shorttext_prefix_end_byte2) {
						continue; // Invalid range, skip this match
					}
					
					result.common_middle = shorttext.substring(shorttext_middle_start_byte,
                             shorttext_middle_end_byte - shorttext_middle_start_byte) + 
                             shorttext.substring(shorttext_prefix_start_byte, shorttext_prefix_end_byte2 - shorttext_prefix_start_byte);
					result.longtext_prefix = longtext.substring(0, longtext_suffix_start_byte);
					result.longtext_suffix = longtext.substring(longtext_prefix_end_byte);
					result.shorttext_prefix = shorttext.substring(0, shorttext_suffix_start_byte);
					result.shorttext_suffix = shorttext.substring(shorttext_prefix_end_byte);
					result.success = true;
				}
			}
			
			if (result.common_middle.length == 0 || result.common_middle.length * 2 < longtext.length) {
				return new HalfMatchResult();
			}
			
			result.success = true;
			return result;
		}
		
		// Do a quick line-level diff on both strings, then rediff the parts for greater accuracy
		private Gee.ArrayList<Diff> diff_line_mode(string text1, string text2, int64 deadline)
		{
			// GLib.debug("DEBUG: diff_line_mode entry: text1.length=%d, text2.length=%d", text1.length, text2.length);
			// Scan the text on a line-by-line basis first
			var result = this.diff_lines_to_chars(text1, text2);
			// GLib.debug("DEBUG: diff_line_mode after diff_lines_to_chars: chars1.length=%d, chars2.length=%d", result.chars1.length, result.chars2.length);
			
			var diffs = this.diff_main(result.chars1, result.chars2, false, deadline);
			// GLib.debug("DEBUG: diff_line_mode after diff_main: diffs.size=%d", diffs.size);
			
			// Convert the diff back to original text
			this.diff_chars_to_lines(diffs, result.line_array);
			// GLib.debug("DEBUG: diff_line_mode after diff_chars_to_lines");
			// Eliminate freak matches (e.g. blank lines)
			this.diff_cleanup_semantic(diffs);
			// GLib.debug("DEBUG: diff_line_mode after diff_cleanup_semantic: diffs.size=%d", diffs.size);
			
			// Rediff any replacement blocks, this time character-by-character
			// Add a dummy entry at the end
			diffs.add(new Diff(DiffOperation.EQUAL, ""));
			int pointer = 0;
			int count_delete = 0;
			int count_insert = 0;
			var text_delete = new StringBuilder();
			var text_insert = new StringBuilder();
			int loop_iterations = 0;
			
			// GLib.debug("DEBUG: diff_line_mode starting character-by-character rediff loop, initial diffs.size=%d", diffs.size);
			while (pointer < diffs.size) {
				loop_iterations++;
				if (loop_iterations % 100 == 0) {
					// GLib.debug("DEBUG: diff_line_mode loop iteration %d, pointer=%d, diffs.size=%d", loop_iterations, pointer, diffs.size);
				}
				if (loop_iterations > 10000) {
					// GLib.debug("DEBUG: diff_line_mode WARNING - loop iteration limit reached!");
					break;
				}
				switch (diffs.get(pointer).operation) {
					case DiffOperation.INSERT:
						count_insert++;
						text_insert.append(diffs.get(pointer).text);
						pointer++;
						break;
					case DiffOperation.DELETE:
						count_delete++;
						text_delete.append(diffs.get(pointer).text);
						pointer++;
						break;
					case DiffOperation.EQUAL:
						// Upon reaching an equality, check for prior redundancies
						if (count_delete >= 1 && count_insert >= 1) {
							// GLib.debug("DEBUG: diff_line_mode rediffing: delete_len=%d, insert_len=%d", text_delete.str.length, text_insert.str.length);
							// Delete the offending records and add the merged ones
							var remove_start = pointer - count_delete - count_insert;
							for (var k = 0; k < count_delete + count_insert; k++) {
								diffs.remove_at(remove_start);
							}
							pointer = remove_start;
							var sub_diff = this.diff_main(text_delete.str, text_insert.str, false, deadline);
							// GLib.debug("DEBUG: diff_line_mode sub_diff.size=%d", sub_diff.size);
							for (var j = sub_diff.size - 1; j >= 0; j--) {
								diffs.insert(pointer, sub_diff.get(j));
							}
							pointer = pointer + sub_diff.size;
						}
						count_insert = 0;
						count_delete = 0;
						text_delete = new StringBuilder();
						text_insert = new StringBuilder();
						pointer++;
						break;
				}
			}
			
			// Remove the dummy entry at the end
			if (diffs.size > 0 && diffs.get(diffs.size - 1).text == "") {
				diffs.remove_at(diffs.size - 1);
			}
			
			return diffs;
		}
		
		// Split two texts into an array of strings. Reduce the texts to a string of hashes where each Unicode character represents one line
		private class LinesToCharsResult {
			public string chars1;
			public string chars2;
			public Gee.ArrayList<string> line_array;
			
			public LinesToCharsResult(string c1, string c2, Gee.ArrayList<string> la)
			{
				this.chars1 = c1;
				this.chars2 = c2;
				this.line_array = la;
			}
		}
		
		private LinesToCharsResult diff_lines_to_chars(string text1, string text2)
		{
			var line_array = new Gee.ArrayList<string>();
			var line_hash = new Gee.HashMap<string, int>();
			
			// '\x00' is a valid character, but various debuggers don't like it
			// So we'll insert a junk entry to avoid generating a null character
			line_array.add("");
			
			// Allocate 2/3rds of the space for text1, the rest for text2
			int max_lines = 40000;
			string chars1 = diff_lines_to_chars_munge(text1, line_array, line_hash, ref max_lines);
			max_lines = 65535;
			string chars2 = diff_lines_to_chars_munge(text2, line_array, line_hash, ref max_lines);
			
			return new LinesToCharsResult(chars1, chars2, line_array);
		}
		
		private string diff_lines_to_chars_munge(string text, Gee.ArrayList<string> line_array, Gee.HashMap<string, int> line_hash, ref int max_lines)
		{
			var chars = new StringBuilder();
			int line_start = 0;
			int line_end = -1;
			int line_array_length = line_array.size;
			
			while (line_end < text.length - 1) {
				line_end = text.index_of("\n", line_start);
				if (line_end == -1) {
					line_end = text.length - 1;
				}
				// Calculate length from line_start to line_end + 1 (inclusive)
				int line_length = int.min((line_end + 1) - line_start, text.length - line_start);
				string line = text.substring(line_start, line_length);
				
				if (line_hash.has_key(line)) {
					chars.append_unichar((unichar)line_hash.get(line));
					line_start = line_end + 1;
					continue;
				}
				
				if (line_array_length == max_lines) {
					// Bail out at 65535 because String.fromCharCode(65536) == String.fromCharCode(0)
					line = text.substring(line_start);
					line_end = text.length;
				}
				chars.append_unichar((unichar)line_array_length);
				line_hash.set(line, line_array_length);
				line_array.add(line);
				line_array_length++;
				line_start = line_end + 1;
			}
			
			return chars.str;
		}
		
		// Rehydrate the text in a diff from a string of line hashes to real lines of text
		private void diff_chars_to_lines(Gee.ArrayList<Diff> diffs, Gee.ArrayList<string> line_array)
		{
			// GLib.debug("DEBUG: diff_chars_to_lines entry: processing %d diffs, line_array.size=%d", diffs.size, line_array.size);
			for (var i = 0; i < diffs.size; i++) {
				var diff_text = diffs.get(i).text;
				// GLib.debug("diff_chars_to_lines: diff[%d] operation=%s, text.length=%d", i, diffs.get(i).operation.to_string(), diff_text.length);
				
				// Quick check: if the first character is invalid UTF-8, this diff contains actual text, not line indices
				if (diff_text.length > 0) {
					var first_char = diff_text.get_char(0);
					if (first_char == 0xffffffff) {
						// GLib.debug("diff_chars_to_lines: diff[%d] contains invalid UTF-8 at start, skipping conversion (contains actual text)", i);
						continue; // Skip this diff - it contains actual text, not line indices
					}
				}
				
				var text = new StringBuilder();
				unichar c;
				var j = 0;
				var char_count = 0;
				
				while (j < diff_text.length) {
					var prev_j = j;
					if (!diff_text.get_next_char(ref j, out c)) {
						// GLib.debug("diff_chars_to_lines: get_next_char returned false at j=%d", prev_j);
						break;
					}
					char_count++;
					if (char_count > 10000) {
						// GLib.debug("diff_chars_to_lines: WARNING - processed %d characters, possible infinite loop", char_count);
						break;
					}
					
					// GLib.debug("diff_chars_to_lines: char_count=%d, prev_j=%d, j=%d, c=%u (0x%x)", char_count, prev_j, j, c, c);
					
					// Safety check: ensure j is advancing to prevent infinite loops
					if (j == prev_j) {
						// GLib.debug("diff_chars_to_lines: ERROR - j did not advance! prev_j=%d, j=%d", prev_j, j);
						break;
					}
					
					// Check for invalid UTF-8 character code (0xffffffff)
					if (c == 0xffffffff) {
						// GLib.debug("diff_chars_to_lines: ERROR - invalid UTF-8 character code 0xffffffff at j=%d, diff contains actual text not line indices, skipping conversion", j);
						// This diff contains actual text, not line indices - don't convert it, keep original
						text = new StringBuilder();
						text.append(diff_text);
						break;
					}
					
					var index = (int)c;
					// GLib.debug("diff_chars_to_lines: index=%d, line_array.size=%d", index, line_array.size);
					if (index >= 0 && index < line_array.size) {
						text.append(line_array.get(index));
						// GLib.debug("diff_chars_to_lines: appended line_array[%d]", index);
					} else {
						// Character code is out of bounds - this means the diff contains actual text,
						// not line indices. This can happen after character-by-character rediffing.
						// Just append the character as-is.
						// GLib.debug("diff_chars_to_lines: index out of bounds, appending character as-is (c=%u)", c);
						text.append_unichar(c);
					}
				}
				// GLib.debug("diff_chars_to_lines: diff[%d] processed %d characters, result length=%d", i, char_count, text.str.length);
				diffs.get(i).text = text.str;
			}
		}
		
		// Find the 'middle snake' of a diff, split the problem in two and return the recursively constructed diff
		private Gee.ArrayList<Diff> diff_bisect(string text1, string text2, int64 deadline)
		{
			// GLib.debug("DEBUG: diff_bisect entry: text1.length=%d, text2.length=%d", text1.length, text2.length);
			// Cache the character counts (not byte lengths)
			int text1_char_count = text1.char_count();
			int text2_char_count = text2.char_count();
			// GLib.debug("DEBUG: diff_bisect char counts: text1_char_count=%d, text2_char_count=%d", text1_char_count, text2_char_count);
			int max_d = (text1_char_count + text2_char_count + 1) / 2;
			int v_offset = max_d;
			int v_length = 2 * max_d;
			int[] v1 = new int[v_length];
			int[] v2 = new int[v_length];
			
			// Setting all elements to -1
			for (int x = 0; x < v_length; x++) {
				v1[x] = -1;
				v2[x] = -1;
			}
			v1[v_offset + 1] = 0;
			v2[v_offset + 1] = 0;
			int delta = text1_char_count - text2_char_count;
			// If the total number of characters is odd, then the front path will collide with the reverse path
			bool front = (delta % 2 != 0);
			// Offsets for start and end of k loop
			int k1start = 0;
			int k1end = 0;
			int k2start = 0;
			int k2end = 0;
			
			int bisect_iterations = 0;
			for (int d = 0; d < max_d; d++) {
				bisect_iterations++;
				if (bisect_iterations % 100 == 0) {
					// GLib.debug("DEBUG: diff_bisect iteration d=%d/%d", d, max_d);
				}
				// Bail out if deadline is reached
				if (GLib.get_real_time() > deadline) {
					// GLib.debug("DEBUG: diff_bisect deadline reached");
					break;
				}
				
				// Walk the front path one step
				for (int k1 = -d + k1start; k1 <= d - k1end; k1 += 2) {
					int k1_offset = v_offset + k1;
					int x1;
					if (k1 == -d || (k1 != d && v1[k1_offset - 1] < v1[k1_offset + 1])) {
						x1 = v1[k1_offset + 1];
					} else {
						x1 = v1[k1_offset - 1] + 1;
					}
					int y1 = x1 - k1;
					// x1 and y1 are character positions, convert to byte offsets for get_char
					while (x1 < text1_char_count && y1 < text2_char_count) {
						int text1_byte_offset = text1.index_of_nth_char(x1);
						int text2_byte_offset = text2.index_of_nth_char(y1);
						if (text1_byte_offset == -1 || text2_byte_offset == -1) {
							break;
						}
						if (text1.get_char(text1_byte_offset) != text2.get_char(text2_byte_offset)) {
							break;
						}
						x1++;
						y1++;
					}
					v1[k1_offset] = x1;
					if (x1 > text1_char_count) {
						// Ran off the right of the graph
						k1end += 2;
						continue;
					}
					if (y1 > text2_char_count) {
						// Ran off the bottom of the graph
						k1start += 2;
						continue;
					}
					if (!front) {
						continue;
					}
					int k2_offset = v_offset + delta - k1;
					if (k2_offset < 0 || k2_offset >= v_length || v2[k2_offset] == -1) {
						continue;
					}
					// Mirror x2 onto top-left coordinate system
					int x2 = text1_char_count - v2[k2_offset];
					if (x1 >= x2) {
						// Overlap detected - x1 and y1 are character positions, need to convert to byte offsets for split
						var text1_byte_offset = text1.index_of_nth_char(x1);
						var text2_byte_offset = text2.index_of_nth_char(y1);
						text1_byte_offset = text1_byte_offset > -1 ? text1_byte_offset : text1.length;
						text2_byte_offset = text2_byte_offset > -1 ? text2_byte_offset : text2.length;
						return this.diff_bisect_split(text1, text2, text1_byte_offset, text2_byte_offset, deadline);
					}
				}
				
				// Walk the reverse path one step
				for (int k2 = -d + k2start; k2 <= d - k2end; k2 += 2) {
					int k2_offset = v_offset + k2;
					int x2;
					if (k2 == -d || (k2 != d && v2[k2_offset - 1] < v2[k2_offset + 1])) {
						x2 = v2[k2_offset + 1];
					} else {
						x2 = v2[k2_offset - 1] + 1;
					}
					int y2 = x2 - k2;
					// x2 and y2 are character positions from the end, convert to byte offsets for get_char
					while (x2 < text1_char_count && y2 < text2_char_count) {
						int text1_char_from_start = text1_char_count - x2 - 1;
						int text2_char_from_start = text2_char_count - y2 - 1;
						if (text1_char_from_start < 0 || text2_char_from_start < 0) {
							break;
						}
						int text1_byte_offset = text1.index_of_nth_char(text1_char_from_start);
						int text2_byte_offset = text2.index_of_nth_char(text2_char_from_start);
						if (text1_byte_offset == -1 || text2_byte_offset == -1) {
							break;
						}
						if (text1.get_char(text1_byte_offset) != text2.get_char(text2_byte_offset)) {
							break;
						}
						x2++;
						y2++;
					}
					v2[k2_offset] = x2;
					if (x2 > text1_char_count) {
						// Ran off the left of the graph
						k2end += 2;
						continue;
					}
					if (y2 > text2_char_count) {
						// Ran off the top of the graph
						k2start += 2;
						continue;
					}
					if (front) {
						continue;
					}
					int k1_offset = v_offset + delta - k2;
					if (k1_offset < 0 || k1_offset >= v_length || v1[k1_offset] == -1) {
						continue;
					}
					int x1 = v1[k1_offset];
					int y1 = v_offset + x1 - k1_offset;
					// Mirror x2 onto top-left coordinate system
					x2 = text1_char_count - x2;
					if (x1 >= x2) {
						// Overlap detected - x1 and y1 are character positions, need to convert to byte offsets for split
						var text1_byte_offset = text1.index_of_nth_char(x1);
						var text2_byte_offset = text2.index_of_nth_char(y1);
						text1_byte_offset = text1_byte_offset > -1 ? text1_byte_offset : text1.length;
						text2_byte_offset = text2_byte_offset > -1 ? text2_byte_offset : text2.length;
						return this.diff_bisect_split(text1, text2, text1_byte_offset, text2_byte_offset, deadline);
					}
				}
			}
			
			// Diff took too long and hit the deadline or number of diffs equals number of characters, no commonality at all
			var diffs = new Gee.ArrayList<Diff>();
			diffs.add(new Diff(DiffOperation.DELETE, text1));
			diffs.add(new Diff(DiffOperation.INSERT, text2));
			return diffs;
		}
		
		// Given the location of the 'middle snake', split the diff in two parts and recurse
		// x and y are byte offsets
		private Gee.ArrayList<Diff> diff_bisect_split(string text1, string text2, int x, int y, int64 deadline)
		{
			string text1a = text1.substring(0, x);
			string text2a = text2.substring(0, y);
			string text1b = text1.substring(x);
			string text2b = text2.substring(y);
			
			// Compute both diffs serially
			var diffs = this.diff_main(text1a, text2a, false, deadline);
			diffs.add_all(this.diff_main(text1b, text2b, false, deadline));
			return diffs;
		}
		
		// Reduce the number of edits by eliminating semantically trivial equalities
		private void diff_cleanup_semantic(Gee.ArrayList<Diff> diffs)
		{
			// GLib.debug("DEBUG: diff_cleanup_semantic entry: diffs.size=%d", diffs.size);
			bool changes = false;
			var equalities = new Gee.ArrayList<int>();
			int equalities_length = 0;
			string? last_equality = null;
			int pointer = 0;
			int length_insertions1 = 0;
			int cleanup_iterations = 0;
			int length_deletions1 = 0;
			int length_insertions2 = 0;
			int length_deletions2 = 0;
			
			// GLib.debug("DEBUG: diff_cleanup_semantic starting loop, pointer=%d, diffs.size=%d", pointer, diffs.size);
			while (pointer < diffs.size) {
				cleanup_iterations++;
				if (cleanup_iterations == 1 || cleanup_iterations % 1000 == 0) {
					// GLib.debug("DEBUG: diff_cleanup_semantic loop iteration %d, pointer=%d, diffs.size=%d", cleanup_iterations, pointer, diffs.size);
				}
				if (cleanup_iterations > 50000) {
					// GLib.debug("DEBUG: diff_cleanup_semantic WARNING - loop iteration limit reached!");
					break;
				}
				// GLib.debug("DEBUG: diff_cleanup_semantic checking operation at pointer %d", pointer);
				var op = diffs.get(pointer).operation;
				// GLib.debug("DEBUG: diff_cleanup_semantic operation=%s at pointer %d", op.to_string(), pointer);
				if (op == DiffOperation.EQUAL) {
					// GLib.debug("DEBUG: diff_cleanup_semantic EQUAL at pointer %d", pointer);
					equalities.add(pointer);
					equalities_length++;
					length_insertions1 = length_insertions2;
					length_deletions1 = length_deletions2;
					length_insertions2 = 0;
					length_deletions2 = 0;
					last_equality = diffs.get(pointer).text;
					pointer++;
					continue;
				}
				
				if (op == DiffOperation.INSERT) {
					var insert_char_count = diffs.get(pointer).text.char_count();
					// GLib.debug("DEBUG: diff_cleanup_semantic INSERT at pointer %d, char_count=%d", pointer, insert_char_count);
					length_insertions2 += insert_char_count;
				} else {
					var delete_char_count = diffs.get(pointer).text.char_count();
					// GLib.debug("DEBUG: diff_cleanup_semantic DELETE at pointer %d, char_count=%d", pointer, delete_char_count);
					length_deletions2 += delete_char_count;
				}
				
				// Eliminate an equality that is smaller or equal to the edits on both sides of it
				if (last_equality == null ||
				    last_equality.char_count() > int.max(length_insertions1, length_deletions1) ||
				    last_equality.char_count() > int.max(length_insertions2, length_deletions2)) {
					pointer++;
					continue;
				}
				
				// Duplicate record
				var insert_pos = equalities.get(equalities_length - 1);
				// GLib.debug("DEBUG: diff_cleanup_semantic inserting at position %d, equalities_length=%d", insert_pos, equalities_length);
				diffs.insert(insert_pos, new Diff(DiffOperation.DELETE, last_equality));
				// Change second copy to insert
				diffs.get(insert_pos + 1).operation = DiffOperation.INSERT;
				// Throw away the equality we just deleted
				equalities_length--;
				// Throw away the previous equality (it needs to be reevaluated)
				equalities_length--;
				pointer = equalities_length > 0 ? equalities.get(equalities_length - 1) : -1;
				// GLib.debug("DEBUG: diff_cleanup_semantic after insertion: pointer=%d, equalities_length=%d, diffs.size=%d", pointer, equalities_length, diffs.size);
				length_insertions1 = 0;
				length_deletions1 = 0;
				length_insertions2 = 0;
				length_deletions2 = 0;
				last_equality = null;
				changes = true;
				pointer++;
				// GLib.debug("DEBUG: diff_cleanup_semantic pointer after increment=%d", pointer);
			}
			
			// Normalize the diff
			if (changes) {
				this.diff_cleanup_merge(diffs);
			}
		}
		
		// Reorder and merge like edit sections. Merge equalities
		private void diff_cleanup_merge(Gee.ArrayList<Diff> diffs)
		{
			// GLib.debug("DEBUG: diff_cleanup_merge entry: diffs.size=%d", diffs.size);
			int merge_iterations = 0;
			// Add a dummy entry at the end
			diffs.add(new Diff(DiffOperation.EQUAL, ""));
			int pointer = 0;
			int count_delete = 0;
			int count_insert = 0;
			var text_delete = new StringBuilder();
			var text_insert = new StringBuilder();
			
			while (pointer < diffs.size) {
				merge_iterations++;
				if (merge_iterations % 1000 == 0) {
					// GLib.debug("DEBUG: diff_cleanup_merge loop iteration %d, pointer=%d, diffs.size=%d", merge_iterations, pointer, diffs.size);
				}
				if (merge_iterations > 50000) {
					// GLib.debug("DEBUG: diff_cleanup_merge WARNING - loop iteration limit reached!");
					break;
				}
				switch (diffs.get(pointer).operation) {
					case DiffOperation.INSERT:
						count_insert++;
						text_insert.append(diffs.get(pointer).text);
						pointer++;
						break;
					case DiffOperation.DELETE:
						count_delete++;
						text_delete.append(diffs.get(pointer).text);
						pointer++;
						break;
					case DiffOperation.EQUAL:
						// Upon reaching an equality, check for prior redundancies
						if (count_delete + count_insert > 1) {
							if (count_delete != 0 && count_insert != 0) {
								// Factor out any common prefixies
								var common_length = this.diff_common_prefix(text_insert.str, text_delete.str);
								if (common_length != 0) {
									var text_insert_char_count = text_insert.str.char_count();
									var text_delete_char_count = text_delete.str.char_count();
									// Ensure common_length doesn't exceed the string lengths
									if (common_length > text_insert_char_count) {
										common_length = text_insert_char_count;
									}
									if (common_length > text_delete_char_count) {
										common_length = text_delete_char_count;
									}
									if (common_length > 0) {
										var common_byte_offset = text_insert.str.index_of_nth_char(common_length);
										common_byte_offset = common_byte_offset > -1 ? common_byte_offset : text_insert.str.length;
										// Bounds check before substring
										if (common_byte_offset <= text_insert.str.length && common_byte_offset <= text_delete.str.length) {
											var prev_index = pointer - count_delete - count_insert - 1;
											if (prev_index > 0 && diffs.get(prev_index).operation == DiffOperation.EQUAL) {
												diffs.get(prev_index).text += text_insert.str.substring(0, common_byte_offset);
											} else {
												diffs.insert(0, new Diff(DiffOperation.EQUAL, text_insert.str.substring(0, common_byte_offset)));
												pointer++;
											}
											text_insert = new StringBuilder(text_insert.str.substring(common_byte_offset));
											text_delete = new StringBuilder(text_delete.str.substring(common_byte_offset));
										}
									}
								}
								// Factor out any common suffixies
								common_length = this.diff_common_suffix(text_insert.str, text_delete.str);
								if (common_length != 0) {
									var text_insert_char_count = text_insert.str.char_count();
									var text_delete_char_count = text_delete.str.char_count();
									// Ensure common_length doesn't exceed the string lengths
									if (common_length > text_insert_char_count) {
										common_length = text_insert_char_count;
									}
									if (common_length > text_delete_char_count) {
										common_length = text_delete_char_count;
									}
									if (common_length > 0) {
										var text_insert_suffix_start = text_insert.str.index_of_nth_char(text_insert_char_count - common_length);
										var text_delete_suffix_start = text_delete.str.index_of_nth_char(text_delete_char_count - common_length);
										if (text_insert_suffix_start == -1) {
											text_insert_suffix_start = text_insert.str.length;
										}
										if (text_delete_suffix_start == -1) {
											text_delete_suffix_start = text_delete.str.length;
										}
										// Bounds check before substring
										if (text_insert_suffix_start <= text_insert.str.length && text_delete_suffix_start <= text_delete.str.length) {
											diffs.get(pointer).text = text_insert.str.substring(text_insert_suffix_start) + diffs.get(pointer).text;
											text_insert = new StringBuilder(text_insert.str.substring(0, text_insert_suffix_start));
											text_delete = new StringBuilder(text_delete.str.substring(0, text_delete_suffix_start));
										}
									}
								}
							}
							// Delete the offending records and add the merged ones
							pointer -= count_delete + count_insert;
							for (var i = 0; i < count_delete + count_insert; i++) {
								diffs.remove_at(pointer);
							}
							if (text_delete.str.length > 0) {
								diffs.insert(pointer, new Diff(DiffOperation.DELETE, text_delete.str));
								pointer++;
							}
							if (text_insert.str.length > 0) {
								diffs.insert(pointer, new Diff(DiffOperation.INSERT, text_insert.str));
								pointer++;
							}
							pointer++;
							count_insert = 0;
							count_delete = 0;
							text_delete = new StringBuilder();
							text_insert = new StringBuilder();
							break;
						}
						
						if (pointer != 0 && diffs.get(pointer - 1).operation == DiffOperation.EQUAL) {
							// Merge this equality with the previous one
							diffs.get(pointer - 1).text += diffs.get(pointer).text;
							diffs.remove_at(pointer);
						} else {
							pointer++;
						}
						count_insert = 0;
						count_delete = 0;
						text_delete = new StringBuilder();
						text_insert = new StringBuilder();
						break;
				}
			}
			
			// Remove the dummy entry at the end
			if (diffs.size > 0 && diffs.get(diffs.size - 1).text == "") {
				diffs.remove_at(diffs.size - 1);
			}
			
			// Second pass: look for single edits surrounded on both sides by equalities which can be shifted sideways to eliminate an equality
			var changes = false;
			pointer = 1;
			// Intentionally ignore the first and last element (don't need checking)
			while (pointer < diffs.size - 1) {
				if (diffs.get(pointer - 1).operation != DiffOperation.EQUAL ||
				    diffs.get(pointer + 1).operation != DiffOperation.EQUAL) {
					pointer++;
					continue;
				}
				
				// This is a single edit surrounded by equalities
				if (diffs.get(pointer).text.has_suffix(diffs.get(pointer - 1).text)) {
					// Shift the edit over the previous equality
					var suffix_length = diffs.get(pointer - 1).text.length;
					var prefix_length = diffs.get(pointer).text.length - suffix_length;
					if (prefix_length > 0 && prefix_length <= diffs.get(pointer).text.length) {
						diffs.get(pointer).text = diffs.get(pointer - 1).text + diffs.get(pointer).text.substring(0, prefix_length);
						diffs.get(pointer + 1).text = diffs.get(pointer - 1).text + diffs.get(pointer + 1).text;
						diffs.remove_at(pointer - 1);
						changes = true;
						pointer++;
						continue;
					}
				}
				
				if (diffs.get(pointer).text.has_prefix(diffs.get(pointer + 1).text)) {
					// Shift the edit over the next equality
					var prefix_length = diffs.get(pointer + 1).text.length;
					if (prefix_length <= diffs.get(pointer).text.length) {
						diffs.get(pointer - 1).text += diffs.get(pointer + 1).text;
						diffs.get(pointer).text = diffs.get(pointer).text.substring(prefix_length) + diffs.get(pointer + 1).text;
						diffs.remove_at(pointer + 1);
						changes = true;
					}
				}
				pointer++;
			}
			// If shifts were made, the diff needs reordering and another shift sweep
			if (changes) {
				this.diff_cleanup_merge(diffs);
			}
		}
	}
}

