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

int main(string[] args)
{
	if (args.length < 2) {
		stderr.printf("Usage: %s <markdown_file>\n", args[0]);
		stderr.printf("Parses markdown file and outputs callback trace using DummyRenderer.\n");
		return 1;
	}

	var file_path = args[1];
	
	// Read markdown file
	string markdown_content;
	try {
		GLib.FileUtils.get_contents(file_path, out markdown_content);
	} catch (GLib.FileError e) {
		stderr.printf("Error: Failed to read file '%s': %s\n", file_path, e.message);
		return 1;
	}

	// Create Render instance (using DummyRenderer for testing)
	var renderer = new Markdown.DummyRenderer();
	
	stdout.printf("=== PARSING MARKDOWN FILE: %s ===\n", file_path);
	stdout.printf("=== FILE CONTENT (first 200 chars) ===\n");
	stdout.printf("%.200s...\n\n", markdown_content);
	stdout.printf("=== CALLBACK TRACE ===\n");
	
	// Parse the markdown
	renderer.start();
	renderer.add(markdown_content);
	renderer.flush();
	
	stdout.printf("=== END TRACE ===\n");
	
	return 0;
}
