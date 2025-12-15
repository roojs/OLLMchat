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
	private struct HalfMatchResult
	{
		public bool success;
		public string longtext_prefix;
		public string longtext_suffix;
		public string shorttext_prefix;
		public string shorttext_suffix;
		public string common_middle;
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
			int line_pos = 0;  // Current position in original_lines (0-based)
			int i = 0;
			
			while (i < diffs.size) {
				if (diffs[i].operation == DiffOperation.EQUAL) {
					// Skip equal lines
					line_pos += diffs[i].text.split("\n").length;
					i++;
					continue;
				}
				
				// Collect consecutive DELETE operations
				var delete_lines = new Gee.ArrayList<string>();
				int delete_start = line_pos;
				while (i < diffs.size && diffs[i].operation == DiffOperation.DELETE) {
					foreach (var line in diffs[i].text.split("\n")) {
						delete_lines.add(line);
					}
					line_pos += diffs[i].text.split("\n").length;
					i++;
				}
				
				// Collect consecutive INSERT operations
				var insert_lines = new Gee.ArrayList<string>();
				while (i < diffs.size && diffs[i].operation == DiffOperation.INSERT) {
					foreach (var line in diffs[i].text.split("\n")) {
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
			string text1_after_prefix = text1.substring(prefix_length);
			string text2_after_prefix = text2.substring(prefix_length);
			
			// Trim off common suffix (speedup)
			int suffix_length = this.diff_common_suffix(text1_after_prefix, text2_after_prefix);
			string text1_middle = text1_after_prefix.substring(0, text1_after_prefix.length - suffix_length);
			string text2_middle = text2_after_prefix.substring(0, text2_after_prefix.length - suffix_length);
			
			// Compute the diff on the middle block
			var diffs = this.diff_compute(text1_middle, text2_middle, check_lines, deadline);
			
			// Restore the prefix and suffix
			if (prefix_length > 0) {
				diffs.insert(0, new Diff(DiffOperation.EQUAL, text1.substring(0, prefix_length)));
			}
			if (suffix_length > 0) {
				diffs.add(new Diff(DiffOperation.EQUAL, text1_after_prefix.substring(text1_after_prefix.length - suffix_length)));
			}
			
			this.diff_cleanup_merge(diffs);
			return diffs;
		}
		
		// Find differences between two texts (assumes no common prefix/suffix)
		private Gee.ArrayList<Diff> diff_compute(string text1, string text2, bool check_lines, int64 deadline)
		{
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
			
			int i = longtext.index_of(shorttext);
			if (i != -1) {
				// Shorter text is inside the longer text (speedup)
				diffs.add(new Diff(DiffOperation.INSERT, longtext.substring(0, i)));
				diffs.add(new Diff(DiffOperation.EQUAL, shorttext));
				diffs.add(new Diff(DiffOperation.INSERT, longtext.substring(i + shorttext.length)));
				// Swap insertions for deletions if diff is reversed
				if (text1.length > text2.length) {
					diffs[0].operation = DiffOperation.DELETE;
					diffs[2].operation = DiffOperation.DELETE;
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
				return this.diff_line_mode(text1, text2, deadline);
			}
			
			return this.diff_bisect(text1, text2, deadline);
		}
		
		// Determine the common prefix of two strings
		private int diff_common_prefix(string text1, string text2)
		{
			// Quick check for common null cases
			if (text1.length == 0 || text2.length == 0 || text1[0] != text2[0]) {
				return 0;
			}
			
			// Binary search
			int pointer_min = 0;
			int pointer_max = int.min(text1.length, text2.length);
			int pointer_mid = pointer_max;
			int pointer_start = 0;
			
			while (pointer_min < pointer_mid) {
				if (text1.substring(pointer_start, pointer_mid) == text2.substring(pointer_start, pointer_mid)) {
					pointer_min = pointer_mid;
					pointer_start = pointer_min;
				} else {
					pointer_max = pointer_mid;
				}
				pointer_mid = (pointer_max - pointer_min) / 2 + pointer_min;
			}
			
			return pointer_mid;
		}
		
		// Determine the common suffix of two strings
		private int diff_common_suffix(string text1, string text2)
		{
			// Quick check for common null cases
			if (text1.length == 0 || text2.length == 0 || 
			    text1[text1.length - 1] != text2[text2.length - 1]) {
				return 0;
			}
			
			// Binary search
			int pointer_min = 0;
			int pointer_max = int.min(text1.length, text2.length);
			int pointer_mid = pointer_max;
			int pointer_end = 0;
			
			while (pointer_min < pointer_mid) {
				if (text1.substring(text1.length - pointer_mid, text1.length - pointer_end) ==
				    text2.substring(text2.length - pointer_mid, text2.length - pointer_end)) {
					pointer_min = pointer_mid;
					pointer_end = pointer_min;
				} else {
					pointer_max = pointer_mid;
				}
				pointer_mid = (pointer_max - pointer_min) / 2 + pointer_min;
			}
			
			return pointer_mid;
		}
		
		// Do the two texts share a substring which is at least half the length of the longer text?
		private HalfMatchResult diff_half_match(string text1, string text2)
		{
			var result = HalfMatchResult();
			
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
			var hm1 = this.diff_half_match_i(longtext, shorttext, (longtext.length + 3) / 4);
			// Check again based on the third quarter
			var hm2 = this.diff_half_match_i(longtext, shorttext, (longtext.length + 1) / 2);
			
			if (!hm1.success && !hm2.success) {
				return result;
			}
			
			var hm = HalfMatchResult();
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
				return new HalfMatchResult() {
					success = true,
					longtext_prefix = hm.shorttext_prefix,
					longtext_suffix = hm.shorttext_suffix,
					shorttext_prefix = hm.longtext_prefix,
					shorttext_suffix = hm.longtext_suffix,
					common_middle = hm.common_middle
				};
			}
		}
		
		// Does a substring of shorttext exist within longtext such that the substring is at least half the length of longtext?
		private HalfMatchResult diff_half_match_i(string longtext, string shorttext, int i)
		{
			var result = HalfMatchResult();
			
			// Start with a 1/4 length substring at position i as a seed
			string seed = longtext.substring(i, i + longtext.length / 4);
			int j = -1;
			
			while ((j = shorttext.index_of(seed, j + 1)) != -1) {
				int prefix_length = this.diff_common_prefix(longtext.substring(i), shorttext.substring(j));
				int suffix_length = this.diff_common_suffix(longtext.substring(0, i), shorttext.substring(0, j));
				
				if (result.common_middle.length < suffix_length + prefix_length) {
					result.common_middle = shorttext.substring(j - suffix_length, j) + shorttext.substring(j, j + prefix_length);
					result.longtext_prefix = longtext.substring(0, i - suffix_length);
					result.longtext_suffix = longtext.substring(i + prefix_length);
					result.shorttext_prefix = shorttext.substring(0, j - suffix_length);
					result.shorttext_suffix = shorttext.substring(j + prefix_length);
				}
			}
			
			if (result.common_middle.length * 2 < longtext.length) {
				return result;
			}
			
			result.success = true;
			return result;
		}
		
		// Do a quick line-level diff on both strings, then rediff the parts for greater accuracy
		private Gee.ArrayList<Diff> diff_line_mode(string text1, string text2, int64 deadline)
		{
			// Scan the text on a line-by-line basis first
			var result = this.diff_lines_to_chars(text1, text2);
			
			var diffs = this.diff_main(result.chars1, result.chars2, false, deadline);
			
			// Convert the diff back to original text
			this.diff_chars_to_lines(diffs, result.line_array);
			// Eliminate freak matches (e.g. blank lines)
			this.diff_cleanup_semantic(diffs);
			
			// Rediff any replacement blocks, this time character-by-character
			// Add a dummy entry at the end
			diffs.add(new Diff(DiffOperation.EQUAL, ""));
			int pointer = 0;
			int count_delete = 0;
			int count_insert = 0;
			var text_delete = new StringBuilder();
			var text_insert = new StringBuilder();
			
			while (pointer < diffs.size) {
				switch (diffs[pointer].operation) {
					case DiffOperation.INSERT:
						count_insert++;
						text_insert.append(diffs[pointer].text);
						pointer++;
						break;
					case DiffOperation.DELETE:
						count_delete++;
						text_delete.append(diffs[pointer].text);
						pointer++;
						break;
					case DiffOperation.EQUAL:
						// Upon reaching an equality, check for prior redundancies
						if (count_delete >= 1 && count_insert >= 1) {
							// Delete the offending records and add the merged ones
							for (int k = 0; k < count_delete + count_insert; k++) {
								diffs.remove_at(pointer - count_delete - count_insert);
							}
							pointer = pointer - count_delete - count_insert;
							var sub_diff = this.diff_main(text_delete.str, text_insert.str, false, deadline);
							for (int j = sub_diff.size - 1; j >= 0; j--) {
								diffs.insert(pointer, sub_diff[j]);
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
			if (diffs.size > 0 && diffs[diffs.size - 1].text == "") {
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
				string line = text.substring(line_start, line_end + 1);
				
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
			for (int i = 0; i < diffs.size; i++) {
				var text = new StringBuilder();
				unichar c;
				for (int j = 0; diffs[i].text.get_next_char(ref j, out c);) {
					text.append(line_array[(int)c]);
				}
				diffs[i].text = text.str;
			}
		}
		
		// Find the 'middle snake' of a diff, split the problem in two and return the recursively constructed diff
		private Gee.ArrayList<Diff> diff_bisect(string text1, string text2, int64 deadline)
		{
			// Cache the text lengths to prevent multiple calls
			int text1_length = text1.length;
			int text2_length = text2.length;
			int max_d = (text1_length + text2_length + 1) / 2;
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
			int delta = text1_length - text2_length;
			// If the total number of characters is odd, then the front path will collide with the reverse path
			bool front = (delta % 2 != 0);
			// Offsets for start and end of k loop
			int k1start = 0;
			int k1end = 0;
			int k2start = 0;
			int k2end = 0;
			
			for (int d = 0; d < max_d; d++) {
				// Bail out if deadline is reached
				if (GLib.get_real_time() > deadline) {
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
					while (x1 < text1_length && y1 < text2_length && text1[x1] == text2[y1]) {
						x1++;
						y1++;
					}
					v1[k1_offset] = x1;
					if (x1 > text1_length) {
						// Ran off the right of the graph
						k1end += 2;
						continue;
					}
					if (y1 > text2_length) {
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
					int x2 = text1_length - v2[k2_offset];
					if (x1 >= x2) {
						// Overlap detected
						return this.diff_bisect_split(text1, text2, x1, y1, deadline);
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
					while (x2 < text1_length && y2 < text2_length &&
					       text1[text1_length - x2 - 1] == text2[text2_length - y2 - 1]) {
						x2++;
						y2++;
					}
					v2[k2_offset] = x2;
					if (x2 > text1_length) {
						// Ran off the left of the graph
						k2end += 2;
						continue;
					}
					if (y2 > text2_length) {
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
					x2 = text1_length - x2;
					if (x1 >= x2) {
						// Overlap detected
						return this.diff_bisect_split(text1, text2, x1, y1, deadline);
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
			bool changes = false;
			var equalities = new Gee.ArrayList<int>();
			int equalities_length = 0;
			string? last_equality = null;
			int pointer = 0;
			int length_insertions1 = 0;
			int length_deletions1 = 0;
			int length_insertions2 = 0;
			int length_deletions2 = 0;
			
			while (pointer < diffs.size) {
				if (diffs[pointer].operation == DiffOperation.EQUAL) {
					equalities.add(pointer);
					equalities_length++;
					length_insertions1 = length_insertions2;
					length_deletions1 = length_deletions2;
					length_insertions2 = 0;
					length_deletions2 = 0;
					last_equality = diffs[pointer].text;
					pointer++;
					continue;
				}
				
				if (diffs[pointer].operation == DiffOperation.INSERT) {
					length_insertions2 += diffs[pointer].text.length;
				} else {
					length_deletions2 += diffs[pointer].text.length;
				}
				
				// Eliminate an equality that is smaller or equal to the edits on both sides of it
				if (last_equality == null ||
				    last_equality.length > int.max(length_insertions1, length_deletions1) ||
				    last_equality.length > int.max(length_insertions2, length_deletions2)) {
					pointer++;
					continue;
				}
				
				// Duplicate record
				diffs.insert(equalities[equalities_length - 1], new Diff(DiffOperation.DELETE, last_equality));
				// Change second copy to insert
				diffs[equalities[equalities_length - 1] + 1].operation = DiffOperation.INSERT;
				// Throw away the equality we just deleted
				equalities_length--;
				// Throw away the previous equality (it needs to be reevaluated)
				equalities_length--;
				pointer = equalities_length > 0 ? equalities[equalities_length - 1] : -1;
				length_insertions1 = 0;
				length_deletions1 = 0;
				length_insertions2 = 0;
				length_deletions2 = 0;
				last_equality = null;
				changes = true;
				pointer++;
			}
			
			// Normalize the diff
			if (changes) {
				this.diff_cleanup_merge(diffs);
			}
		}
		
		// Reorder and merge like edit sections. Merge equalities
		private void diff_cleanup_merge(Gee.ArrayList<Diff> diffs)
		{
			// Add a dummy entry at the end
			diffs.add(new Diff(DiffOperation.EQUAL, ""));
			int pointer = 0;
			int count_delete = 0;
			int count_insert = 0;
			var text_delete = new StringBuilder();
			var text_insert = new StringBuilder();
			
			while (pointer < diffs.size) {
				switch (diffs[pointer].operation) {
					case DiffOperation.INSERT:
						count_insert++;
						text_insert.append(diffs[pointer].text);
						pointer++;
						break;
					case DiffOperation.DELETE:
						count_delete++;
						text_delete.append(diffs[pointer].text);
						pointer++;
						break;
					case DiffOperation.EQUAL:
						// Upon reaching an equality, check for prior redundancies
						if (count_delete + count_insert > 1) {
							if (count_delete != 0 && count_insert != 0) {
								// Factor out any common prefixies
								int common_length = this.diff_common_prefix(text_insert.str, text_delete.str);
								if (common_length != 0) {
									if ((pointer - count_delete - count_insert) > 0 &&
									    diffs[pointer - count_delete - count_insert - 1].operation == DiffOperation.EQUAL) {
										diffs[pointer - count_delete - count_insert - 1].text += text_insert.str.substring(0, common_length);
									} else {
										diffs.insert(0, new Diff(DiffOperation.EQUAL, text_insert.str.substring(0, common_length)));
										pointer++;
									}
									text_insert = new StringBuilder(text_insert.str.substring(common_length));
									text_delete = new StringBuilder(text_delete.str.substring(common_length));
								}
								// Factor out any common suffixies
								common_length = this.diff_common_suffix(text_insert.str, text_delete.str);
								if (common_length != 0) {
									diffs[pointer].text = text_insert.str.substring(text_insert.str.length - common_length) + diffs[pointer].text;
									text_insert = new StringBuilder(text_insert.str.substring(0, text_insert.str.length - common_length));
									text_delete = new StringBuilder(text_delete.str.substring(0, text_delete.str.length - common_length));
								}
							}
							// Delete the offending records and add the merged ones
							pointer -= count_delete + count_insert;
							for (int i = 0; i < count_delete + count_insert; i++) {
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
						
						if (pointer != 0 && diffs[pointer - 1].operation == DiffOperation.EQUAL) {
							// Merge this equality with the previous one
							diffs[pointer - 1].text += diffs[pointer].text;
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
			if (diffs.size > 0 && diffs[diffs.size - 1].text == "") {
				diffs.remove_at(diffs.size - 1);
			}
			
			// Second pass: look for single edits surrounded on both sides by equalities which can be shifted sideways to eliminate an equality
			bool changes = false;
			pointer = 1;
			// Intentionally ignore the first and last element (don't need checking)
			while (pointer < diffs.size - 1) {
				if (diffs[pointer - 1].operation != DiffOperation.EQUAL ||
				    diffs[pointer + 1].operation != DiffOperation.EQUAL) {
					pointer++;
					continue;
				}
				
				// This is a single edit surrounded by equalities
				if (diffs[pointer].text.has_suffix(diffs[pointer - 1].text)) {
					// Shift the edit over the previous equality
					diffs[pointer].text = diffs[pointer - 1].text + diffs[pointer].text.substring(0, diffs[pointer].text.length - diffs[pointer - 1].text.length);
					diffs[pointer + 1].text = diffs[pointer - 1].text + diffs[pointer + 1].text;
					diffs.remove_at(pointer - 1);
					changes = true;
					pointer++;
					continue;
				}
				
				if (diffs[pointer].text.has_prefix(diffs[pointer + 1].text)) {
					// Shift the edit over the next equality
					diffs[pointer - 1].text += diffs[pointer + 1].text;
					diffs[pointer].text = diffs[pointer].text.substring(diffs[pointer + 1].text.length) + diffs[pointer + 1].text;
					diffs.remove_at(pointer + 1);
					changes = true;
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

