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
 * Example: oc-markdown-test {markdown file}
 *
 * Parses markdown file and outputs callback trace using DummyRenderer.
 * Extends TestAppBase for standard debug options, log handling, and help.
 */
class TestMarkdown : TestAppBase
{
	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <markdown_file>

Parses markdown file and outputs callback trace using DummyRenderer.

Arguments:
  markdown_file              Path to a markdown file to parse

Options:
  -d, --debug                 Enable debug output

Examples:
  {ARG} README.md
  {ARG} --debug tests/markdown/links.md
"""; }

	public TestMarkdown()
	{
		base("com.roojs.ollmchat.test-markdown");
	}

	protected override string get_app_name()
	{
		return "oc-markdown-test";
	}

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		var base_opts = new OptionEntry[3];
		base_opts[0] = base_options[0];  // debug
		base_opts[1] = base_options[1];  // debug-critical
		base_opts[2] = { null };
		opt_context.add_main_entries(base_opts, null);
		return opt_context;
	}

	public override OLLMchat.Settings.Config2 load_config()
	{
		return new OLLMchat.Settings.Config2();
	}

	protected override string? validate_args(string[] remaining_args)
	{
		if (remaining_args.length < 2 || remaining_args[1] == "") {
			return "ERROR: Markdown file is required.\n" + help.replace("{ARG}", remaining_args[0]);
		}
		return null;
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] remaining_args) throws Error
	{
		var file_path = remaining_args[1];
		if (!GLib.Path.is_absolute(file_path)) {
			file_path = GLib.Path.build_filename(GLib.Environment.get_current_dir(), file_path);
		}
		if (!GLib.FileUtils.test(file_path, GLib.FileTest.EXISTS)) {
			command_line.printerr("ERROR: File not found: %s\n", file_path);
			throw new GLib.IOError.NOT_FOUND("File not found: " + file_path);
		}

		string markdown_content;
		try {
			GLib.FileUtils.get_contents(file_path, out markdown_content);
		} catch (GLib.FileError e) {
			command_line.printerr("ERROR: Failed to read file '%s': %s\n", file_path, e.message);
			throw new GLib.IOError.FAILED("Failed to read file: %s", e.message);
		}

		var renderer = new Markdown.DummyRenderer();

		// Print path as given so test output is stable (not absolute)
		command_line.print("=== PARSING MARKDOWN FILE: %s ===\n", remaining_args[1]);
		command_line.print("=== FILE CONTENT (first 200 chars) ===\n");
		command_line.print("%.200s...\n\n", markdown_content);
		command_line.print("=== CALLBACK TRACE ===\n");

		renderer.start();
		renderer.add(markdown_content);
		renderer.flush();

		command_line.print("=== END TRACE ===\n");
	}
}

int main(string[] args)
{
	var app = new TestMarkdown();
	return app.run(args);
}
