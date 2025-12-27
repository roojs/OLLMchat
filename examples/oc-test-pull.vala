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

class TestPullApp : TestAppBase
{
	public TestPullApp()
	{
		base("org.roojs.oc-test-pull");
	}
	
	protected override string get_app_name()
	{
		return "OLLMchat Test Pull Tool";
	}
	
	protected override string? validate_args(string[] args)
	{
		if (opt_model == null || opt_model == "") {
			return @"Usage: $(args[0]) [OPTIONS] --model=MODEL

Test tool for ollama pull with streaming enabled.

Options:
  -d, --debug          Enable debug output
  --url=URL           Ollama server URL (required if config not found)
  --api-key=KEY       API key (optional)
  -m, --model=MODEL    Model name to pull (required)

Examples:
  $(args[0]) --model llama2
  $(args[0]) --debug --url http://localhost:11434/api --model llama2
";
		}
		return null;
	}
	
	protected override async void run_test(ApplicationCommandLine command_line) throws Error
	{
		var client = yield this.setup_client(command_line);
		
		stdout.printf("Pulling model: %s\n", opt_model);
		stdout.printf("Streaming progress updates:\n\n");
		
		// Create Pull call
		var pull_call = new OLLMchat.Call.Pull(client, opt_model) {
			stream = true
		};
		
		// Connect to progress signal to display chunks
		pull_call.progress_chunk.connect((chunk) => {
			// Parse and display progress information
			var generator = new Json.Generator();
			var chunk_node = new Json.Node(Json.NodeType.OBJECT);
			chunk_node.set_object(chunk);
			generator.set_root(chunk_node);
			var json_str = generator.to_data(null);
			
			// Extract key fields for display
			string status = "";
			if (chunk.has_member("status")) {
				status = chunk.get_string_member("status");
			}
			
			string digest = "";
			if (chunk.has_member("digest")) {
				digest = chunk.get_string_member("digest");
			}
			
			int64 completed = -1;
			if (chunk.has_member("completed")) {
				completed = chunk.get_int_member("completed");
			}
			
			int64 total = -1;
			if (chunk.has_member("total")) {
				total = chunk.get_int_member("total");
			}
			
			// Display progress information
			stdout.printf("Status: %s", status);
			if (digest != "") {
				stdout.printf(" | Digest: %s", digest);
			}
			if (completed >= 0 && total >= 0) {
				double percent = ((double)completed / (double)total) * 100.0;
				stdout.printf(" | Progress: %lld/%lld (%.1f%%)", completed, total, percent);
			}
			stdout.printf("\n");
			
			// Also print full JSON for debugging
			if (opt_debug) {
				stdout.printf("  Full JSON: %s\n", json_str);
			}
		});
		
		// Execute pull
		try {
			yield pull_call.exec_pull();
			
			stdout.printf("\nPull completed successfully!\n");
		} catch (GLib.IOError e) {
			if (e.code == GLib.IOError.CANCELLED) {
				stdout.printf("\nPull cancelled by user.\n");
			} else {
				throw e;
			}
		}
	}
}

int main(string[] args)
{
	var app = new TestPullApp();
	return app.run(args);
}

