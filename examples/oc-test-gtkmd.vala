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
 * Example: oc-test-gtkmd with optional markdown file path.
 *
 * Opens a window with the GTK markdown widget and renders the given
 * markdown file, or replays session JSON with {{{--history}}}.
 *
 * Extends TestAppBase for standard debug options, log handling, and help.
 *
 * @see TestAppBase
 */
class TestGtkMd : TestAppBase
{
	private static string? opt_file = null;
	private static int opt_stream_delay_sec = -1;
	private static bool opt_thinking = false;
	private static string? opt_history = null;

	private Gtk.Window window;
	private Gtk.Box text_view_box;
	private Gtk.ScrolledWindow scrolled;
	private MarkdownGtk.Render md_renderer;

	private string window_title { get; set; default = ""; }
	private string file_markdown { get; set; default = ""; }
	private Json.Array history_messages { get; set; default = new Json.Array(); }
	private int history_msg_start { get; set; default = 0; }

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] [<markdown_file>]

Opens a window with the GTK markdown widget and renders the given markdown file.

Arguments:
  markdown_file              Path to a markdown file (omit if --history is set)

Options:
  -s, --stream SECS          Emulate streaming: wait SECS seconds then feed content in chunks (0 = start immediately)
  -t, --thinking             Nested ```markdown block (RenderSourceView + nested MarkdownGtk.Render), like ChatView thinking
      --history FILE         Session JSON: replay messages from the start (ui / think-stream / content-stream) like ChatWidget

Examples:
  {ARG} README.md
  {ARG} --stream 0 tests/markdown/tables.md
  {ARG} -s 15 -f docs/notes.md
  {ARG} --thinking tests/markdown/repro-chatview-thinking-lines.md
  {ARG} --thinking --stream 0 tests/markdown/repro-chatview-thinking-lines.md
  {ARG} --thinking tests/markdown/repro-state-stack-overflow.md
  {ARG} --thinking tests/markdown/repro-gtkmd-hang.md
  {ARG} --history ~/.local/share/ollmchat/history/2026/04/01/23-56-59.json
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
		{ "thinking", 't', 0, OptionArg.NONE, ref opt_thinking, "Use ChatView-style markdown code block + nested MarkdownGtk.Render", null },
		{ "history", 0, 0, OptionArg.STRING, ref opt_history, "Session JSON: replay messages from the start", "FILE" },
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

	protected override string? validate_args(string[] args)
	{
		opt_file = opt_file == null ? "" : opt_file;
		opt_history = opt_history == null ? "" : opt_history;
		if (opt_history != "") {
			return null;
		}
		if (opt_file == "" && (args.length < 2 || args[1] == "")) {
			return "ERROR: Markdown file is required unless --history is set.\nUsage: %s <markdown_file>\n".printf(args[0]);
		}
		return null;
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] args) throws Error
	{
		if (!Gtk.init_check()) {
			command_line.printerr("ERROR: Failed to initialize GTK (no display?)\n");
			throw new GLib.IOError.FAILED("Failed to initialize GTK");
		}

		if (opt_history != "") {
			this.load_json(opt_history);
			this.build_window();
			this.render_history();
			this.run_loop();
			return;
		}

		this.load_file(opt_file != "" ? opt_file : args[1]);
		this.build_window();

		if (opt_thinking) {
			this.render_thinking(
				opt_stream_delay_sec > -1,
				opt_stream_delay_sec > -1 ? opt_stream_delay_sec : 0
			);
			this.run_loop();
			return;
		}
		if (opt_stream_delay_sec > -1) {
			this.start_streaming(this.file_markdown, opt_stream_delay_sec);
			this.run_loop();
			return;
		}
		this.md_renderer.add(this.file_markdown);
		this.md_renderer.flush();
		GLib.Timeout.add(200, () => {
			this.text_view_box.queue_resize();
			this.scrolled.queue_resize();
			return false;
		});
		this.run_loop();
	}

	private void run_loop()
	{
		var loop = new GLib.MainLoop();
		this.window.close_request.connect(() => {
			loop.quit();
			return false;
		});
		this.window.present();
		loop.run();
	}

	private string resolve_path(string path)
	{
		if (GLib.Path.is_absolute(path)) {
			return path;
		}
		return GLib.Path.build_filename(GLib.Environment.get_current_dir(), path);
	}

	private void load_file(string path) throws Error
	{
		var p = this.resolve_path(path);
		if (!GLib.FileUtils.test(p, GLib.FileTest.EXISTS)) {
			throw new GLib.IOError.NOT_FOUND("File not found: " + p);
		}
		if (!GLib.FileUtils.test(p, GLib.FileTest.IS_REGULAR)) {
			throw new GLib.IOError.INVALID_ARGUMENT("Not a regular file: " + p);
		}
		try {
			var contents = "";
			GLib.FileUtils.get_contents(p, out contents);
			this.file_markdown = contents;
		} catch (GLib.FileError e) {
			throw new GLib.IOError.FAILED("Failed to read file: %s", e.message);
		}
		this.window_title = GLib.Path.get_basename(p);
		GLib.debug("%s", p);
	}

	private void load_json(string path) throws Error
	{
		var p = this.resolve_path(path);
		GLib.debug("loading json %s", p);
		if (!GLib.FileUtils.test(p, GLib.FileTest.EXISTS)) {
			throw new GLib.IOError.NOT_FOUND("File not found: " + p);
		}
		if (!GLib.FileUtils.test(p, GLib.FileTest.IS_REGULAR)) {
			throw new GLib.IOError.INVALID_ARGUMENT("Not a regular file: " + p);
		}

		var parser = new Json.Parser();
		parser.load_from_file(p);
		var root = parser.get_root();
		if (root.get_node_type() != Json.NodeType.OBJECT) {
			throw new GLib.IOError.INVALID_ARGUMENT("session root must be object");
		}
		var obj = root.get_object();
		if (!obj.has_member("messages")) {
			throw new GLib.IOError.INVALID_ARGUMENT("session has no messages");
		}
		var msg_node = obj.get_member("messages");
		if (msg_node.get_node_type() != Json.NodeType.ARRAY) {
			throw new GLib.IOError.INVALID_ARGUMENT("messages must be array");
		}
		var arr = msg_node.get_array();
		this.history_messages = arr;
		this.window_title = GLib.Path.get_basename(p);
		GLib.debug("messages=%u", this.history_messages.get_length());
	}

	private void build_window()
	{
		string[] css_files = { "pulldown.css", "style.css" };
		foreach (var css_file in css_files) {
			var css_provider = new Gtk.CssProvider();
			try {
				css_provider.load_from_resource("/ollmchat/" + css_file);
				Gtk.StyleContext.add_provider_for_display(
					Gdk.Display.get_default(),
					css_provider,
					Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
				);
			} catch (GLib.Error e) {
				GLib.warning("Failed to load %s resource: %s", css_file, e.message);
			}
		}

		var stream = (opt_stream_delay_sec >= 0);

		this.window = new Gtk.Window() {
			title = this.window_title,
			default_width = 700,
			default_height = 500
		};

		this.text_view_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			hexpand = true,
			vexpand = true,
			margin_start = 8,
			margin_end = 8,
			margin_top = 8,
			margin_bottom = 8
		};

		this.scrolled = new Gtk.ScrolledWindow() {
			hexpand = true,
			vexpand = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
			vscrollbar_policy = Gtk.PolicyType.AUTOMATIC
		};
		this.scrolled.set_child(this.text_view_box);

		this.md_renderer = new MarkdownGtk.Render(this.text_view_box) {
			scroll_to_end = this.history_messages.get_length() == 0 && stream
		};
		this.md_renderer.link_clicked.connect((href, link_title) => {
			if (href.has_prefix("http://") || href.has_prefix("https://")) {
				try {
					Gtk.show_uri(this.window, href, 0);
				} catch (GLib.Error e) {
					GLib.warning("Failed to open link %s: %s", href, e.message);
				}
			}
		});

		this.window.set_child(this.scrolled);

		this.md_renderer.start();
	}

	private void render_thinking(bool stream, int stream_delay_sec)
	{
		this.md_renderer.on_code_block(true, "markdown.oc-frame-info.thinking oc-test-gtkmd");
		if (stream) {
			this.start_streaming_thinking(this.file_markdown, stream_delay_sec);
			return;
		}
		assert(this.md_renderer.childview != null);
		this.md_renderer.childview.add_code_text(this.file_markdown);
		this.md_renderer.childview.end_code_block();
		GLib.Timeout.add(200, () => {
			this.text_view_box.queue_resize();
			this.scrolled.queue_resize();
			return false;
		});
		
	}

	private void render_history()
	{
		var n = this.history_messages.get_length();
		for (var i = this.history_msg_start; i < n; i++) {
			var el = this.history_messages.get_element(i);
			if (el.get_node_type() != Json.NodeType.OBJECT) {
				continue;
			}
			var msg = el.get_object();
			var role = msg.has_member("role") ? msg.get_string_member("role") : "";
			var content = msg.has_member("content") ? msg.get_string_member("content") : "";

			var think = "";
			var body = "";
			switch (role) {
				case "think-stream":
					think = content;
					break;
				case "content-stream":
				case "content-non-stream":
				case "ui":
					body = content;
					break;
				case "ui-warning":
					body = "⚠️ " + content;
					break;
				default:
					continue;
			}
			if (think != "") {
				this.md_renderer.on_code_block(true, "markdown.oc-frame-info.thinking oc-test-gtkmd");
				assert(this.md_renderer.childview != null);
				this.md_renderer.childview.add_code_text(think);
				this.md_renderer.childview.end_code_block();
			}
			if (body != "") {
				this.md_renderer.add(body);
				this.md_renderer.flush();
			}
		}
		GLib.Timeout.add(200, () => {
			this.text_view_box.queue_resize();
			this.scrolled.queue_resize();
			return false;
		});
	}

	private void start_streaming_thinking(string markdown_content, int delay_sec)
	{
		if (delay_sec > 0) {
			GLib.Timeout.add_full(GLib.Priority.DEFAULT, (uint) (delay_sec * 1000), () => {
				this.start_streaming_thinking(markdown_content, 0);
				return false;
			});
			return;
		}
		// Same chunk strategy as stream_content_chunks (2–8 Unicode chars, ~30ms), not line-by-line.
		int[] pos = { 0 };
		const uint interval_ms = 30;
		GLib.Timeout.add(interval_ms, () => {
			assert(this.md_renderer.childview != null);
			var cc = markdown_content.char_count();
			if (pos[0] >= cc) {
				this.md_renderer.childview.end_code_block();
				GLib.Timeout.add(200, () => {
					this.md_renderer.box.queue_resize();
					this.scrolled.queue_resize();
					return false;
				});
				return false;
			}
			var chunk_chars = (int) (GLib.Random.next_int() % 7 + 2);
			var end_ci = int.min(pos[0] + chunk_chars, cc);
			var start_byte = markdown_content.index_of_nth_char(pos[0]);
			var end_byte = end_ci >= cc ? markdown_content.length : markdown_content.index_of_nth_char(end_ci);
			this.md_renderer.childview.add_code_text(markdown_content.substring(start_byte, end_byte - start_byte));
			pos[0] = end_ci;
			GLib.Idle.add(() => {
				var vadj = this.scrolled.vadjustment;
				if (vadj.upper < 100.0) {
					return true;
				}
				vadj.value = vadj.upper + 1000.0;
				return false;
			});
			return true;
		});
	}

	private void start_streaming(string markdown_content, int delay_sec)
	{
		if (delay_sec > 0) {
			GLib.Timeout.add_full(GLib.Priority.DEFAULT, (uint) (delay_sec * 1000), () => {
				this.start_streaming(markdown_content, 0);
				return false;
			});
			return;
		}
		this.stream_content_chunks(markdown_content);
	}

	/**
	 * Feed body markdown in random-sized chunks (2–8 Unicode characters)
	 * every ~30ms. Uses character indices and {{{index_of_nth_char}}} for
	 * UTF-8 byte offsets (see Parser.vala string conventions).
	 */
	private void stream_content_chunks(string markdown_content)
	{
		int[] pos = { 0 };
		const uint interval_ms = 30;
		GLib.Timeout.add(interval_ms, () => {
			var cc = markdown_content.char_count();
			if (pos[0] >= cc) {
				this.md_renderer.flush();
				// Re-layout after nested blocks (e.g. ```markdown) finish.
				GLib.Timeout.add(200, () => {
					this.md_renderer.box.queue_resize();
					this.scrolled.queue_resize();
					return false;
				});
				return false;
			}
			var chunk_chars = (int) (GLib.Random.next_int() % 7 + 2);
			var end_ci = int.min(pos[0] + chunk_chars, cc);
			var start_byte = markdown_content.index_of_nth_char(pos[0]);
			var end_byte = end_ci >= cc ? markdown_content.length : markdown_content.index_of_nth_char(end_ci);
			this.md_renderer.add(markdown_content.substring(start_byte, end_byte - start_byte));
			pos[0] = end_ci;
			GLib.Idle.add(() => {
				var vadj = this.scrolled.vadjustment;
				if (vadj.upper < 100.0) {
					return true;
				}
				vadj.value = vadj.upper + 1000.0;
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
