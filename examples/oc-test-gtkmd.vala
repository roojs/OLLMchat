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

/**
 * Example: oc-test-gtkmd {markdown file}
 *
 * Opens a window with the GTK markdown widget and renders the given markdown file.
 * Uses the same structural pattern as other examples (option parsing, help, validation).
 */
class TestGtkMd : Gtk.Application
{
	private static bool opt_help = false;
	private static string? opt_file = null;

	private const OptionEntry[] options = {
		{ "help", 'h', 0, OptionArg.NONE, ref opt_help, "Show help and exit", null },
		{ "file", 'f', 0, OptionArg.STRING, ref opt_file, "Markdown file to render", "FILE" },
		{ null }
	};

	public TestGtkMd()
	{
		Object(
			application_id: "com.roojs.ollmchat.test-gtkmd",
			flags: ApplicationFlags.HANDLES_COMMAND_LINE
		);
	}

	protected override int command_line(ApplicationCommandLine command_line)
	{
		opt_help = false;
		opt_file = null;

		string[] args = command_line.get_arguments();
		unowned string[] remaining = args;

		var opt_context = new OptionContext("oc-test-gtkmd");
		opt_context.set_help_enabled(true);
		opt_context.add_main_entries(options, null);

		try {
			opt_context.parse(ref remaining);
		} catch (OptionError e) {
			command_line.printerr("error: %s\n", e.message);
			command_line.printerr("Run '%s --help' for options.\n", args[0]);
			return 1;
		}

		if (opt_help) {
			command_line.print(help_text());
			return 0;
		}

		// File: from --file or first positional argument
		string? file_path = (opt_file != null && opt_file != "") ? opt_file : null;
		if (file_path == null && remaining.length > 1) {
			file_path = remaining[1];
		}
		if (file_path == null || file_path == "") {
			command_line.printerr("ERROR: Markdown file is required.\n");
			command_line.printerr("Usage: %s <markdown_file>\n", args[0]);
			command_line.printerr("Run '%s --help' for options.\n", args[0]);
			return 1;
		}

		// Resolve path
		if (!GLib.Path.is_absolute(file_path)) {
			file_path = GLib.Path.build_filename(GLib.Environment.get_current_dir(), file_path);
		}
		if (!GLib.FileUtils.test(file_path, GLib.FileTest.EXISTS)) {
			command_line.printerr("ERROR: File not found: %s\n", file_path);
			return 1;
		}
		if (!GLib.FileUtils.test(file_path, GLib.FileTest.IS_REGULAR)) {
			command_line.printerr("ERROR: Not a regular file: %s\n", file_path);
			return 1;
		}

		string markdown_content;
		try {
			GLib.FileUtils.get_contents(file_path, out markdown_content);
		} catch (GLib.FileError e) {
			command_line.printerr("ERROR: Failed to read file: %s\n", e.message);
			return 1;
		}

		// Hold so app stays alive until window is closed
		this.hold();

		// Create window with markdown widget
		var window = build_markdown_window(file_path, markdown_content);
		var loop = new MainLoop();
		window.close_request.connect(() => {
			loop.quit();
			this.release();
			this.quit();
			return false;  // allow default close behaviour
		});
		window.present();

		// Block until window is closed
		loop.run();

		return 0;
	}

	private Gtk.Window build_markdown_window(string title, string markdown_content)
	{
		var window = new Gtk.ApplicationWindow(this) {
			title = title,
			default_width = 700,
			default_height = 500
		};

		var text_view_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			hexpand = true,
			vexpand = true,
			margin_start = 8,
			margin_end = 8,
			margin_top = 8,
			margin_bottom = 8
		};

		var renderer = new MarkdownGtk.Render(text_view_box) {
			scroll_to_end = false
		};

		renderer.start();
		renderer.add(markdown_content);
		renderer.flush();

		var scrolled = new Gtk.ScrolledWindow() {
			hexpand = true,
			vexpand = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
			vscrollbar_policy = Gtk.PolicyType.AUTOMATIC
		};
		scrolled.set_child(text_view_box);

		window.set_child(scrolled);
		return window;
	}

	internal static string help_text()
	{
		return """
Usage: oc-test-gtkmd [OPTIONS] <markdown_file>

Opens a window with the GTK markdown widget and renders the given markdown file.

Arguments:
  markdown_file              Path to a markdown file to render

Options:
  -f, --file=FILE            Markdown file to render (alternative to positional arg)
  -h, --help                  Show this help and exit

Examples:
  oc-test-gtkmd README.md
  oc-test-gtkmd --file=docs/notes.md
""";
	}
}

int main(string[] args)
{
	// Handle --help without starting GTK (avoids "Failed to open display" when no display)
	for (int i = 1; i < args.length; i++) {
		if (args[i] == "--help" || args[i] == "-h") {
			stdout.printf("%s", TestGtkMd.help_text());
			return 0;
		}
	}
	var app = new TestGtkMd();
	return app.run(args);
}
