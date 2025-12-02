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

int main(string[] args)
{
	// Initialize Gtk (required for Render class)
	Gtk.init();
	
	// Create a minimal TextBuffer and mark for Render
	var buffer = new Gtk.TextBuffer(null);
	Gtk.TextIter iter;
	buffer.get_start_iter(out iter);
	var start_mark = buffer.create_mark(null, iter, true);
	
	// Create Render instance (using DummyRenderer for testing)
	var renderer = new OLLMchat.Markdown.DummyRenderer(buffer, start_mark);
	
	// Simulate streaming chunks from actual debug output
	// First block chunks
	string[] first_block_chunks = {
		"We",
		" need",
		" to",
		" read",
		" /",
		"var",
		"/log",
		"/sys",
		"log",
		".",
		" Use",
		" run",
		"_command",
		"?",
		" Actually",
		" need",
		" to",
		" read",
		" a",
		" file",
		".",
		" It's",
		" a",
		" system",
		" file",
		",",
		" we",
		" can",
		" run",
		" command",
		" \"",
		"head",
		" -",
		"n",
		" ",
		"20",
		" /",
		"var",
		"/log",
		"/sys",
		"log",
		"\".",
		" Use",
		" run",
		"_command",
		" tool",
		".",
		" Explain",
		" to",
		" user",
		".",
		"\n"
	};
	
	// Second block chunks (after flush and add_start)
	string[] second_block_chunks = {
		"I",
		" will",
		" run",
		" a",
		" command",
		" to",
		" show",
		" the",
		" first",
		" few",
		" lines",
		" of",
		" the",
		" system",
		" log",
		" file",
		" so",
		" we",
		" can",
		" look",
		" for",
		" the",
		" hostname",
		"."
	};
	
	// Process chunks like the real stream does
	stdout.printf("=== STREAMING CHUNKS ===\n");
	
	// First block: add_start (not shown in debug but implied), then add chunks
	renderer.add_start("<span color=\"blue\">", false);
	foreach (var chunk in first_block_chunks) {
		renderer.add(chunk);
	}
	renderer.flush();
	
	// Second block: add_start with is_end_of_chunks=true, then add chunks
	renderer.add_start("<span color=\"blue\">", true);
	foreach (var chunk in second_block_chunks) {
		renderer.add(chunk);
	}
	
	stdout.printf("=== END STREAMING ===\n");
	
	// Test case: bold before code block
	// Input: - `**/**tmp**/test**.gs**` ** – exact copy of the original script you supplied.
	// Expected: TEXT "-", START <strong>, TEXT "`/**tmp**/test**.gs**`", END (strong), TEXT " – exact copy..."
	stdout.printf("\n=== TEST: BOLD BEFORE CODE BLOCK ===\n");
	
	var test_renderer = new OLLMchat.Markdown.DummyRenderer(buffer, start_mark);
	
	// Simulate the exact chunks from debug output
	string[] test_chunks = {
		"-",
		" ",
		"**",
		"`",
		"/",
		"tmp",
		"/test",
		".gs",
		"`",
		"**",
		" –",
		" exact",
		" copy",
		" of",
		" the",
		" original",
		" script",
		" you",
		" supplied",
		"."
	};
	
	test_renderer.add_start("", false);
	foreach (var chunk in test_chunks) {
		test_renderer.add(chunk);
	}
	test_renderer.flush();
	
	stdout.printf("\n=== TEST: SIMPLE BOLD BEFORE CODE ===\n");
	var test2_renderer = new OLLMchat.Markdown.DummyRenderer(buffer, start_mark);
	// Simpler test: just "**" followed by "`"
	test2_renderer.add_start("", false);
	test2_renderer.add("**");
	test2_renderer.add("`");
	test2_renderer.add("test");
	test2_renderer.add("`");
	test2_renderer.add("**");
	test2_renderer.flush();
	
	stdout.printf("=== END TEST ===\n");
	
	return 0;
}
