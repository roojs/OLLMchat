/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

/**
 * Example: oc-markdown-doc-test
 *
 * Converts between markdown and document JSON. Input from file; output to stdout.
 * Enables full-circle validation: markdown→JSON→markdown or JSON→markdown.
 */
class OcMarkdownDocTest : TestAppBase
{
	protected static string? opt_input_format = null;
	protected static string? opt_output_format = null;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] FILE

Reads markdown or document JSON from FILE and outputs JSON or markdown to stdout.

Options:
  -d, --debug                 Enable debug output
  -i, --input-format=FORMAT   Input: markdown (default) or json
  -o, --output-format=FORMAT  Output: json (default) or markdown

Examples:
  {ARG} doc.md                 # markdown → JSON
  {ARG} doc.md markdown        # markdown → markdown (round-trip; 2nd arg = output format)
  {ARG} doc.json markdown      # JSON → markdown
"""; }

	public OcMarkdownDocTest()
	{
		base("com.roojs.ollmchat.oc-markdown-doc-test");
	}

	protected override string get_app_name()
	{
		return "oc-markdown-doc-test";
	}

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		var base_opts = new OptionEntry[4];
		base_opts[0] = base_options[0];
		base_opts[1] = base_options[1];
		base_opts[2] = { "output-format", 'o', 0, OptionArg.STRING, ref opt_output_format, "Output format: json or markdown", "FORMAT" };
		base_opts[3] = { null };
		opt_context.add_main_entries(base_opts, null);
		return opt_context;
	}

	public override OLLMchat.Settings.Config2 load_config()
	{
		return new OLLMchat.Settings.Config2();
	}

	protected override string? validate_args(string[] remaining_args)
	{
		if (remaining_args.length < 2)
			return "Missing FILE. Usage: " + this.get_app_name() + " [OPTIONS] FILE\n";
		return null;
	}

	private Markdown.Document.Document doc_from_markdown(string input)
	{
		var renderer = new Markdown.Document.Render();
		renderer.start();
		renderer.add(input);
		renderer.flush();
		return renderer.document;
	}

	private Markdown.Document.Document doc_from_json(string input) throws Error
	{
		var parser = new Json.Parser();
		parser.load_from_data(input, -1);
		var root = parser.get_root();
		var doc = Json.gobject_deserialize(typeof(Markdown.Document.Document), root) as Markdown.Document.Document;
		if (doc == null)
			throw new GLib.IOError.INVALID_DATA("JSON root is not a document (node_type DOCUMENT)");
		return doc;
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] remaining_args) throws Error
	{
		string output_format = (remaining_args.length >= 3)
			? remaining_args[2].down()
			: (opt_output_format ?? "json").down();
		string path = remaining_args[1];
		bool input_is_json = path.has_suffix(".json");

		uint8[] contents;
		FileUtils.get_data(path, out contents);
		string input = (string)contents;

		Markdown.Document.Document doc;
		if (input_is_json)
			doc = doc_from_json(input);
		else
			doc = doc_from_markdown(input);

		if (output_format == "markdown") {
			command_line.print(doc.to_markdown());
		} else {
			var root = Json.gobject_serialize(doc);
			var gen = new Json.Generator();
			gen.set_root(root);
			gen.pretty = true;
			command_line.print(gen.to_data(null));
		}
	}
}

int main(string[] args)
{
	// Ensure stdout uses UTF-8 so non-ASCII (e.g. en-dash, ellipsis) is preserved when printing
	Intl.setlocale(LocaleCategory.ALL, "C.UTF-8");
	var app = new OcMarkdownDocTest();
	return app.run(args);
}
