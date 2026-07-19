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
 * Spike GTK app for {@link OLLMwebkit} — Phase 2 shows {@link OLLMwebkit.BrowserStack}.
 *
 * Extends {@link TestAppBase} for standard debug / log / help (same pattern as
 * ''oc-test-gtkmd''). Phase 3 adds CLI fetch / search / press / dump options.
 */
class OcTestWebkitApp : TestAppBase
{
	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS]

Phase 2 spike: open a window embedding BrowserStack (primary WebView).

Options:
  -d, --debug            Enable debug output
      --debug-critical   Treat critical warnings as errors

Examples:
  {ARG}
  {ARG} --debug
"""; }

	public OcTestWebkitApp()
	{
		base("com.roojs.oc-test-webkit");
	}

	protected override string get_app_name()
	{
		return "oc-test-webkit";
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

	public override OLLMchat.Settings.Config2 load_config()
	{
		return new OLLMchat.Settings.Config2();
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] args) throws Error
	{
		if (!Gtk.init_check()) {
			command_line.printerr("ERROR: Failed to initialize GTK (no display?)\n");
			throw new GLib.IOError.FAILED("Failed to initialize GTK");
		}

		var window = new Gtk.Window();
		window.title = "oc-test-webkit";
		window.default_width = 960;
		window.default_height = 720;
		window.set_child(new OLLMwebkit.BrowserStack());

		var loop = new GLib.MainLoop();
		window.close_request.connect(() => {
			loop.quit();
			return false;
		});
		window.present();
		loop.run();
	}
}

int main(string[] args)
{
	var app = new OcTestWebkitApp();
	return app.run(args);
}
