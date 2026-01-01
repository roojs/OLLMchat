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

namespace OLLMchat
{
	int main(string[] args)
	{
		if (args.length != 3) {
			stderr.printf("Usage: %s <file1> <file2>\n", args[0]);
			return 1;
		}
		
		string file1_path = args[1];
		string file2_path = args[2];
		
		// Read file1
		string file1_contents;
		try {
			FileUtils.get_contents(file1_path, out file1_contents);
		} catch (Error e) {
			stderr.printf("Error reading %s: %s\n", file1_path, e.message);
			return 1;
		}
		
		// Read file2
		string file2_contents;
		try {
			FileUtils.get_contents(file2_path, out file2_contents);
		} catch (Error e) {
			stderr.printf("Error reading %s: %s\n", file2_path, e.message);
			return 1;
		}
		
		// Create patches
		var differ = new OLLMfiles.Diff.Differ(file1_contents, file2_contents);
		var patches = differ.diff();
		
		// Output unified diff format
		stdout.printf("--- %s\n", file1_path);
		stdout.printf("+++ %s\n", file2_path);
		
		if (patches.size == 0) {
			return 0;
		}
		
		// Merge adjacent patches into hunks (within context distance)
		var context_lines = 3;
		var i = 0;
		while (i < patches.size) {
			// Start of a new hunk
			var hunk_start_patch = patches.get(i);
			var hunk_end_patch = hunk_start_patch;
			var hunk_patches = new Gee.ArrayList<OLLMfiles.Diff.Patch>();
			hunk_patches.add(hunk_start_patch);
			
			// Find all patches that should be in this hunk
			var last_old_end = hunk_start_patch.old_line_end;
			i++;
			
			while (i < patches.size) {
				var next_patch = patches.get(i);
				// If next patch is within 2*context_lines of the last patch, merge it
				var gap = next_patch.old_line_start - last_old_end - 1;
				if (gap <= 2 * context_lines) {
					hunk_patches.add(next_patch);
					last_old_end = next_patch.old_line_end;
					hunk_end_patch = next_patch;
					i++;
				} else {
					break;
				}
			}
			
			// Calculate hunk boundaries
			var hunk_old_start = hunk_start_patch.old_line_start;
			var hunk_old_end = hunk_end_patch.old_line_end;
			var hunk_new_start = hunk_start_patch.new_line_start;
			var hunk_new_end = hunk_end_patch.new_line_end;
			
			// Get context before first patch
			var context_before = hunk_start_patch.context(-context_lines);
			var context_before_count = context_before.length;
			
			// Get context after last patch
			var context_after = hunk_end_patch.context(context_lines);
			var context_after_count = context_after.length;
			
			// Calculate hunk header
			var hunk_start_line = int.max(1, hunk_old_start - context_before_count);
			var hunk_old_count = context_before_count + (hunk_old_end - hunk_old_start + 1) + context_after_count;
			var hunk_new_count = context_before_count + (hunk_new_end - hunk_new_start + 1) + context_after_count;
			
			// Output hunk header
			stdout.printf("@@ -%d,%d +%d,%d @@\n", hunk_start_line, hunk_old_count, hunk_start_line, hunk_new_count);
			
			// Output context before
			foreach (var line in context_before) {
				stdout.printf(" %s\n", line);
			}
			
			// Output patches in order, with context between them
			var current_line = hunk_old_start;
			foreach (var patch in hunk_patches) {
				// Output unchanged lines between patches
				if (patch.old_line_start > current_line) {
					// Get the gap lines using context from the patch
					var gap_size = patch.old_line_start - current_line;
					var gap_context = patch.context(-gap_size);
					foreach (var line in gap_context) {
						stdout.printf(" %s\n", line);
					}
				}
				
				// Output old lines (deletions) - these come from lines1
				var old_lines_array = patch.old_lines();
				foreach (var line in old_lines_array) {
					stdout.printf("-%s\n", line);
				}
				
				// Output new lines (additions) - these come from lines2
				var new_lines_array = patch.new_lines();
				foreach (var line in new_lines_array) {
					stdout.printf("+%s\n", line);
				}
				
				current_line = patch.old_line_end + 1;
			}
			
			// Output context after
			foreach (var line in context_after) {
				stdout.printf(" %s\n", line);
			}
		}
		
		return 0;
	}
}

