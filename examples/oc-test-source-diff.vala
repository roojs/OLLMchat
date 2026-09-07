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
		this.review_bar.file_index_changed.connect((index) => {
			if (index < 0 || index >= this.pair_baselines.length) {
				return;
			}
			this.current_file_index = index;
			this.window.title = this.pair_titles[index];
			var differ = new OLLMfiles.Diff.Differ(
				this.pair_baselines[index], this.pair_currents[index]);
			this.source_view.show_diff(differ);
			this.review_bar.update_diff(differ, index);
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
		this.window.set_child(this.root_box);
		this.current_file_index = 0;
		this.window.title = this.pair_titles[0];
		var differ = new OLLMfiles.Diff.Differ(
			this.pair_baselines[0], this.pair_currents[0]);
		this.source_view.show_diff(differ);
		this.review_bar.update_diff(differ, 0);
		var loop = new GLib.MainLoop();
		this.window.close_request.connect(() => {
			loop.quit();
			return false;
		});
		this.window.present();
		loop.run();
	}

	public static int main(string[] args)
	{
		return new TestSourceDiff().run(args);
	}
}
