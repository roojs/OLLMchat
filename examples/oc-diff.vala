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
		var creator = new OLLMcoder.Diff.PatchCreator();
		var patches = creator.create_patches(file1_contents, file2_contents);
		
		// Output unified diff format
		stdout.printf("--- %s\n", file1_path);
		stdout.printf("+++ %s\n", file2_path);
		
		foreach (var patch in patches) {
			int old_count = patch.old_lines.length;
			int new_count = patch.new_lines.length;
			
			// Calculate line numbers for unified diff
			int start_old = patch.start_line;
			int start_new = patch.start_line;
			
			switch (patch.operation) {
				case OLLMcoder.Diff.PatchOperation.ADD:
					// Adding lines: old file unchanged, new file adds lines
					old_count = 0;
					break;
				case OLLMcoder.Diff.PatchOperation.REMOVE:
					// Removing lines: old file removes lines, new file unchanged
					new_count = 0;
					break;
				case OLLMcoder.Diff.PatchOperation.REPLACE:
					// Replacing lines: both files change
					break;
			}
			
			// Output hunk header
			if (old_count == 0) {
				// Special case: no old lines (pure addition)
				stdout.printf("@@ -%d,0 +%d,%d @@\n", start_old, start_new, new_count);
			} else if (new_count == 0) {
				// Special case: no new lines (pure removal)
				stdout.printf("@@ -%d,%d +%d,0 @@\n", start_old, old_count, start_new);
			} else {
				// Normal case: both old and new lines
				stdout.printf("@@ -%d,%d +%d,%d @@\n", start_old, old_count, start_new, new_count);
			}
			
			// Output old lines (with - prefix)
			foreach (var line in patch.old_lines) {
				stdout.printf("-%s\n", line);
			}
			
			// Output new lines (with + prefix)
			foreach (var line in patch.new_lines) {
				stdout.printf("+%s\n", line);
			}
		}
		
		return 0;
	}
}

