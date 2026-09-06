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
 * Usage: oc-test-source-diff [OPTIONS] <baseline_file> <current_file>
 * text1 = baseline (V_backup), text2 = current (V_disk).
 */
class TestSourceDiff : TestAppBase
{
	private static int opt_mock_files = 1;
	private static bool opt_mock_inactive = false;

	private Gtk.Window window;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <baseline_file> <current_file>

Opens a window with SourceView.show_diff of the two files plus footer review bar.

Arguments:
  baseline_file              Old / backup text (Differ text1)
  current_file               New / disk text (Differ text2)

Options:
  --mock-files=N             Stub pending file count for footer nav (default 1)
  --mock-inactive            Show "N changes pending review" instead of hunk bands

Examples:
  {ARG} old.vala new.vala
  {ARG} --mock-files=5 --mock-inactive tests/source-diff/hello-baseline.txt tests/source-diff/hello-current.txt
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
		var opts = new OptionEntry[5];
		opts[0] = base_options[0];
		opts[1] = base_options[1];
		opts[2] = { "mock-files", 0, 0, OptionArg.INT, ref opt_mock_files,
			"Stub pending file count for footer nav", "N" };
		opts[3] = { "mock-inactive", 0, 0, OptionArg.NONE, ref opt_mock_inactive,
			"Show pending-review label instead of hunk bands", null };
		opts[4] = { null };
		opt_context.add_main_entries(opts, null);
		return opt_context;
	}

	protected override string? validate_args(string[] args)
	{
		if (args.length < 3 || args[1] == "" || args[2] == "") {
			return "ERROR: Two files required.\nUsage: %s <baseline_file> <current_file>\n".printf(args[0]);
		}
		if (opt_mock_files < 1) {
			opt_mock_files = 1;
		}
		return null;
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] args) throws Error
	{
		if (!Gtk.init_check()) {
			command_line.printerr("ERROR: Failed to initialize GTK (no display?)\n");
			throw new GLib.IOError.FAILED("Failed to initialize GTK");
		}
		var baseline_path = GLib.Path.is_absolute(args[1])
			? args[1]
			: GLib.Path.build_filename(GLib.Environment.get_current_dir(), args[1]);
		var current_path = GLib.Path.is_absolute(args[2])
			? args[2]
			: GLib.Path.build_filename(GLib.Environment.get_current_dir(), args[2]);
		var baseline = "";
		var current = "";
		GLib.FileUtils.get_contents(baseline_path, out baseline);
		GLib.FileUtils.get_contents(current_path, out current);
		this.window = new Gtk.Window() {
			title = "%s → %s".printf(
				GLib.Path.get_basename(baseline_path),
				GLib.Path.get_basename(current_path)),
			default_width = 720,
			default_height = 520
		};
		var source_view = new OLLMcoder.SourceView(new OLLMfiles.ProjectManager());
		var differ = new OLLMfiles.Diff.Differ(baseline, current);
		source_view.show_diff(differ);
		var review_bar = new OLLMcoder.Diff.ReviewBar(
			source_view, differ, opt_mock_files, opt_mock_inactive);
		var editor_overlay = new Gtk.Overlay() {
			vexpand = true,
			hexpand = true,
		};
		editor_overlay.set_child(source_view);
		editor_overlay.add_overlay(review_bar.review_overlay);
		var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			hexpand = true,
			vexpand = true,
		};
		root.append(editor_overlay);
		root.append(review_bar);
		this.window.set_child(root);
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
