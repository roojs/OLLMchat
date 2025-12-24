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

class VectorSearchApp : Application
{
	private static bool opt_debug = false;
	private static bool opt_json = false;
	private static string? opt_language = null;
	private static string? opt_element_type = null;
	private static int opt_max_results = 10;
	private static int opt_max_snippet_lines = 10;
	
	private string data_dir;
	private string db_path;
	private string vector_db_path;
	
	const GLib.OptionEntry[] options = {
		{ "debug", 'd', 0, OptionArg.NONE, ref opt_debug, "Enable debug output", null },
		{ "json", 'j', 0, OptionArg.NONE, ref opt_json, "Output results as JSON", null },
		{ "language", 'l', 0, OptionArg.STRING, ref opt_language, "Filter by language (e.g., vala, python)", "LANG" },
		{ "element-type", 'e', 0, OptionArg.STRING, ref opt_element_type, "Filter by element type (e.g., class, method, function, property, struct, interface, enum, constructor, field, delegate, signal, constant)", "TYPE" },
		{ "max-results", 'n', 0, OptionArg.INT, ref opt_max_results, "Maximum number of results (default: 10)", "N" },
		{ "max-snippet-lines", 's', 0, OptionArg.INT, ref opt_max_snippet_lines, "Maximum lines of code snippet to display (default: 10, -1 for no limit)", "N" },
		{ null }
	};
	
	public VectorSearchApp()
	{
		Object(
			application_id: "org.roojs.oc-vector-search",
			flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE
		);
	}
	
	protected override int command_line(ApplicationCommandLine command_line)
	{
		// Reset static option variables at start of each command line invocation
		opt_debug = false;
		opt_json = false;
		opt_language = null;
		opt_element_type = null;
		opt_max_results = 10;
		opt_max_snippet_lines = 10;
		
		string[] args = command_line.get_arguments();
		var opt_context = new OptionContext("Code Vector Search");
		opt_context.set_help_enabled(true);
		opt_context.add_main_entries(options, null);
		
		try {
			unowned string[] unowned_args = args;
			opt_context.parse(ref unowned_args);
		} catch (OptionError e) {
			command_line.printerr("error: %s\n", e.message);
			command_line.printerr("Run '%s --help' to see a full list of available command line options.\n", args[0]);
			return 1;
		}
		
		if (opt_debug) {
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				var timestamp = (new DateTime.now_local()).format("%H:%M:%S.%f");
				var level_str = lvl.to_string();
				command_line.printerr("%s [%s] %s\n", timestamp, level_str, msg);
			});
		}
		
		// Build paths at start
		this.data_dir = GLib.Path.build_filename(
			GLib.Environment.get_home_dir(), ".local", "share", "ollmchat");
		this.db_path = GLib.Path.build_filename(this.data_dir, "files.sqlite");
		this.vector_db_path = GLib.Path.build_filename(this.data_dir, "codedb.faiss.vectors");
		
		string? folder_path = null;
		string? query = null;
		
		if (args.length > 1) {
			folder_path = args[1];
		}
		if (args.length > 2) {
			query = args[2];
		}
		
		if (folder_path == null || folder_path == "" || query == null || query == "") {
			var usage = @"Usage: $(args[0]) [OPTIONS] <folder> <query>

Search indexed codebase using semantic vector search.

Arguments:
  folder                 Folder path to search within (required)
  query                  Search query text (required)

Options:
  -d, --debug          Enable debug output
  -j, --json           Output results as JSON
  -l, --language=LANG Filter by language (e.g., vala, python)
  -e, --element-type=TYPE Filter by element type (e.g., class, method, function, property, struct, interface, enum, constructor, field, delegate, signal, constant)
  -n, --max-results=N  Maximum number of results (default: 10)
  -s, --max-snippet-lines=N Maximum lines of code snippet to display (default: 10, -1 for no limit)

Examples:
  $(args[0]) libocvector \"database connection\"
  $(args[0]) --json libocvector \"async function\"
  $(args[0]) --language=vala --element-type=method libocvector \"parse\"
  $(args[0]) --max-results=20 libocvector \"search\"
  $(args[0]) --max-snippet-lines=5 libocvector \"search\"
";
			command_line.printerr("%s", usage);
			return 1;
		}
		
		// Hold the application to keep main loop running during async operations
		this.hold();
		
		this.run_search.begin(folder_path, query, (obj, res) => {
			try {
				this.run_search.end(res);
			} catch (Error e) {
				command_line.printerr("Error: %s\n", e.message);
			} finally {
				// Release hold and quit when done
				this.release();
				this.quit();
			}
		});
		
		return 0;
	}
	
	private async void run_search(string folder_path, string query) throws Error
	{
		stdout.printf("=== Code Vector Search ===\n\n");
		
		var data_dir_file = GLib.File.new_for_path(this.data_dir);
		if (!data_dir_file.query_exists()) {
			throw new GLib.IOError.NOT_FOUND("Data directory not found: " + this.data_dir);
		}
		
		var sql_db = new SQ.Database(this.db_path, false);
		GLib.debug("Using database: %s", this.db_path);
		
		var manager = new OLLMfiles.ProjectManager(sql_db);
		
		// Load embed config
		var embed_config_path = GLib.Path.build_filename(
			GLib.Environment.get_home_dir(), ".config", "ollmchat", "embed.json");
		
		if (!GLib.FileUtils.test(embed_config_path, GLib.FileTest.EXISTS)) {
			throw new GLib.IOError.NOT_FOUND("Embed config not found at " + embed_config_path);
		}
		
		GLib.debug("Loading embed config from: %s", embed_config_path);
		var parser = new Json.Parser();
		parser.load_from_file(embed_config_path);
		var obj = parser.get_root().get_object();
	 
		var embed_client = new OLLMchat.Client(new OLLMchat.Config() {
			url = obj.get_string_member("url"),
			model = obj.get_string_member("model"),
			api_key = obj.get_string_member("api-key")
		});
		embed_client.options = new OLLMchat.Call.Options() {
			temperature = 0.0,
			num_ctx = 2048
		};
		
		// Get dimension and create vector database
		var dimension = yield OLLMvector.Database.get_embedding_dimension(embed_client);
		var vector_db = new OLLMvector.Database(embed_client, this.vector_db_path, dimension);
		
		GLib.debug("Using vector database: %s", this.vector_db_path);
		
		// Look up folder from database
		var file = GLib.File.new_for_path(folder_path);
		if (!file.query_exists()) {
			throw new GLib.IOError.NOT_FOUND("Folder not found: " + folder_path);
		}
		
		var abs_path = file.get_path();
		if (abs_path == null) {
			throw new GLib.IOError.FAILED("Failed to get absolute path for: " + folder_path);
		}
		
		var results_list = new Gee.ArrayList<OLLMfiles.FileBase>();
		var query_obj = OLLMfiles.FileBase.query(sql_db, manager);
		var stmt = query_obj.selectPrepare(
				"SELECT " + string.joinv(",", query_obj.getColsExcept(null)) +
					 " FROM filebase WHERE path = $path");
		stmt.bind_text(stmt.bind_parameter_index("$path"), abs_path);
		query_obj.selectExecute(stmt, results_list);
		
		OLLMfiles.Folder? search_folder = null;
		if (results_list.size > 0 && results_list[0] is OLLMfiles.Folder) {
			search_folder = (OLLMfiles.Folder)results_list[0];
		} else {
			throw new GLib.IOError.NOT_FOUND("Folder not found in database: " + abs_path);
		}
		
		// Load files into folder's project_files
		yield search_folder.load_files_from_db();
		
		// Get all file IDs from project_files (optionally filtered by language)
		var language_filter = opt_language != null ? opt_language : "";
		var file_ids = search_folder.project_files.get_ids(language_filter);
		
		if (file_ids.size == 0) {
			if (language_filter != "") {
				throw new GLib.IOError.FAILED("No files found in folder matching language filter: " + language_filter);
			} else {
				throw new GLib.IOError.FAILED("No files found in folder");
			}
		}
		
		// Build filtered vector IDs
		var filtered_vector_ids = new Gee.ArrayList<int>();
		
		// Build SQL query string
		var file_id_list = string.joinv(",", file_ids.to_array());
		var sql = "SELECT DISTINCT vector_id FROM vector_metadata WHERE file_id IN (" + file_id_list + ")";
		
		if (opt_element_type != null) {
			sql = sql + " AND element_type = $element_type";
		}
		
		GLib.debug("Filter SQL: %s", sql);
		
		var vector_query = OLLMvector.VectorMetadata.query(sql_db);
		var vector_stmt = vector_query.selectPrepare(sql);
		
		if (opt_element_type != null) {
			vector_stmt.bind_text(
				vector_stmt.bind_parameter_index("$element_type"), opt_element_type);
		}
		
		foreach (var vector_id_str in vector_query.fetchAllString(vector_stmt)) {
			filtered_vector_ids.add((int)int64.parse(vector_id_str));
		}
		
		GLib.debug("Filtered to %lld vector IDs", filtered_vector_ids.size);
		
		// Create search instance
		var search = new OLLMvector.Search.Search(
			vector_db,
			sql_db,
			embed_client,
			search_folder,
			query,
			(uint64)opt_max_results,
			filtered_vector_ids
		);
		
		// Execute search
		stdout.printf("Folder: %s\n", search_folder.path);
		stdout.printf("Query: %s\n", query);
		if (opt_language != null || opt_element_type != null) {
			var filters = new Gee.ArrayList<string>();
			if (opt_language != null) {
				filters.add("language: " + opt_language);
			}
			if (opt_element_type != null) {
				filters.add("element-type: " + opt_element_type);
			}
			stdout.printf("Filters: %s\n", string.joinv(", ", filters.to_array()));
		}
		stdout.printf("Max results: %d\n\n", opt_max_results);
		
		var results = yield search.execute();
		
		if (results.size == 0) {
			stdout.printf("No results found.\n");
			return;
		}
		
		// Output results
		if (opt_json) {
			this.output_json(results);
		} else {
			this.output_text(results);
		}
	}
	
	private void output_text(Gee.ArrayList<OLLMvector.Search.SearchResult> results)
	{
		stdout.printf("Found %d result(s):\n\n", results.size);
		
		for (int i = 0; i < results.size; i++) {
			var rank = i + 1;
			
			// Convert distance to score: 1.0 - distance (higher score = better match)
			var score = 1.0f - results[i].distance;
			stdout.printf("--- Result %d (score: %.4f) ---\n", rank, score);
			stdout.printf("File: %s\n", results[i].file().path);
			stdout.printf("Element: %s (%s)\n", results[i].metadata.element_name, results[i].metadata.element_type);
			stdout.printf("Lines: %d-%d\n", results[i].metadata.start_line, results[i].metadata.end_line);	
			stdout.printf("Description: %s\n", results[i].metadata.description);
			
			
			var snippet = results[i].code_snippet(opt_max_snippet_lines);
			
			// Get language from file object for markdown code block
			var file = results[i].file();
			var language = file.language != null && file.language != "" ? file.language : "";
			
			if (language != "") {
				stdout.printf("```%s\n%s\n```\n", language, snippet);
			} else {
				stdout.printf("```\n%s\n```\n", snippet);
			}
			
			// Check if snippet was truncated by comparing metadata line range to max_lines
			if (opt_max_snippet_lines != -1) {
				var original_line_count = results[i].metadata.end_line - results[i].metadata.start_line + 1;
				if (original_line_count > opt_max_snippet_lines) {
					stdout.printf("... (%d more lines)\n", original_line_count - opt_max_snippet_lines);
				}
			}
			
			
			stdout.printf("\n");
		}
	}
	
	private void output_json(Gee.ArrayList<OLLMvector.Search.SearchResult> results)
	{
		var json_array = new Json.Array();
		
		foreach (var result in results) {
			var json_node = Json.gobject_serialize(result);
			json_array.add_element(json_node);
		}
		
		var json_root = new Json.Node(Json.NodeType.ARRAY);
		json_root.set_array(json_array);
		
		var generator = new Json.Generator();
		generator.set_root(json_root);
		generator.set_pretty(true);
		generator.set_indent(2);
		
		var json_string = generator.to_data(null);
		stdout.printf("%s\n", json_string);
	}
}

int main(string[] args)
{
	var app = new VectorSearchApp();
	return app.run(args);
}

