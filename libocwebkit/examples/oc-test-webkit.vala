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
 * Spike GTK app for {@link OLLMwebkit}.
 *
 * Extends {@link TestAppBase}. One-shot ''--fetch'' / ''--search'', or
 * ''--script FILE'' (fetch / search / fill / press / whereami per line).
 * Without those, opens a BrowserStack window.
 */
class OcTestWebkitApp : TestAppBase
{
	protected static string? opt_script = null;
	protected static string? opt_fetch = null;
	protected static string? opt_search = null;
	protected static string? opt_format = null;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS]
       {ARG} --fetch URL [OPTIONS]
       {ARG} --search QUERY [OPTIONS]
       {ARG} --script FILE [OPTIONS]

Phase 3 spike: BrowserStack window, one-shot fetch/search, or a script.

Script lines (one action each; # comments ignored):
  fetch <url>
  search <terms>
  whereami
  press #<n>
  fill #<n>=<text>

After each navigation/fill/press: settle then print page output.

Options:
  -d, --debug            Enable debug output
      --debug-critical   Treat critical warnings as errors
      --fetch URL        Load URL and print page output
      --search QUERY     Google search terms and print page output
      --script FILE      Run commands from FILE (not stdin)
      --format FORMAT    a11y (default), html, or markdown

Examples:
  {ARG}
  {ARG} --fetch https://example.com/
  {ARG} --search 'Vala WebKitGTK'
  {ARG} --script libocwebkit/examples/recipes/google-search.txt
"""; }

	protected const OptionEntry[] local_options = {
		{ "script", 0, 0, OptionArg.FILENAME, ref opt_script, "Script file of browser commands", "FILE" },
		{ "fetch", 0, 0, OptionArg.STRING, ref opt_fetch, "Load URL and print page output", "URL" },
		{ "search", 0, 0, OptionArg.STRING, ref opt_search, "Google search terms and print page output", "QUERY" },
		{ "format", 0, 0, OptionArg.STRING, ref opt_format, "Output format: a11y, html, or markdown", "FORMAT" },
		{ null }
	};

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
		var app_group = new OptionGroup("oc-test-webkit", "WebKit spike options", "Show oc-test-webkit options");
		app_group.add_entries(local_options);
		opt_context.add_group(app_group);
		return opt_context;
	}

	public override OLLMchat.Settings.Config2 load_config()
	{
		return new OLLMchat.Settings.Config2();
	}

	protected override string? validate_args(string[] remaining_args)
	{
		opt_script = opt_script == null ? "" : opt_script;
		opt_fetch = opt_fetch == null ? "" : opt_fetch;
		opt_search = opt_search == null ? "" : opt_search;
		opt_format = opt_format == null || opt_format == "" ? "a11y" : opt_format;
		if (opt_format != "a11y" && opt_format != "html" && opt_format != "markdown") {
			return "Error: --format must be a11y, html, or markdown\n";
		}
		var modes = 0;
		if (opt_script != "") {
			modes++;
		}
		if (opt_fetch != "") {
			modes++;
		}
		if (opt_search != "") {
			modes++;
		}
		if (modes > 1) {
			return "Error: use only one of --script, --fetch, or --search\n";
		}
		return null;
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] args) throws Error
	{
		GLib.Environment.set_variable("GTK_A11Y", "atspi", false);
		if (!Gtk.init_check()) {
			command_line.printerr("ERROR: Failed to initialize GTK (no display?)\n");
			throw new GLib.IOError.FAILED("Failed to initialize GTK");
		}

		var stack = new OLLMwebkit.BrowserStack();
		var window = new Gtk.Window();
		window.title = "oc-test-webkit";
		window.default_width = 960;
		window.default_height = 720;
		window.set_child(stack);
		stack.cloudflare_blocked.connect((browser) => {
			command_line.printerr(
				"Cloudflare challenge — complete it in the window (uri=%s)\n",
				browser.current_uri
			);
		});
		stack.cloudflare_cleared.connect(() => {
			command_line.printerr("Cloudflare cleared\n");
		});
		window.present();

		if (opt_script == "" && opt_fetch == "" && opt_search == "") {
			var loop = new GLib.MainLoop();
			window.close_request.connect(() => {
				loop.quit();
				return false;
			});
			loop.run();
			return;
		}

		if (opt_fetch != "") {
			yield stack.primary.load(opt_fetch);
			command_line.print("%s\n", yield stack.primary.dump(opt_format));
			window.close();
			return;
		}
		if (opt_search != "") {
			yield stack.primary.load(
				"https://www.google.com/search?q=" + GLib.Uri.escape_string(opt_search) + "&hl=en");
			command_line.print("%s\n", yield stack.primary.dump(opt_format));
			window.close();
			return;
		}

		var script_file = GLib.File.new_for_path(opt_script);
		var stream = new GLib.DataInputStream(yield script_file.read_async());
		while (true) {
			var line = yield stream.read_line_async();
			if (line == null) {
				break;
			}
			var trimmed = line.strip();
			if (trimmed == "" || trimmed.has_prefix("#")) {
				continue;
			}
			command_line.print(">>> %s\n", trimmed);
			var space = trimmed.index_of_char(' ');
			var cmd = space < 0 ? trimmed.down() : trimmed.substring(0, space).down();
			var rest = space < 0 ? "" : trimmed.substring(space + 1).strip();
			switch (cmd) {
				case "fetch":
					if (rest == "") {
						throw new GLib.IOError.INVALID_ARGUMENT("fetch needs a URL");
					}
					yield stack.primary.load(rest);
					command_line.print("%s\n", yield stack.primary.dump(opt_format));
					break;

				case "search":
					if (rest == "") {
						throw new GLib.IOError.INVALID_ARGUMENT("search needs query terms");
					}
					yield stack.primary.load(
						"https://www.google.com/search?q=" + GLib.Uri.escape_string(rest) + "&hl=en");
					command_line.print("%s\n", yield stack.primary.dump(opt_format));
					break;

				case "whereami":
					command_line.print("%s\n", yield stack.primary.dump(opt_format));
					break;

				case "press":
					var press_tok = rest.has_prefix("#") ? rest.substring(1) : rest;
					var press_id = int.parse(press_tok);
					if (press_id <= 0) {
						throw new GLib.IOError.INVALID_ARGUMENT("press needs #<n>, got: %s", rest);
					}
					yield stack.primary.press(press_id);
					command_line.print("%s\n", yield stack.primary.dump(opt_format));
					break;

				case "fill":
					var eq = rest.index_of_char('=');
					if (eq < 1) {
						throw new GLib.IOError.INVALID_ARGUMENT("fill needs #<n>=<text>, got: %s", rest);
					}
					var fill_tok = rest.substring(0, eq).strip();
					if (fill_tok.has_prefix("#")) {
						fill_tok = fill_tok.substring(1);
					}
					var fill_map = new Gee.HashMap<string, string>();
					fill_map.set(fill_tok, rest.substring(eq + 1));
					yield stack.primary.fill(fill_map);
					command_line.print("%s\n", yield stack.primary.dump(opt_format));
					break;

				default:
					throw new GLib.IOError.INVALID_ARGUMENT("Unknown script command: %s", cmd);
			}
		}
		window.close();
	}
}

int main(string[] args)
{
	var app = new OcTestWebkitApp();
	return app.run(args);
}
