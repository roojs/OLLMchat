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
	// Set up debug handler with nice formatting
	GLib.Log.set_default_handler((dom, lvl, msg) => {
		var timestamp = (new DateTime.now_local()).format("%H:%M:%S.%f");
		var level_str = lvl.to_string();
		stderr.printf("%s [%s] %s\n", timestamp, level_str, msg);
	});

	if (args.length < 2) {
		stderr.printf("Usage: %s <file_path>\n", args[0]);
		stderr.printf("Tests tree-sitter parsing with a single file.\n");
		stderr.printf("\n");
		stderr.printf("Example:\n");
		stderr.printf("  %s libocvector/Database.vala\n", args[0]);
		return 1;
	}

	var file_path = args[1];

	var main_loop = new MainLoop();

	run_test.begin(file_path, (obj, res) => {
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

async void run_test(string file_path) throws Error
{
	stdout.printf("=== Code Indexer Test Tool ===\n\n");
	
	// Check if file exists
	var file = GLib.File.new_for_path(file_path);
	if (!file.query_exists()) {
		throw new GLib.IOError.NOT_FOUND("File not found: " + file_path);
	}
	
	// Get absolute path
	var abs_path = file.get_path();
	if (abs_path == null) {
		throw new GLib.IOError.FAILED("Failed to get absolute path for: " + file_path);
	}
	
	stdout.printf("File: %s\n\n", abs_path);
	
	// Create temporary database at /tmp/files.sqlite
	var db_path = "/tmp/files.sqlite";
	var db_file = GLib.File.new_for_path(db_path);
	if (db_file.query_exists()) {
		try {
			db_file.delete(null);
			GLib.debug("Deleted existing database: %s", db_path);
		} catch (GLib.Error e) {
			GLib.warning("Failed to delete existing database: %s", e.message);
		}
	}
	
	var sql_db = new SQ.Database(db_path, false);
	GLib.debug("Created temporary database: %s", db_path);
	
	// Create ProjectManager and File object
	var manager = new OLLMfiles.ProjectManager(sql_db);
	manager.buffer_provider = new OLLMcoder.Files.BufferProvider();
	manager.git_provider = new OLLMcoder.Files.GitProvider();
	
	// Create File object from path
	var file_info = file.query_info("standard::*", GLib.FileQueryInfoFlags.NONE, null);
	var ollm_file = new OLLMfiles.File(manager);
	ollm_file.path = abs_path;
	
	// Set file properties from FileInfo
	var mod_time = file_info.get_modification_date_time();
	if (mod_time != null) {
		ollm_file.last_modified = mod_time.to_unix();
	}
	
	var content_type = file_info.get_content_type();
	ollm_file.is_text = content_type != null && content_type != "" && content_type.has_prefix("text/");
	
	// Detect language using buffer provider
	var detected_lang = manager.buffer_provider.detect_language(ollm_file);
	if (detected_lang != null && detected_lang != "") {
		ollm_file.language = detected_lang;
	}
	
	// Save file to database
	ollm_file.saveToDB(sql_db, null, false);
	
	stdout.printf("Created file object (ID: %lld, Language: %s)\n", ollm_file.id, ollm_file.language);
	stdout.printf("\n");
	
	// Parse file using Tree
	stdout.printf("=== Running Tree Parser ===\n");
	GLib.debug("Parsing file with tree-sitter...");
	
	var tree = new OLLMvector.Indexing.Tree(ollm_file);
	try {
		yield tree.parse();
		stdout.printf("✓ Parsing completed\n");
		stdout.printf("  Found %d elements\n\n", tree.elements.size);
		
		// Show elements found
		stdout.printf("=== Elements Found ===\n");
		foreach (var element in tree.elements) {
			// Skip showing name if it looks like a code snippet (contains newlines or is too long)
			var display_name = element.element_name;
			if (display_name.contains("\n") || display_name.length > 80) {
				display_name = "[code snippet - name extraction failed]";
			}
			stdout.printf("  - %s: %s (lines %d-%d)", 
				element.element_type, display_name, element.start_line, element.end_line);
			// Always show signature if available
			if (element.signature != null && element.signature != "" && element.signature.length < 200) {
				stdout.printf("\n    Signature: %s", element.signature);
			}
			if (element.codedoc_start > 0 && element.codedoc_end > 0) {
				stdout.printf("\n    Documentation: lines %d-%d", element.codedoc_start, element.codedoc_end);
			}
			stdout.printf("\n");
		}
		stdout.printf("\n");
	} catch (GLib.Error e) {
		throw new GLib.IOError.FAILED("Tree parsing failed: " + e.message);
	}
	
	/* COMMENTED OUT FOR NOW
	// Load analysis config from ~/.config/ollmchat/analysis.json
	var analysis_config_path = Path.build_filename(
		GLib.Environment.get_home_dir(), ".config", "ollmchat", "analysis.json"
	);
	
	if (!GLib.FileUtils.test(analysis_config_path, GLib.FileTest.EXISTS)) {
		throw new GLib.IOError.NOT_FOUND("Analysis config not found at " + analysis_config_path);
	}
	
	GLib.debug("Loading analysis config from: %s", analysis_config_path);
	var parser = new Json.Parser();
	parser.load_from_file(analysis_config_path);
	var obj = parser.get_root().get_object();
	 
	var analysis_config = new OLLMchat.Config() {
		url = obj.get_string_member("url"),
		model = obj.get_string_member("model"),
		api_key = obj.get_string_member("api-key")
	};
	
	// Load embed config from ~/.config/ollmchat/embed.json
	var embed_config_path = Path.build_filename(
		GLib.Environment.get_home_dir(), ".config", "ollmchat", "embed.json"
	);
	
	if (!GLib.FileUtils.test(embed_config_path, GLib.FileTest.EXISTS)) {
		throw new GLib.IOError.NOT_FOUND("Embed config not found at " + embed_config_path);
	}
	
	GLib.debug("Loading embed config from: %s", embed_config_path);
	var parser2 = new Json.Parser();
	parser2.load_from_file(embed_config_path);
	var obj2 = parser2.get_root().get_object();
 
	var embed_config = new OLLMchat.Config() {
		url = obj2.get_string_member("url"),
		model = obj2.get_string_member("model"),
		api_key =   obj2.get_string_member("api-key")
	};
	
	// Create clients with sensible temperature and context window settings
	var analysis_client = new OLLMchat.Client(analysis_config);
	analysis_client.options.temperature = 0.0;  // Deterministic for structured outputs
	analysis_client.options.num_ctx = 65536;     // Reasonable context window
	analysis_client.options.top_k = 1405;     // Reasonable context window
	analysis_client.options.top_p = 0.9;     // Reasonable context window
	analysis_client.options.min_p= 0.1;     // Reasonable context window
	
	var embed_client = new OLLMchat.Client(embed_config);
	embed_client.options.temperature = 0.0;     // Not used for embeddings, but set anyway
	embed_client.options.num_ctx = 2048;        // Smaller context for embeddings
	
	stdout.printf("Analysis Model: %s\n", analysis_config.model);
	stdout.printf("Embed Model: %s\n", embed_config.model);
	stdout.printf("\n");
	
	// Run analysis
	stdout.printf("=== Running Analysis ===\n");
	GLib.debug("Sending file to LLM for analysis...");
	
	var analysis = new OLLMvector.Indexing.Analysis(analysis_client);
	OLLMvector.CodeFile code_file;
	try {
		code_file = yield analysis.analyze_file(ollm_file);
		stdout.printf("✓ Analysis completed\n");
		stdout.printf("  Found %d elements\n", code_file.elements.size);
		
		// Show elements found
		foreach (var element in code_file.elements) {
			stdout.printf("    - %s: %s (lines %d-%d)\n", 
				element.property_type, element.name, element.start_line, element.end_line);
		}
		stdout.printf("\n");
	} catch (GLib.Error e) {
		throw new GLib.IOError.FAILED("Analysis failed: " + e.message);
	}
	
	// Run vectorization
	stdout.printf("=== Running Vectorization ===\n");
	GLib.debug("Generating embeddings and storing in FAISS...");
	
	var vector_db = new OLLMvector.Database(embed_client);
	var vector_builder = new OLLMvector.Indexing.VectorBuilder(embed_client, vector_db, sql_db);
	
	try {
		yield vector_builder.process_file(code_file, ollm_file);
		stdout.printf("✓ Vectorization completed\n");
		stdout.printf("  Stored %llu vectors in FAISS index\n", vector_db.vector_count);
		stdout.printf("  Vector dimension: %llu\n", vector_db.dimension);
		stdout.printf("\n");
	} catch (GLib.Error e) {
		throw new GLib.IOError.FAILED("Vectorization failed: " + e.message);
	}
	
	// Perform search
	stdout.printf("=== Running Search ===\n");
	GLib.debug("Searching for: %s", search_query);
	
	try {
		var results = yield vector_db.search(search_query, 5);
		stdout.printf("✓ Search completed\n");
		stdout.printf("  Found %d results\n\n", results.length);
		
		// Display results nicely
		for (int i = 0; i < results.length; i++) {
			var result = results[i];
			var metadata = OLLMvector.VectorMetadata.lookup(sql_db, "vector_id", result.search_result.document_id);
			
			stdout.printf("Result %d (Score: %.4f)\n", i + 1, result.search_result.similarity_score);
			if (metadata != null) {
				stdout.printf("  Element: %s %s\n", metadata.element_type, metadata.element_name);
				stdout.printf("  File ID: %lld\n", metadata.file_id);
				stdout.printf("  Lines: %d-%d\n", metadata.start_line, metadata.end_line);
				
				// Lookup file path from file_id
				var results_list = new Gee.ArrayList<OLLMfiles.FileBase>();
				OLLMfiles.FileBase.query(sql_db, manager).select(
					"WHERE id = " + metadata.file_id.to_string(), results_list);
				if (results_list.size > 0) {
					var file_lookup = results_list[0];
					stdout.printf("  File: %s\n", file_lookup.path);
				}
			} else {
				stdout.printf("  Vector ID: %lld (metadata not found)\n", result.search_result.document_id);
			}
			stdout.printf("\n");
		}
	} catch (GLib.Error e) {
		throw new GLib.IOError.FAILED("Search failed: " + e.message);
	}
	*/
	
	stdout.printf("=== Test Complete ===\n");
	stdout.printf("Database saved at: %s\n", db_path);
}
