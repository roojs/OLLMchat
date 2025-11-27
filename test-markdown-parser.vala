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
	
	// Create DummyRenderer instance (extends Render but prints callbacks)
	var renderer = new OLLMchat.MarkdownGtk.DummyRenderer(buffer, start_mark);
	var parser = renderer.parser;
	
	// Read markdown from stdin or use test file
	string markdown_text;
	if (args.length > 1) {
		// Read from file
		try {
			FileUtils.get_contents(args[1], out markdown_text);
		} catch (Error e) {
			stderr.printf("Error reading file: %s\n", e.message);
			return 1;
		}
	} else {
		// Read from stdin
		var input = new StringBuilder();
		string? line;
		while ((line = stdin.read_line()) != null) {
			if (input.len > 0) {
				input.append_c('\n');
			}
			input.append(line);
		}
		markdown_text = input.str;
	}
	
	// Parse the markdown - DummyRenderer will print all callbacks
	stdout.printf("=== PARSER CALLBACKS ===\n");
	parser.add(markdown_text);
	stdout.printf("=== END CALLBACKS ===\n");
	
	return 0;
}
