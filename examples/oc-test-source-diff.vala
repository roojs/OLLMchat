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
 * Smoke: {@link TestAppBase} window showing {@link OLLMcoder.SourceView} inline diff
 * and {@link OLLMcoder.Diff.ReviewBar} Phase A mock review chrome.
 *
 * Usage: oc-test-source-diff [OPTIONS] <baseline> <current> [<baseline> <current> ...]
 * text1 = baseline (V_backup), text2 = current (V_disk).
 */
class TestSourceDiff : TestAppBase
{
	private static bool opt_mock_inactive = false;

	private Gtk.Window window;
	private Gtk.Box root_box;
	private Gtk.Overlay editor_overlay;
	private OLLMcoder.SourceView source_view;
	private OLLMcoder.Diff.ReviewBar review_bar;
	private string[] pair_baselines = {};
	private string[] pair_currents = {};
	private string[] pair_titles = {};
	private int current_file_index = 0;
	private int highlight_line = -2;
	private Gtk.Label add_swatch;
	private Gtk.Label remove_swatch;
	private Gtk.Label add_active_swatch;
	private Gtk.Label remove_active_swatch;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <baseline> <current> [<baseline> <current> ...]

Opens a window with SourceView.show_diff of the file pair(s) plus footer review bar.
Pass two or more baseline/current pairs to exercise real file prev/next in the footer.

Arguments:
  baseline_file              Old / backup text (Differ text1)
  current_file               New / disk text (Differ text2)
  ...                        Optional further baseline/current pairs

Options:
  --mock-inactive            Show "N changes pending review" instead of hunk bands

Click a red or green line to make that hunk the deep color. Click unchanged
text to clear it and hide Accept and Reject. Shades are .oc-diff-add,
.oc-diff-remove, .oc-diff-add-active, and .oc-diff-remove-active in
resources/style.css (`color` is the line background).

Examples:
  {ARG} tests/source-diff/review-smoke-baseline.txt tests/source-diff/review-smoke-current.txt
  {ARG} tests/source-diff/review-smoke-baseline.txt tests/source-diff/review-smoke-current.txt \\
      tests/source-diff/hello-baseline.txt tests/source-diff/hello-current.txt
  {ARG} --mock-inactive \\
      tests/source-diff/review-smoke-baseline.txt tests/source-diff/review-smoke-current.txt \\
      tests/source-diff/hello-baseline.txt tests/source-diff/hello-current.txt
"""; }

	public TestSourceDiff()
	{
		base("com.roojs.ollmchat.test-source-diff");
	}

	protected override string get_app_name()
	{
		return "oc-test-source-diff";
	}

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		var opts = new OptionEntry[4];
		opts[0] = base_options[0];
		opts[1] = base_options[1];
		opts[2] = { "mock-inactive", 0, 0, OptionArg.NONE, ref opt_mock_inactive,
			"Show pending-review label instead of hunk bands", null };
		opts[3] = { null };
		opt_context.add_main_entries(opts, null);
		return opt_context;
	}

	protected override string? validate_args(string[] args)
	{
		if (args.length < 3 || args[1] == "" || args[2] == "") {
			return "ERROR: At least one baseline/current pair required.\nUsage: %s <baseline> <current> [...]\n".printf(args[0]);
		}
		if ((args.length - 1) % 2 != 0) {
			return "ERROR: File arguments must be baseline/current pairs (even count).\n";
		}
		return null;
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] args) throws Error
	{
		if (!Gtk.init_check()) {
			command_line.printerr("ERROR: Failed to initialize GTK (no display?)\n");
			throw new GLib.IOError.FAILED("Failed to initialize GTK");
		}
		var css_provider = new Gtk.CssProvider();
		css_provider.load_from_resource("/ollmchat/style.css");
		Gtk.StyleContext.add_provider_for_display(
			Gdk.Display.get_default(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
		var pair_count = (args.length - 1) / 2;
		for (var pi = 0; pi < pair_count; pi++) {
			var baseline_arg = args[1 + pi * 2];
			var current_arg = args[2 + pi * 2];
			var baseline_path = GLib.Path.is_absolute(baseline_arg)
				? baseline_arg
				: GLib.Path.build_filename(GLib.Environment.get_current_dir(), baseline_arg);
			var current_path = GLib.Path.is_absolute(current_arg)
				? current_arg
				: GLib.Path.build_filename(GLib.Environment.get_current_dir(), current_arg);
			var baseline = "";
			var current = "";
			GLib.FileUtils.get_contents(baseline_path, out baseline);
			GLib.FileUtils.get_contents(current_path, out current);
			this.pair_baselines += baseline;
			this.pair_currents += current;
			this.pair_titles += "%s → %s".printf(
				GLib.Path.get_basename(baseline_path),
				GLib.Path.get_basename(current_path));
		}
		this.window = new Gtk.Window() {
			title = this.pair_titles[0],
			default_width = 720,
			default_height = 520
		};
		this.source_view = new OLLMcoder.SourceView(new OLLMfiles.ProjectManager()) {
			hexpand = true,
			vexpand = true,
		};
		this.review_bar = new OLLMcoder.Diff.ReviewBar(
			this.source_view, pair_count, opt_mock_inactive, 0, this.pair_titles);
		var review_responses = new Gee.ArrayList<OLLMcoder.Diff.ReviewResponse>();
		review_responses.add(new OLLMcoder.Diff.ReviewResponse() {
			label = "Coding standards",
			prompt = "This section of code does not follow coding standards. "
				+ "Please refer to docs/coding-standards-router.md and the mapped "
				+ "sections in docs/coding-standards.md.",
			tooltip = "Report coding standards issue for this hunk",
			is_bulk = false,
		});
		review_responses.add(new OLLMcoder.Diff.ReviewResponse() {
			label = "Helper methods (whole file)",
			prompt = "This file contains helper methods that were not requested. "
				+ "Do not add helper methods unless the user or plan names them.",
			tooltip = "Report unauthorized helper methods for the whole file",
			is_bulk = true,
		});
		this.review_bar.responses(review_responses);
		this.add_swatch = new Gtk.Label("") {
			css_classes = { "oc-diff-add" },
			visible = false,
		};
		this.remove_swatch = new Gtk.Label("") {
			css_classes = { "oc-diff-remove" },
			visible = false,
		};
		this.add_active_swatch = new Gtk.Label("") {
			css_classes = { "oc-diff-add-active" },
			visible = false,
		};
		this.remove_active_swatch = new Gtk.Label("") {
			css_classes = { "oc-diff-remove-active" },
			visible = false,
		};
		this.review_bar.file_index_changed.connect((index) => {
			if (index < 0 || index >= this.pair_baselines.length) {
				return;
			}
			this.current_file_index = index;
			this.highlight_line = -2;
			this.window.title = this.pair_titles[index];
			var differ = new OLLMfiles.Diff.Differ(
				this.pair_baselines[index], this.pair_currents[index]);
			this.source_view.show_diff(differ);
			this.review_bar.update_diff(differ, index);
			this.apply_highlight();
		});
		this.editor_overlay = new Gtk.Overlay() {
			vexpand = true,
			hexpand = true,
		};
		this.editor_overlay.set_child(this.source_view);
		this.editor_overlay.add_overlay(this.review_bar.review_overlay);
		this.root_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			hexpand = true,
			vexpand = true,
		};
		this.root_box.append(this.editor_overlay);
		this.root_box.append(this.review_bar);
		this.root_box.append(this.add_swatch);
		this.root_box.append(this.remove_swatch);
		this.root_box.append(this.add_active_swatch);
		this.root_box.append(this.remove_active_swatch);
		this.window.set_child(this.root_box);
		var text_view = (GtkSource.View) ((Gtk.ScrolledWindow) ((Gtk.Overlay) this.source_view
			.get_first_child().get_next_sibling()).get_child()).child;
		var hunk_click = new Gtk.GestureClick();
		hunk_click.pressed.connect((n_press, x, y) => {
			if (n_press < 1) {
				return;
			}
			var bx = 0;
			var by = 0;
			text_view.window_to_buffer_coords(
				Gtk.TextWindowType.WIDGET, (int) x, (int) y, out bx, out by);
			Gtk.TextIter at;
			if (!text_view.get_iter_at_location(out at, bx, by)) {
				return;
			}
			var add_tag = this.source_view.current_buffer.tag_table.lookup("diff-add");
			var remove_tag = this.source_view.current_buffer.tag_table.lookup("diff-remove");
			if (add_tag == null || remove_tag == null) {
				return;
			}
			Gtk.TextIter line_iter;
			this.source_view.current_buffer.get_iter_at_line(out line_iter, at.get_line());
			if (!line_iter.has_tag(add_tag) && !line_iter.has_tag(remove_tag)) {
				this.highlight_line = -1;
				this.apply_highlight();
				return;
			}
			this.highlight_line = at.get_line();
			this.apply_highlight();
		});
		text_view.add_controller(hunk_click);
		this.current_file_index = 0;
		this.window.title = this.pair_titles[0];
		var differ = new OLLMfiles.Diff.Differ(
			this.pair_baselines[0], this.pair_currents[0]);
		this.source_view.show_diff(differ);
		this.review_bar.update_diff(differ, 0);
		this.review_bar.review_response.connect((response, file_index, hunk_index) => {
			GLib.print("Review response [%s] file=%d hunk=%d:\n%s\n\n".printf(
				response.label, file_index, hunk_index, response.prompt));
		});
		var loop = new GLib.MainLoop();
		this.window.close_request.connect(() => {
			loop.quit();
			return false;
		});
		this.window.present();
		GLib.Idle.add(() => {
			this.apply_highlight();
			return Source.REMOVE;
		});
		loop.run();
	}

	/**
	 * Copy the hunk-wash CSS ``color`` onto the diff line backgrounds.
	 *
	 * Inactive lines use ``.oc-diff-add`` and ``.oc-diff-remove``. The hunk at
	 * {@link highlight_line} uses the ``-active`` rules. A value below 0, other
	 * than -1, means the first changed hunk. -1 clears that wash and hides
	 * Accept and Reject.
	 */
	private void apply_highlight()
	{
		var add_tag = this.source_view.current_buffer.tag_table.lookup("diff-add");
		var remove_tag = this.source_view.current_buffer.tag_table.lookup("diff-remove");
		if (add_tag == null || remove_tag == null) {
			return;
		}
		add_tag.paragraph_background_rgba = this.add_swatch.get_color();
		remove_tag.paragraph_background_rgba = this.remove_swatch.get_color();
		var active_add = this.source_view.current_buffer.tag_table.lookup("diff-add-active");
		if (active_add == null) {
			active_add = new Gtk.TextTag("diff-add-active");
			this.source_view.current_buffer.tag_table.add(active_add);
		}
		var active_remove = this.source_view.current_buffer.tag_table.lookup("diff-remove-active");
		if (active_remove == null) {
			active_remove = new Gtk.TextTag("diff-remove-active");
			this.source_view.current_buffer.tag_table.add(active_remove);
		}
		active_add.paragraph_background_rgba = this.add_active_swatch.get_color();
		active_remove.paragraph_background_rgba = this.remove_active_swatch.get_color();
		Gtk.TextIter bounds_start, bounds_end;
		this.source_view.current_buffer.get_bounds(out bounds_start, out bounds_end);
		this.source_view.current_buffer.remove_tag(active_add, bounds_start, bounds_end);
		this.source_view.current_buffer.remove_tag(active_remove, bounds_start, bounds_end);
		if (this.highlight_line == -1) {
			this.review_bar.review_overlay.visible = false;
			return;
		}
		var anchor = this.highlight_line;
		if (anchor < 0) {
			anchor = -1;
			for (var i = 0; i < this.source_view.current_buffer.get_line_count(); i++) {
				Gtk.TextIter line_iter;
				this.source_view.current_buffer.get_iter_at_line(out line_iter, i);
				if (!line_iter.has_tag(add_tag) && !line_iter.has_tag(remove_tag)) {
					continue;
				}
				anchor = i;
				break;
			}
		}
		if (anchor < 0) {
			this.review_bar.review_overlay.visible = false;
			return;
		}
		var hunk_start = anchor;
		while (hunk_start > 0) {
			Gtk.TextIter prev;
			this.source_view.current_buffer.get_iter_at_line(out prev, hunk_start - 1);
			if (!prev.has_tag(add_tag) && !prev.has_tag(remove_tag)) {
				break;
			}
			hunk_start--;
		}
		var hunk_end = anchor;
		while (hunk_end + 1 < this.source_view.current_buffer.get_line_count()) {
			Gtk.TextIter next;
			this.source_view.current_buffer.get_iter_at_line(out next, hunk_end + 1);
			if (!next.has_tag(add_tag) && !next.has_tag(remove_tag)) {
				break;
			}
			hunk_end++;
		}
		for (var i = hunk_start; i <= hunk_end; i++) {
			Gtk.TextIter from, to;
			this.source_view.current_buffer.get_iter_at_line(out from, i);
			to = from;
			if (!to.ends_line()) {
				to.forward_to_line_end();
			}
			if (from.has_tag(add_tag)) {
				this.source_view.current_buffer.apply_tag(active_add, from, to);
			}
			if (from.has_tag(remove_tag)) {
				this.source_view.current_buffer.apply_tag(active_remove, from, to);
			}
		}
		this.review_bar.review_overlay.visible = true;
	}

	public static int main(string[] args)
	{
		return new TestSourceDiff().run(args);
	}
}
