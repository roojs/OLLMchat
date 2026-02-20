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

class VectorSearchApp : VectorAppBase
{
	protected static bool opt_json = false;
	protected static string? opt_show_info = null;
	protected static string? opt_language = null;
	protected static string? opt_element_type = null;
	protected static string? opt_category = null;
	protected static int opt_max_results = 3;
	protected static int opt_max_snippet_lines = 10;
	protected static string? opt_embed_model = null;
	
	private string db_path;
	private string vector_db_path;
	
	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <folder> [query]

Search indexed codebase using semantic vector search.

Arguments:
  folder                 Folder path to search within (required)
  query                  Search query text (required unless --show-info is used)

Options:
  --show-info=FILE       List all vector metadata for the given file (path relative to folder or absolute)

Examples:
  {ARG} libocvector "database connection"
  {ARG} --json libocvector "async function"
  {ARG} --show-info README.md libocvector
  {ARG} --show-info docs/guide.md libocvector
  {ARG} --language=vala --element-type=method libocvector "parse"
  {ARG} --category=documentation libocvector "packaging"
  {ARG} --max-results=20 libocvector "search"
  {ARG} --max-snippet-lines=5 libocvector "search"
"""; }
	
	protected const OptionEntry[] local_options = {
		{ "json", 'j', 0, OptionArg.NONE, ref opt_json, "Output results as JSON", null },
		{ "show-info", 0, 0, OptionArg.STRING, ref opt_show_info, "List vector metadata for a file", "FILE" },
		{ "language", 'l', 0, OptionArg.STRING, ref opt_language, "Filter by language (e.g., vala, python)", "LANG" },
		{ "element-type", 'e', 0, OptionArg.STRING, ref opt_element_type, "Filter by element type (e.g., class, method, function, property, struct, interface, enum, constructor, field, delegate, signal, constant, file, document, section)", "TYPE" },
		{ "category", 'c', 0, OptionArg.STRING, ref opt_category, "Filter docs by category (plan, documentation, rule, configuration, data, license, changelog, other)", "CATEGORY" },
		{ "max-results", 'n', 0, OptionArg.INT, ref opt_max_results, "Maximum number of results (default: 3)", "N" },
		{ "max-snippet-lines", 's', 0, OptionArg.INT, ref opt_max_snippet_lines, "Maximum lines of code snippet to display (default: 10, -1 for no limit)", "N" },
		{ "embed-model", 0, 0, OptionArg.STRING, ref opt_embed_model, "Embedding model name (default: bge-m3)", "MODEL" },
		{ null }
	};
	
	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		opt_context.add_main_entries(base_options, null);
		
		var app_group = new OptionGroup("oc-vector-search", "Code Vector Search Options", "Show Code Vector Search options");
		app_group.add_entries(local_options);
		opt_context.add_group(app_group);
		
		return opt_context;
	}
	
	public VectorSearchApp()
	{
		base("org.roojs.oc-vector-search");
	}
	
	public override OLLMchat.Settings.Config2 load_config()
	{
		// Register all tool config types before loading config
		// Use Registry to ensure GTypes are registered first
		var registry = new OLLMvector.Registry();
		registry.init_config();
		
		// Call base implementation
		return base_load_config();
	}
	
	protected override int command_line(ApplicationCommandLine command_line)
	{
		// Reset local static option variables at start of each command line invocation
		// This must happen BEFORE parsing, not in validate_args() which is called AFTER parsing
		opt_json = false;
		opt_show_info = null;
		opt_language = null;
		opt_element_type = null;
		opt_category = null;
		opt_max_results = 3;
		opt_max_snippet_lines = 10;
		opt_embed_model = null;
		
		// Call base implementation which will parse options and call validate_args()
		return base.command_line(command_line);
	}
	
	private static string[] VALID_CATEGORIES = {
		"plan", "documentation", "rule", "configuration", "data", "license", "changelog", "other"
	};
	
	protected override string? validate_args(string[] remaining_args)
	{
		// Note: Option variables are already reset in command_line() before parsing,
		// so they now contain the parsed values. Normalize string options to "" when unset.
		opt_language = opt_language == null ? "" : opt_language;
		opt_element_type = opt_element_type == null ? "" : opt_element_type;
		opt_category = opt_category == null ? "" : opt_category;
		opt_embed_model = opt_embed_model == null ? "" : opt_embed_model;
		
		if (opt_category != "") {
			var normalized = opt_category.strip().down();
			bool valid = false;
			foreach (var v in VALID_CATEGORIES) {
				if (normalized == v) {
					valid = true;
					break;
				}
			}
			if (!valid) {
				return "Invalid category \"%s\"; valid values: %s".printf(
					opt_category, string.joinv(", ", VALID_CATEGORIES));
			}
		}
		
		// Build paths at start
		this.db_path = GLib.Path.build_filename(this.data_dir, "files.sqlite");
		this.vector_db_path = GLib.Path.build_filename(this.data_dir, "codedb.faiss.vectors");
		
		string folder_path = remaining_args.length > 1 ? remaining_args[1] : "";
		string query = remaining_args.length > 2 ? remaining_args[2] : "";
		
		if (folder_path == "") {
			return help.replace("{ARG}", remaining_args[0]);
		}
		// When --show-info is set, query is optional; otherwise required
		if (opt_show_info == null && query == "") {
			return help.replace("{ARG}", remaining_args[0]);
		}
		
		return null;
	}
	
	protected override string get_app_name()
	{
		return "Code Vector Search";
	}
	
	protected override async void run_test(ApplicationCommandLine command_line, string[] remaining_args) throws Error
	{
		string folder_path = remaining_args.length > 1 ? remaining_args[1] : "";
		string query = remaining_args.length > 2 ? remaining_args[2] : "";
		
		if (folder_path == "") {
			throw new GLib.IOError.NOT_FOUND("Folder required");
		}
		if (opt_show_info != null) {
			yield this.run_show_info(folder_path, opt_show_info);
			return;
		}
		if (query == "") {
			throw new GLib.IOError.NOT_FOUND("Query required (or use --show-info=FILE to list metadata for a file)");
		}
		yield this.run_search(folder_path, query);
	}
	
	private async void run_show_info(string folder_path, string file_path) throws Error
	{
		stdout.printf("=== Vector metadata for file ===\n\n");
		this.ensure_data_dir();
		
		var sql_db = new SQ.Database(this.db_path, false);
		var manager = new OLLMfiles.ProjectManager(sql_db);
		
		var file = GLib.File.new_for_path(folder_path);
		if (!file.query_exists()) {
			throw new GLib.IOError.NOT_FOUND("Folder not found: " + folder_path);
		}
		var abs_folder = file.get_path();
		if (abs_folder == null) {
			throw new GLib.IOError.FAILED("Failed to get absolute path for: " + folder_path);
		}
		
		var results_list = new Gee.ArrayList<OLLMfiles.FileBase>();
		var query_obj = OLLMfiles.FileBase.query(sql_db, manager);
		var stmt = query_obj.selectPrepare(
				"SELECT " + string.joinv(",", query_obj.getColsExcept(null)) +
					 " FROM filebase WHERE path = $path AND delete_id = 0");
		stmt.bind_text(stmt.bind_parameter_index("$path"), abs_folder);
		query_obj.selectExecute(stmt, results_list);
		
		OLLMfiles.Folder? search_folder = null;
		if (results_list.size > 0 && results_list[0] is OLLMfiles.Folder) {
			search_folder = (OLLMfiles.Folder)results_list[0];
		} else {
			throw new GLib.IOError.NOT_FOUND("Folder not found in database: " + abs_folder);
		}
		
		yield search_folder.load_files_from_db();
		
		// Resolve file path: absolute or relative to folder
		string resolved_path;
		if (GLib.Path.is_absolute(file_path)) {
			resolved_path = file_path;
		} else {
			resolved_path = GLib.Path.build_filename(abs_folder, file_path);
		}
		try {
			var resolved_file = GLib.File.new_for_path(resolved_path);
			var canonical = resolved_file.resolve_relative_path(".");
			if (canonical != null) {
				resolved_path = canonical.get_path() ?? resolved_path;
			}
		} catch (GLib.Error e) {
			// Keep unresolved path for lookup
		}
		
		var file_base = search_folder.project_files.all_files.get(resolved_path);
		if (file_base == null) {
			// Try with folder path + file_path as stored in DB
			foreach (var entry in search_folder.project_files.all_files.entries) {
				if (entry.value is OLLMfiles.File && (entry.key.has_suffix(file_path) || entry.key == resolved_path)) {
					file_base = entry.value;
					break;
				}
			}
		}
		if (file_base == null) {
			throw new GLib.IOError.NOT_FOUND("File not found in project: " + file_path + " (resolved: " + resolved_path + ")");
		}
		if (file_base is OLLMfiles.Folder) {
			throw new GLib.IOError.NOT_FOUND("Path is a folder, not a file: " + file_path);
		}
		
		var metadata_list = new Gee.ArrayList<OLLMvector.VectorMetadata>();
		OLLMvector.VectorMetadata.query(sql_db).select(
			"WHERE file_id = " + file_base.id.to_string() + " ORDER BY start_line, id",
			metadata_list
		);
		
		stdout.printf("Folder: %s\n", search_folder.path);
		stdout.printf("File: %s (id=%lld)\n", file_base.path, file_base.id);
		stdout.printf("Vector metadata entries: %d\n\n", metadata_list.size);
		
		if (opt_json) {
			this.output_metadata_json(metadata_list);
		} else {
			this.output_metadata_text(metadata_list);
		}
	}
	
	private void output_metadata_text(Gee.ArrayList<OLLMvector.VectorMetadata> metadata_list)
	{
		for (int i = 0; i < metadata_list.size; i++) {
			var m = metadata_list.get(i);
			stdout.printf("--- Entry %d ---\n", i + 1);
			stdout.printf("  id: %lld  vector_id: %lld  file_id: %lld\n", m.id, m.vector_id, m.file_id);
			stdout.printf("  lines: %d-%d  type: %s  name: %s\n", m.start_line, m.end_line, m.element_type, m.element_name);
			if (m.ast_path != "") {
				stdout.printf("  ast_path: %s\n", m.ast_path);
			}
			if (m.category != "") {
				stdout.printf("  category: %s\n", m.category);
			}
			if (m.description != "") {
				stdout.printf("  description: %s\n", m.description);
			}
			stdout.printf("\n");
		}
	}
	
	private void output_metadata_json(Gee.ArrayList<OLLMvector.VectorMetadata> metadata_list)
	{
		var json_array = new Json.Array();
		foreach (var m in metadata_list) {
			json_array.add_element(Json.gobject_serialize(m));
		}
		var json_root = new Json.Node(Json.NodeType.ARRAY);
		json_root.set_array(json_array);
		var generator = new Json.Generator();
		generator.set_root(json_root);
		generator.set_pretty(true);
		generator.set_indent(2);
		stdout.printf("%s\n", generator.to_data(null));
	}
	
	private async void run_search(string folder_path, string query) throws Error
	{
		stdout.printf("=== Code Vector Search ===\n\n");
		
		this.ensure_data_dir();
		
		var sql_db = new SQ.Database(this.db_path, false);
		GLib.debug("Using database: %s", this.db_path);
		
		var manager = new OLLMfiles.ProjectManager(sql_db);
		
		OLLMchat.Client embed_client;
		
		if (this.config.loaded) {
			yield this.ensure_config();
			embed_client = yield this.tool_config_client("embed");
		} else {
			// Get client and verify model (tool_config_client will check model availability and apply CLI override)
			embed_client = yield this.tool_config_client("embed", opt_url, opt_api_key, opt_embed_model);
			
			// Save config after all checks are complete
			this.save_config();
		}
		
		// Get dimension first, then create database
		var temp_db = new OLLMvector.Database(this.config, 
			this.vector_db_path, OLLMvector.Database.DISABLE_INDEX);
		var dimension = yield temp_db.embed_dimension();
		var vector_db = new OLLMvector.Database(this.config, this.vector_db_path, dimension);
		
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
					 " FROM filebase WHERE path = $path AND delete_id = 0");
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
		var language_filter = opt_language;
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
		
		if (opt_element_type != "") {
			sql = sql + " AND element_type = $element_type";
		}
		if (opt_category != "") {
			sql = sql + " AND file_id IN (SELECT file_id FROM vector_metadata fvm WHERE fvm.category = $category) AND element_type IN ('document','section')";
		}
		
		GLib.debug("file_id_list from get_ids: %u IDs", file_ids.size);
		GLib.debug("Filter SQL: %s", sql);
		
		var vector_query = OLLMvector.VectorMetadata.query(sql_db);
		var vector_stmt = vector_query.selectPrepare(sql);
		
		if (opt_element_type != "") {
			vector_stmt.bind_text(
				vector_stmt.bind_parameter_index("$element_type"), opt_element_type);
		}
		if (opt_category != "") {
			vector_stmt.bind_text(
				vector_stmt.bind_parameter_index("$category"), opt_category);
		}
		
		foreach (var vector_id_str in vector_query.fetchAllString(vector_stmt)) {
			filtered_vector_ids.add((int)int64.parse(vector_id_str));
		}
		
		GLib.debug("Filtered to %lld vector IDs", filtered_vector_ids.size);
		
		if (filtered_vector_ids.size == 0) {
			stdout.printf("No document matches the criteria.\n");
			return;
		}
		
		// Create search instance (optional set via object initializer)
		var search = new OLLMvector.Search.Search(
			vector_db,
			sql_db,
			this.config,
			search_folder,
			query,
			filtered_vector_ids
		) {
			max_results = (uint64)opt_max_results,
			element_type_filter = opt_element_type,
			category_filter = opt_category
		};
		
		// Execute search
		stdout.printf("Folder: %s\n", search_folder.path);
		stdout.printf("Query: %s\n", query);
		if (opt_language != "" || opt_element_type != "" || opt_category != "") {
			var filters = new Gee.ArrayList<string>();
			if (opt_language != "") {
				filters.add("language: " + opt_language);
			}
			if (opt_element_type != "") {
				filters.add("element-type: " + opt_element_type);
			}
			if (opt_category != "") {
				filters.add("category: " + opt_category);
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
			
			// Display distance (lower distance = better match)
			stdout.printf("--- Result %d (distance: %.4f) ---\n", rank, results[i].distance);
			stdout.printf("File: %s\n", results[i].file().path);
			stdout.printf("Element: %s (%s)\n", results[i].metadata.element_name, results[i].metadata.element_type);
			stdout.printf("Lines: %d-%d\n", results[i].metadata.start_line, results[i].metadata.end_line);	
			stdout.printf("Description: %s\n", results[i].metadata.description);
			
			if (results[i].metadata.ast_path != "") {
				stdout.printf("ast-path: %s\n", results[i].metadata.ast_path);
			}
			
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

