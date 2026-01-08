/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
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

class TestFetchApp : TestAppBase
{
	protected static string? opt_format = null;
	
	protected const string help = """
Usage: {ARG} [OPTIONS] <url> [format]

Fetch content from a URL and display it.

Arguments:
  url                    URL to fetch (required)
  format                 Output format: markdown, raw, or base64 (default: markdown)

Options:
  -d, --debug          Enable debug output
  --format=FORMAT     Output format: markdown, raw, or base64 (default: markdown)

Examples:
  {ARG} https://example.com
  {ARG} https://example.com markdown
  {ARG} --format=raw https://example.com
  {ARG} https://example.com base64
""";
	
	protected const OptionEntry[] local_options = {
		{ "format", 0, 0, OptionArg.STRING, ref opt_format, "Output format: markdown, raw, or base64 (default: markdown)", "FORMAT" },
		{ null }
	};
	
	protected override OptionEntry[] get_options()
	{
		// Only include debug from base_options, skip url/api-key/model since we don't need Ollama connection
		var options = new OptionEntry[3];  // debug + format + null terminator
		options[0] = base_options[0];  // debug option
		options[1] = local_options[0];  // format option
		options[2] = { null };  // null terminator
		return options;
	}
	
	public TestFetchApp()
	{
		base("org.roojs.oc-test-fetch");
	}
	
	// Override load_config to return empty config (we don't need to load from file)
	public override OLLMchat.Settings.Config2 load_config()
	{
		// Return empty config instead of loading from file
		// This avoids deserialization issues since we create our own dummy client
		return new OLLMchat.Settings.Config2();
	}
	
	protected override string? validate_args(string[] args)
	{
		// Reset static option variables at start of each command line invocation
		opt_format = null;
		
		string url = "";
		string format_arg = "";
		
		if (args.length > 1) {
			url = args[1];
		}
		if (args.length > 2) {
			format_arg = args[2];
		}
		
		if (url == "") {
			return help.replace("{ARG}", args[0]);
		}
		
		// Validate format if provided
		if (format_arg != "" && 
		    format_arg != "markdown" && format_arg != "raw" && format_arg != "base64") {
			return "Error: Format must be 'markdown', 'raw', or 'base64'\n";
		}
		
		if (opt_format != null && opt_format != "" &&
		    opt_format != "markdown" && opt_format != "raw" && opt_format != "base64") {
			return "Error: Format must be 'markdown', 'raw', or 'base64'\n";
		}
		
		return null;
	}
	
	protected override string get_app_name()
	{
		return "Web Fetch Test Tool";
	}
	
	protected override async void run_test(ApplicationCommandLine command_line) throws Error
	{
		string[] args = command_line.get_arguments();
		string url = args.length > 1 ? args[1] : "";
		string format_arg = args.length > 2 ? args[2] : "";
		
		if (url == "") {
			throw new GLib.IOError.NOT_FOUND("URL is required");
		}
		
		// Determine format: command-line option takes precedence, then positional argument, then default
		string format = "markdown";
		if (opt_format != null && opt_format != "") {
			format = opt_format;
		} else if (format_arg != "") {
			format = format_arg;
		}
		
		// Create minimal client with Dummy permission provider (auto-approves)
		// We don't actually need a real connection for this test tool
		var connection = new OLLMchat.Settings.Connection() {
			name = "Test",
			url = "http://localhost:11434/api",
			api_key = "",
			is_default = true
		};
		
		// Create a dummy Config2 to avoid null config errors
		var dummy_config = new OLLMchat.Settings.Config2();
		
		var client = new OLLMchat.Client(connection);
		
		// Create WebFetchTool
		var tool = new OLLMtools.WebFetchTool(client);
		
		// Create RequestWebFetch manually
		var request = new OLLMtools.RequestWebFetch();
		request.tool = tool;
		request.url = url;
		request.format = format;
		
		// Create a dummy agent handler for testing
		// Create dummy manager and session
		var dummy_manager = new OLLMchat.History.Manager(this);
		// Verify model usage (may fail for test setups, but that's okay)
		try {
			yield dummy_manager.ensure_model_usage();
		} catch (GLib.Error e) {
			GLib.warning("Test setup: model verification failed (this may be expected): %s", e.message);
		}
		var dummy_session = new OLLMchat.History.EmptySession(dummy_manager);
		
		// Create dummy agent and handler
		var dummy_agent = new OLLMchat.Prompt.JustAsk();
		var dummy_handler = new OLLMchat.Prompt.AgentHandler(dummy_agent, dummy_session);
		
		// Set permission provider on chat
		dummy_handler.chat.permission_provider = new OLLMchat.ChatPermission.Dummy();
		
		// Set agent on request
		request.agent = dummy_handler;
		
		// Execute the request (Dummy provider will auto-approve)
		// Output result
		stdout.printf("%s", yield request.execute());
	}
}

int main(string[] args)
{
	var app = new TestFetchApp();
	return app.run(args);
}
