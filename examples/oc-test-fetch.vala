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

int main(string[] args)
{
	if (args.length < 2) {
		stderr.printf("Usage: %s <url> [format]\n", args[0]);
		stderr.printf("\n");
		stderr.printf("Fetch content from a URL and display it.\n");
		stderr.printf("\n");
		stderr.printf("Arguments:\n");
		stderr.printf("  url      URL to fetch (required)\n");
		stderr.printf("  format   Output format: markdown, raw, or base64 (default: markdown)\n");
		stderr.printf("\n");
		stderr.printf("Examples:\n");
		stderr.printf("  %s https://example.com\n", args[0]);
		stderr.printf("  %s https://example.com markdown\n", args[0]);
		stderr.printf("  %s https://example.com raw\n", args[0]);
		return 1;
	}
	
	var url = args[1];
	var format = "markdown";
	if (args.length > 2) {
		format = args[2];
	}
	
	// Validate format
	if (format != "markdown" && format != "raw" && format != "base64") {
		stderr.printf("Error: Format must be 'markdown', 'raw', or 'base64'\n");
		return 1;
	}
	
	// Create minimal client with Dummy permission provider (auto-approves)
	var connection = new OLLMchat.Settings.Connection() {
		name = "Test",
		url = "http://localhost:11434/api",
		api_key = "",
		is_default = true
	};
	
	var client = new OLLMchat.Client(connection);
	client.permission_provider = new OLLMchat.ChatPermission.Dummy();
	
	// Create WebFetchTool
	var tool = new OLLMchat.Tools.WebFetchTool(client);
	
	// Create RequestWebFetch manually
	var request = new OLLMchat.Tools.RequestWebFetch();
	request.tool = tool;
	request.url = url;
	request.format = format;
	
	// Create a dummy chat call context (needed for execute)
	var dummy_chat_call = new OLLMchat.Call.Chat(client);
	request.chat_call = dummy_chat_call;
	
	// Execute the request (Dummy provider will auto-approve)
	var main_loop = new GLib.MainLoop();
	int exit_code = 0;
	
	request.execute.begin((obj, res) => {
		try {
			var output = request.execute.end(res);
			stdout.printf("%s", output);
		} catch (GLib.Error e) {
			stderr.printf("Error: %s\n", e.message);
			exit_code = 1;
		}
		main_loop.quit();
	});
	
	main_loop.run();
	return exit_code;
}

