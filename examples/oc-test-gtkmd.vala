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
 * Extends TestAppBase and uses ApplicationInterface for standard debug options,
 * log handling, and help.
 */
class TestGtkMd : TestAppBase
{
	private static string? opt_file = null;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <markdown_file>

Opens a window with the GTK markdown widget and renders the given markdown file.

Arguments:
  markdown_file              Path to a markdown file to render

Examples:
  {ARG} README.md
  {ARG} --file=docs/notes.md
  {ARG} -d tests/data/markdown/tables.md
"""; }

	public TestGtkMd()
	{
		base("com.roojs.ollmchat.test-gtkmd");
	}

	protected override string get_app_name()
	{
		return "oc-test-gtkmd";
	}

	private const OptionEntry[] local_options = {
		{ "file", 'f', 0, OptionArg.STRING, ref opt_file, "Markdown file to render (alternative to positional arg)", "FILE" },
		{ null }
	};

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		var base_opts = new OptionEntry[3];
		base_opts[0] = base_options[0];  // debug
		base_opts[1] = base_options[1];   // debug-critical
		base_opts[2] = { null };
		opt_context.add_main_entries(base_opts, null);

		var app_group = new OptionGroup("oc-test-gtkmd", "GTK Markdown Viewer Options", "Show oc-test-gtkmd options");
		app_group.add_entries(local_options);
		opt_context.add_group(app_group);

		return opt_context;
	}

	protected override string? validate_args(string[] remaining_args)
	{
		string? file_path = (opt_file != null && opt_file != "") ? opt_file : null;
		if (file_path == null && remaining_args.length > 1) {
			file_path = remaining_args[1];
		}
		if (file_path == null || file_path == "") {
			return "ERROR: Markdown file is required.\nUsage: %s <markdown_file>\n".printf(remaining_args[0]);
		}
		return null;
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] remaining_args) throws Error
	{
		if (!Gtk.init_check()) {
			command_line.printerr("ERROR: Failed to initialize GTK (no display?)\n");
			throw new GLib.IOError.FAILED("Failed to initialize GTK");
		}

		string? file_path = (opt_file != null && opt_file != "") ? opt_file : remaining_args[1];
		if (!GLib.Path.is_absolute(file_path)) {
			file_path = GLib.Path.build_filename(GLib.Environment.get_current_dir(), file_path);
		}
		if (!GLib.FileUtils.test(file_path, GLib.FileTest.EXISTS)) {
			command_line.printerr("ERROR: File not found: %s\n", file_path);
			throw new GLib.IOError.NOT_FOUND("File not found: " + file_path);
		}
		if (!GLib.FileUtils.test(file_path, GLib.FileTest.IS_REGULAR)) {
			command_line.printerr("ERROR: Not a regular file: %s\n", file_path);
			throw new GLib.IOError.INVALID_ARGUMENT("Not a regular file: " + file_path);
		}

		string markdown_content;
		try {
			GLib.FileUtils.get_contents(file_path, out markdown_content);
		} catch (GLib.FileError e) {
			command_line.printerr("ERROR: Failed to read file: %s\n", e.message);
			throw new GLib.IOError.FAILED("Failed to read file: %s", e.message);
		}

		var window = build_markdown_window(file_path, markdown_content);
		var loop = new MainLoop();
		window.close_request.connect(() => {
			loop.quit();
			return false;  // allow default close behaviour
		});
		window.present();

		loop.run();
	}

	private Gtk.Window build_markdown_window(string title, string markdown_content)
	{
		var window = new Gtk.Window() {
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
}

int main(string[] args)
{
	var app = new TestGtkMd();
	return app.run(args);
}
