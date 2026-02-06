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
	private static int opt_stream_delay_sec = -1;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <markdown_file>

Opens a window with the GTK markdown widget and renders the given markdown file.

Arguments:
  markdown_file              Path to a markdown file to render

Options:
  -s, --stream SECS          Emulate streaming: wait SECS seconds then feed content in chunks (0 = start immediately)

Examples:
  {ARG} README.md
  {ARG} --stream 0 tests/markdown/tables.md
  {ARG} -s 15 -f docs/notes.md
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
		{ "stream", 's', 0, OptionArg.INT, ref opt_stream_delay_sec, "Seconds to wait before starting stream (0 = immediately)", "SECS" },
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

		bool stream = (opt_stream_delay_sec >= 0);
		var window = build_markdown_window(file_path, markdown_content, stream, stream ? opt_stream_delay_sec : 0);
		var loop = new MainLoop();
		window.close_request.connect(() => {
			loop.quit();
			return false;  // allow default close behaviour
		});
		window.present();

		loop.run();
	}

	private Gtk.Window build_markdown_window(string title, string markdown_content, bool stream, int stream_delay_sec)
	{
		// Load CSS from resources (same as ChatView; resources are in libollmchat)
		string[] css_files = { "pulldown.css", "style.css" };
		foreach (var css_file in css_files) {
			var css_provider = new Gtk.CssProvider();
			try {
				css_provider.load_from_resource(@"/ollmchat/$(css_file)");
				Gtk.StyleContext.add_provider_for_display(
					Gdk.Display.get_default(),
					css_provider,
					Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
				);
			} catch (GLib.Error e) {
				GLib.warning("Failed to load %s resource: %s", css_file, e.message);
			}
		}

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

		var scrolled = new Gtk.ScrolledWindow() {
			hexpand = true,
			vexpand = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
			vscrollbar_policy = Gtk.PolicyType.AUTOMATIC
		};
		scrolled.set_child(text_view_box);

		var renderer = new MarkdownGtk.Render(text_view_box) {
			scroll_to_end = stream
		};
		renderer.link_clicked.connect((href, title) => {
			// Only open http/https URLs; reference-style links have href as a label
			if (href.has_prefix("http://") || href.has_prefix("https://")) {
				try {
					Gtk.show_uri(window, href, 0);
				} catch (GLib.Error e) {
					GLib.warning("Failed to open link %s: %s", href, e.message);
				}
			}
		});

		renderer.start();
		if (stream) {
			if (stream_delay_sec > 0) {
				GLib.Timeout.add_full(GLib.Priority.DEFAULT, (uint) (stream_delay_sec * 1000), () => {
					this.start_streaming(renderer, scrolled, markdown_content);
					return false;
				});
			} else {
				this.start_streaming(renderer, scrolled, markdown_content);
			}
		} else {
			renderer.add(markdown_content);
			renderer.flush();
		}

		window.set_child(scrolled);
		return window;
	}

	private void start_streaming(MarkdownGtk.Render renderer, Gtk.ScrolledWindow scrolled, string markdown_content)
	{
		// Feed content in random-sized chunks (2–8 chars) every ~30ms to emulate streaming.
		// Advance by full UTF-8 characters so we never split a multi-byte character (substring uses byte offsets).
		int[] pos = { 0 };
		const uint interval_ms = 30;
		GLib.Timeout.add(interval_ms, () => {
			if (pos[0] >= markdown_content.length) {
				renderer.flush();
				return false;
			}
			int chunk_chars = (int) (GLib.Random.next_int() % 7 + 2);  // 2–8 characters
			int end_byte = pos[0];
			for (int i = 0; i < chunk_chars && end_byte < markdown_content.length; i++) {
				end_byte += markdown_content.get_char(end_byte).to_string().length;
			}
			if (end_byte > markdown_content.length) {
				end_byte = (int) markdown_content.length;
			}
			renderer.add(markdown_content.substring(pos[0], end_byte - pos[0]));
			pos[0] = end_byte;
			// Scroll to bottom after layout updates (streaming autoscroll).
			// Retry on next idle if layout not ready (upper too small); otherwise force to max.
			GLib.Idle.add(() => {
				var vadj = scrolled.vadjustment;
				if (vadj == null) {
					return false;
				}
				if (vadj.upper < 100.0) {
					return true;  // layout not ready, retry next idle
				}
				vadj.value = vadj.upper + 1000.0;  // force scroll to bottom (clamped by GTK)
				return false;
			});
			return true;
		});
	}
}

int main(string[] args)
{
	var app = new TestGtkMd();
	return app.run(args);
}
