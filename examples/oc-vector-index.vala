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
	// Set up debug handler
	GLib.Log.set_default_handler((dom, lvl, msg) => {
		stderr.printf("%s: %s : %s\n", (new DateTime.now_local()).format("%H:%M:%S.%f"), lvl.to_string(), msg);
	});

	if (args.length < 2) {
		stderr.printf("Usage: %s <test_text1> [test_text2] ...\n", args[0]);
		stderr.printf("Tests FAISS indexing and search with provided text documents.\n");
		return 1;
	}

	var main_loop = new MainLoop();

	run_test.begin(args, (obj, res) => {
		try {
			run_test.end(res);
		} catch (Error e) {
			stderr.printf("Error: %s\n", e.message);
			Posix.exit(1);
		}
		main_loop.quit();
	});

	main_loop.run();

	return 0;
}

async void run_test(string[] args) throws Error
{
	stdout.printf("=== FAISS Test Tool ===\n\n");

	// Load config
	var config_path = Path.build_filename(
		GLib.Environment.get_home_dir(), ".config", "ollmchat", "embed.json"
	);
	
	OLLMchat.Config config;
	var parser = new Json.Parser();
	parser.load_from_file(config_path);
	var obj = parser.get_root().get_object();
	config = new OLLMchat.Config() {
		url = obj.get_string_member("url"),
		model = obj.get_string_member("model"),
		api_key = obj.get_string_member("api-key")
	};


	var client = new OLLMchat.Client(config);
	stdout.printf("Created OLLMchat client (model: %s)\n", config.model);

	// Create database
	var db = new OLLMvector.Database(client);
	stdout.printf("Created vector database\n\n");

	// Extract test texts from args (skip program name)
	var test_texts = new string[args.length - 1];
	for (int i = 1; i < args.length; i++) {
		test_texts[i - 1] = args[i];
	}

	stdout.printf("Adding %u documents to index...\n", test_texts.length);
	yield db.add_documents(test_texts);
	stdout.printf("✓ Documents added successfully\n\n");

	// Test search
	stdout.printf("Testing search with query: \"%s\"\n", test_texts[0]);
	var results = yield db.search(test_texts[0], 3);
	stdout.printf("✓ Search completed, found %u results:\n", results.length);
	
	for (int i = 0; i < results.length; i++) {
		var result = results[i];
		stdout.printf("  %d. Document ID: %lld, Score: %.4f\n", 
			i + 1, 
			result.search_result.document_id,
			result.search_result.similarity_score
		);
	}

	// TODO: Test save/load once C API wrapper is available
	// For now, skip save/load test as it requires C API wrapper compilation
	stdout.printf("\nNote: Save/load test skipped (C API wrapper functions not in static library)\n");

	stdout.printf("\n=== All tests passed! ===\n");
}
