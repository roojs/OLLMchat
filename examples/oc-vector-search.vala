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

class VectorSearchApp : TestAppBase
{
	protected static bool opt_json = false;
	protected static string? opt_show_info = null;
	protected static string? opt_language = null;
	protected static string? opt_element_type = null;
	protected static string? opt_category = null;
	protected static int opt_max_results = 3;
	protected static int opt_max_snippet_lines = 10;
	protected static string? opt_dump_vector = null;
	protected static string? opt_only_file = null;
	protected static string? opt_data_dir = null;

	private OLLMrpc.Client rpc;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <folder> [query]

Search indexed codebase using semantic vector search.

Arguments:
  folder                 Folder path to search within (required)
  query                  Search query text (required unless --show-info is used)

Options:
  --show-info=FILE       List all vector metadata for the given file (path relative to folder or absolute)

Examples:
  {ARG} libocfiles "database connection"
  {ARG} --json libocfiles "async function"
  {ARG} --show-info README.md libocfiles
  {ARG} --show-info docs/guide.md libocfiles
  {ARG} --language=vala --element-type=method libocfiles "parse"
  {ARG} --category=documentation libocfiles "packaging"
  {ARG} --max-results=20 libocfiles "search"
  {ARG} --max-snippet-lines=5 libocfiles "search"
  {ARG} --data-dir=/custom/path libocfiles "search"
  {ARG} --dump-vector=OLLMcoder.Task-List-write libocfiles
  {ARG} --only-file=liboccoder/Task/List.vala libocfiles "write"
"""; }

	protected const OptionEntry[] local_options = {
		{ "json", 'j', 0, OptionArg.NONE, ref opt_json, "Output results as JSON", null },
		{ "show-info", 0, 0, OptionArg.STRING, ref opt_show_info, "List vector metadata for a file", "FILE" },
		{ "language", 'l', 0, OptionArg.STRING, ref opt_language, "Filter by language (e.g., vala, python)", "LANG" },
		{ "element-type", 'e', 0, OptionArg.STRING, ref opt_element_type, "Filter by element type (e.g., class, method, function, property, struct, interface, enum, constructor, field, delegate, signal, constant, file, document, section)", "TYPE" },
		{ "category", 'c', 0, OptionArg.STRING, ref opt_category, "Filter docs by category (plan, documentation, rule, configuration, data, license, changelog, other)", "CATEGORY" },
		{ "max-results", 'n', 0, OptionArg.INT, ref opt_max_results, "Maximum number of results (default: 3)", "N" },
		{ "max-snippet-lines", 's', 0, OptionArg.INT, ref opt_max_snippet_lines, "Maximum lines of code snippet to display (default: 10, -1 for no limit)", "N" },
		{ "data-dir", 0, 0, OptionArg.STRING, ref opt_data_dir, "Data directory for database files (default: ~/.local/share/ollmchat)", "DIR" },
		{ "dump-vector", 0, 0, OptionArg.STRING, ref opt_dump_vector, "Dump stored vector for AST path (one float per line, for diff)", "AST_PATH" },
		{ "only-file", 0, 0, OptionArg.STRING, ref opt_only_file, "Restrict search to vectors from this file only (path relative to folder)", "FILE" },
		{ null }
	};

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		opt_context.add_main_entries(base_options, null);

		var app_group = new OptionGroup(
			"oc-vector-search",
			"Code Vector Search Options",
			"Show Code Vector Search options"
		);
		app_group.add_entries(local_options);
		opt_context.add_group(app_group);

		return opt_context;
	}

	public VectorSearchApp()
	{
		base("org.roojs.oc-vector-search");
	}

	protected override int command_line(ApplicationCommandLine command_line)
	{
		opt_json = false;
		opt_show_info = null;
		opt_language = null;
		opt_element_type = null;
		opt_category = null;
		opt_max_results = 3;
		opt_max_snippet_lines = 10;
		opt_dump_vector = null;
		opt_only_file = null;
		opt_data_dir = null;

		return base.command_line(command_line);
	}

	private static string[] VALID_CATEGORIES = {
		"plan", "documentation", "rule", "configuration", "data", "license", "changelog", "other"
	};

	protected override string? validate_args(string[] remaining_args)
	{
		opt_language = opt_language == null ? "" : opt_language;
		opt_element_type = opt_element_type == null ? "" : opt_element_type;
		opt_category = opt_category == null ? "" : opt_category;
		opt_dump_vector = opt_dump_vector == null ? "" : opt_dump_vector;
		opt_only_file = opt_only_file == null ? "" : opt_only_file;
		opt_data_dir = opt_data_dir == null ? "" : opt_data_dir;
		opt_show_info = opt_show_info == null ? "" : opt_show_info;

		if (opt_data_dir != "") {
			this.data_dir = opt_data_dir;
			var data_dir_file = GLib.File.new_for_path(this.data_dir);
			if (!data_dir_file.query_exists()) {
				return "Error: data directory does not exist: %s\n".printf(this.data_dir);
			}
		}

		if (opt_category != "") {
			var normalized = opt_category.strip().down();
			var valid = false;
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

		var folder_path = remaining_args.length > 1 ? remaining_args[1] : "";
		var query = remaining_args.length > 2 ? remaining_args[2] : "";

		if (folder_path == "") {
			return help.replace("{ARG}", remaining_args[0]);
		}
		if (opt_show_info == "" && opt_dump_vector == "" && query == "") {
			return help.replace("{ARG}", remaining_args[0]);
		}

		return null;
	}

	protected override string get_app_name()
	{
		return "Code Vector Search";
	}

	protected override async void run_test(
		ApplicationCommandLine command_line,
		string[] remaining_args
	) throws Error
	{
		var folder_path = remaining_args.length > 1 ? remaining_args[1] : "";
		var query = remaining_args.length > 2 ? remaining_args[2] : "";

		if (folder_path == "") {
			throw new GLib.IOError.NOT_FOUND("Folder required");
		}

		var folder_file = GLib.File.new_for_path(folder_path);
		if (!folder_file.query_exists()) {
			throw new GLib.IOError.NOT_FOUND("Folder not found: " + folder_path);
		}
		var abs_folder = folder_file.get_path();
		if (abs_folder == null) {
			throw new GLib.IOError.FAILED("Failed to get absolute path for: " + folder_path);
		}

		OLLMrpc.Daemon.rpc_register();
		OLLMfilesd.DaemonParams.rpc_register();
		OLLMfilesd.ProjectParams.rpc_register();
		OLLMfilesd.VectorParams.rpc_register();
		OLLMfiles.SQT.VectorMetadata.rpc_register();

		this.rpc = new OLLMrpc.Client(
			this.data_dir,
			"ollmfilesd.pid",
			"ollmfilesd.sock"
		) {
			debug = opt_debug,
			pass_data_dir = opt_data_dir != ""
		};

		if (!yield this.rpc.connect(new OLLMrpc.Request() {
			method = "Daemon.hello",
			param = new OLLMfilesd.DaemonParams() {
				protocol = 1,
				client = "oc-vector-search"
			}
		})) {
			var msg = this.rpc.connect_error;
			if (msg == "") {
				msg = "could not start or reach the filesystem daemon (ollmfilesd)";
			}
			throw new GLib.IOError.FAILED("%s", msg);
		}

		var load_response = yield this.rpc.call(new OLLMrpc.Request() {
			method = "ProjectManager.load_projects_from_db",
			param = new OLLMfilesd.ProjectParams()
		});
		if (load_response.error != null) {
			throw new GLib.IOError.FAILED(load_response.error.message);
		}

		var activate_response = yield this.rpc.call(new OLLMrpc.Request() {
			method = "ProjectManager.activate_project",
			param = new OLLMfilesd.ProjectParams() {
				path = abs_folder,
				skip_scan = true
			}
		});
		if (activate_response.error != null) {
			throw new GLib.IOError.FAILED(activate_response.error.message);
		}

		if (opt_show_info != "") {
			yield this.run_show_info(abs_folder, opt_show_info);
			return;
		}
		if (opt_dump_vector != "") {
			yield this.run_dump_vector(abs_folder, opt_dump_vector);
			return;
		}
		if (query == "") {
			throw new GLib.IOError.NOT_FOUND(
				"Query required (or use --show-info=FILE to list metadata for a file)"
			);
		}
		yield this.run_search(abs_folder, query);
	}

	private async void run_show_info(string abs_folder, string file_path) throws Error
	{
		stdout.printf("=== Vector metadata for file ===\n\n");

		var resolved_path = GLib.Path.is_absolute(file_path)
			? file_path
			: GLib.Path.build_filename(abs_folder, file_path);
		try {
			var resolved_file = GLib.File.new_for_path(resolved_path);
			var canonical = resolved_file.resolve_relative_path(".");
			if (canonical != null) {
				resolved_path = canonical.get_path() ?? resolved_path;
			}
		} catch (GLib.Error e) {
			// Keep unresolved path for daemon lookup
		}

		var response = yield this.rpc.call(new OLLMrpc.Request() {
			method = "Codebase.file_info",
			param = new OLLMfilesd.VectorParams() {
				path = abs_folder,
				file_path = resolved_path
			}
		});
		if (response.error != null) {
			throw new GLib.IOError.FAILED(response.error.message);
		}

		var metadata_list = (Gee.ArrayList<OLLMfiles.SQT.VectorMetadata>) response.result;

		stdout.printf("Folder: %s\n", abs_folder);
		stdout.printf("File: %s\n", resolved_path);
		stdout.printf("Vector metadata entries: %d\n\n", metadata_list.size);

		if (opt_json) {
			this.output_metadata_json(metadata_list);
		} else {
			this.output_metadata_text(metadata_list);
		}
	}

	private void output_metadata_text(Gee.ArrayList<OLLMfiles.SQT.VectorMetadata> metadata_list)
	{
		for (var i = 0; i < metadata_list.size; i++) {
			var m = metadata_list.get(i);
			stdout.printf("--- Entry %d ---\n", i + 1);
			stdout.printf(
				"  id: %lld  vector_id: %lld  file_id: %lld\n",
				m.id,
				m.vector_id,
				m.file_id
			);
			stdout.printf(
				"  lines: %d-%d  type: %s  name: %s\n",
				m.start_line,
				m.end_line,
				m.element_type,
				m.element_name
			);
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

	private void output_metadata_json(Gee.ArrayList<OLLMfiles.SQT.VectorMetadata> metadata_list)
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

	private async void run_dump_vector(string abs_folder, string ast_path) throws Error
	{
		var response = yield this.rpc.call(new OLLMrpc.Request() {
			method = "Codebase.debug_get",
			param = new OLLMfilesd.VectorParams() {
				path = abs_folder,
				ast_path = ast_path
			}
		});
		if (response.error != null) {
			throw new GLib.IOError.FAILED(response.error.message);
		}
		stdout.printf("%s", response.msg);
		if (!response.msg.has_suffix("\n")) {
			stdout.printf("\n");
		}
	}

	private async void run_search(string abs_folder, string query) throws Error
	{
		if (!opt_json) {
			stdout.printf("=== Code Vector Search ===\n\n");
			stdout.printf("Folder: %s\n", abs_folder);
			stdout.printf("Query: %s\n", query);
			if (opt_language != "" || opt_element_type != "" || opt_category != "" || opt_only_file != "") {
				var filters = new Gee.ArrayList<string>();
				if (opt_only_file != "") {
					filters.add("only-file: " + opt_only_file);
				}
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
		}

		var response = yield this.rpc.call(new OLLMrpc.Request() {
			method = "Codebase.search",
			param = new OLLMfilesd.VectorParams() {
				path = abs_folder,
				query = query,
				language = opt_language,
				element_type = opt_element_type,
				category = opt_category,
				max_results = opt_max_results,
				only_file = opt_only_file,
				format = opt_json ? "json" : ""
			}
		});
		if (response.error != null) {
			throw new GLib.IOError.FAILED(response.error.message);
		}
		stdout.printf("%s\n", response.msg);
	}
}

int main(string[] args)
{
	var app = new VectorSearchApp();
	return app.run(args);
}
