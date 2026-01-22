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
	// Set up debug handler to output to stderr
	GLib.Log.set_default_handler((dom, lvl, msg) => {
		stderr.printf(lvl.to_string() + " : " + msg + "\n");
	});

	if (args.length < 2) {
		stderr.printf("Usage: %s <markdown_file>\n", args[0]);
		stderr.printf("Converts markdown file to HTML and outputs to stdout.\n");
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

	// Convert markdown to HTML
	var renderer = new Markdown.HtmlRender();
	var html = renderer.toHtml(markdown_content);

	// Output HTML to stdout
	stdout.printf("%s", html);

	return 0;
}
