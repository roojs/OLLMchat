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
 * Smoke: {@link TestAppBase} window showing {@link OLLMcoder.SourceView} inline diff.
 *
 * Usage: oc-test-source-diff <baseline_file> <current_file>
 * text1 = baseline (V_backup), text2 = current (V_disk).
 */
class TestSourceDiff : TestAppBase
{
	private Gtk.Window window;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <baseline_file> <current_file>

Opens a window with SourceView.show_diff of the two files.

Arguments:
  baseline_file              Old / backup text (Differ text1)
  current_file               New / disk text (Differ text2)

Examples:
  {ARG} old.vala new.vala
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
		var base_opts = new OptionEntry[3];
		base_opts[0] = base_options[0];
		base_opts[1] = base_options[1];
		base_opts[2] = { null };
		opt_context.add_main_entries(base_opts, null);
		return opt_context;
	}

	protected override string? validate_args(string[] args)
	{
		if (args.length < 3 || args[1] == "" || args[2] == "") {
			return "ERROR: Two files required.\nUsage: %s <baseline_file> <current_file>\n".printf(args[0]);
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
			default_height = 480
		};
		var source_view = new OLLMcoder.SourceView(new OLLMfiles.ProjectManager());
		source_view.show_diff(new OLLMfiles.Diff.Differ(baseline, current));
		this.window.set_child(source_view);
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
