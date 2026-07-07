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

class VectorIndexerApp : TestAppBase
{
	protected static bool opt_recurse = true;
	protected static bool opt_reset_database = false;
	protected static bool opt_create_project = false;
	protected static bool opt_project_summary = false;
	protected static string? opt_embed_model = null;
	protected static string? opt_analyze_model = null;
	protected static string? opt_data_dir = null;
	protected static string? opt_only_file = null;

	private OLLMrpc.Client rpc;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <file_or_folder_path>

Index files or folders for vector search.

Examples:
  {ARG} libocvector/
  {ARG} --recurse libocvector/
  {ARG} --create-project libocvector/
  {ARG} --only-file=libocvector/Database.vala libocvector/
  {ARG} --project-summary libocvector/
  {ARG} --data-dir=/custom/path libocvector/
  {ARG} --reset-database
"""; }

	protected const OptionEntry[] local_options = {
		{ "recurse", 'r', 0, OptionArg.NONE, ref opt_recurse, "Recurse into subfolders (default: true)", null },
		{ "reset-database", 0, 0, OptionArg.NONE, ref opt_reset_database, "Reset the vector database (delete vectors, metadata, and reset scan dates)", null },
		{ "create-project", 0, 0, OptionArg.NONE, ref opt_create_project, "Create the folder as a project if it's not already one", null },
		{ "project-summary", 0, 0, OptionArg.NONE, ref opt_project_summary, "Only generate project summary from existing metadata (file scan runs; indexer does not)", null },
		{ "data-dir", 0, 0, OptionArg.STRING, ref opt_data_dir, "Data directory for database files (default: ~/.local/share/ollmchat)", "DIR" },
		{ "only-file", 0, 0, OptionArg.STRING, ref opt_only_file, "Index only one file within the selected folder/project", "PATH" },
		{ "embed-model", 0, 0, OptionArg.STRING, ref opt_embed_model, "Embedding model name (default: bge-m3)", "MODEL" },
		{ "analyze-model", 0, 0, OptionArg.STRING, ref opt_analyze_model, "Analysis model name (default: qwen3-coder:30b)", "MODEL" },
		{ null }
	};

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		opt_context.add_main_entries(base_options, null);

		var app_group = new OptionGroup(
			"oc-vector-index",
			"Code Vector Indexer Options",
			"Show Code Vector Indexer options"
		);
		app_group.add_entries(local_options);
		opt_context.add_group(app_group);

		return opt_context;
	}

	public VectorIndexerApp()
	{
		base("org.roojs.oc-vector-index");
	}

	protected override int command_line(ApplicationCommandLine command_line)
	{
		opt_recurse = true;
		opt_reset_database = false;
		opt_create_project = false;
		opt_project_summary = false;
		opt_embed_model = null;
		opt_analyze_model = null;
		opt_data_dir = null;
		opt_only_file = null;

		return base.command_line(command_line);
	}

	protected override string? validate_args(string[] remaining_args)
	{
		opt_data_dir = opt_data_dir == null ? "" : opt_data_dir;
		opt_only_file = opt_only_file == null ? "" : opt_only_file;
		opt_embed_model = opt_embed_model == null ? "" : opt_embed_model;
		opt_analyze_model = opt_analyze_model == null ? "" : opt_analyze_model;

#if WINDOWS
		if (opt_data_dir != "") {
			return "Error: --data-dir is not supported on Windows\n";
		}
#endif

		if (opt_data_dir != "") {
			this.data_dir = opt_data_dir;
			var data_dir_file = GLib.File.new_for_path(this.data_dir);
			if (!data_dir_file.query_exists()) {
				return "Error: data directory does not exist: %s\n".printf(this.data_dir);
			}
		}

		var path = remaining_args.length > 1 ? remaining_args[1] : "";

		if (path == "" && !opt_reset_database) {
			return help.replace("{ARG}", remaining_args[0]);
		}

		if (opt_only_file != "" && opt_project_summary) {
			return "--only-file cannot be combined with --project-summary\n";
		}

		return null;
	}

	protected override string get_app_name()
	{
		return "Code Vector Indexer";
	}

	protected override async void run_test(
		ApplicationCommandLine command_line,
		string[] remaining_args
	) throws Error
	{
		OLLMrpc.Daemon.rpc_register();
		OLLMfilesd.DaemonParams.rpc_register();
		OLLMfilesd.ProjectParams.rpc_register();
		OLLMfilesd.FolderParams.rpc_register();
		OLLMfilesd.VectorParams.rpc_register();
		OLLMrpc.Bin.register("Folder", typeof(OLLMfiles.Folder));

		var pass_data_dir = opt_data_dir != "";
		this.rpc = new OLLMrpc.Client(
			this.data_dir,
			"ollmfilesd.pid",
			"ollmfilesd.sock",
			opt_debug,
			pass_data_dir
		);

		if (!yield this.rpc.connect(new OLLMrpc.Request() {
			method = "Daemon.hello",
			param = new OLLMfilesd.DaemonParams() {
				protocol = 1,
				client = "oc-vector-index"
			}
		})) {
			var msg = this.rpc.connect_error;
			if (msg == "") {
				msg = "could not start or reach the filesystem daemon (ollmfilesd)";
			}
			throw new GLib.IOError.FAILED("%s", msg);
		}

		if (opt_reset_database) {
			var reset_response = yield this.rpc.call(new OLLMrpc.Request() {
				method = "Codebase.reset",
				param = new OLLMfilesd.VectorParams()
			});
			if (reset_response.error != null) {
				throw new GLib.IOError.FAILED(reset_response.error.message);
			}
			stdout.printf("✓ Database reset complete\n");
			return;
		}

		var path = remaining_args.length > 1 ? remaining_args[1] : "";
		if (path == "") {
			throw new GLib.IOError.NOT_FOUND("Path required");
		}

		yield this.run_index(path);
	}

	private async void run_index(string path) throws Error
	{
		stdout.printf("=== Code Vector Indexer ===\n\n");

		var file = GLib.File.new_for_path(path);
		if (!file.query_exists()) {
			throw new GLib.IOError.NOT_FOUND("Path not found: " + path);
		}

		var abs_path = file.get_path();
		if (abs_path == null) {
			throw new GLib.IOError.FAILED("Failed to get absolute path for: " + path);
		}

		var file_info = file.query_info("standard::type", GLib.FileQueryInfoFlags.NONE, null);
		var is_folder = file_info.get_file_type() == GLib.FileType.DIRECTORY;
		var project_path = is_folder ? abs_path : GLib.Path.get_dirname(abs_path);

		if (is_folder) {
			if (opt_recurse) {
				stdout.printf("Folder: %s\nRecursion: enabled\n\n", abs_path);
			} else {
				stdout.printf("Folder: %s\n\n", abs_path);
			}
		} else {
			stdout.printf("File: %s\n\n", abs_path);
		}

		var load_response = yield this.rpc.call(new OLLMrpc.Request() {
			method = "ProjectManager.load_projects_from_db",
			param = new OLLMfilesd.ProjectParams()
		});
		if (load_response.error != null) {
			throw new GLib.IOError.FAILED(load_response.error.message);
		}

		var fetch_response = yield this.rpc.call(new OLLMrpc.Request() {
			method = "Folder.fetch",
			param = new OLLMfilesd.FolderParams() { path = project_path }
		});
		if (fetch_response.error != null) {
			throw new GLib.IOError.FAILED(fetch_response.error.message);
		}
		var folders = (Gee.ArrayList<OLLMfiles.Folder>) fetch_response.result;
		if (folders.size == 0 && !opt_create_project) {
			throw new GLib.IOError.INVALID_ARGUMENT(
				"Folder '%s' is not in the database. Use --create-project to create it as a project first.".printf(
					project_path
				)
			);
		}
		if (folders.size > 0 && !folders.get(0).is_project && !opt_create_project) {
			throw new GLib.IOError.INVALID_ARGUMENT(
				"Folder '%s' is not a project. Use --create-project to create it as a project first.".printf(
					project_path
				)
			);
		}

		if (opt_create_project) {
			stdout.printf("Creating folder as project: %s\n", project_path);
			var create_response = yield this.rpc.call(new OLLMrpc.Request() {
				method = "ProjectManager.create_project",
				param = new OLLMfilesd.ProjectParams() { path = project_path }
			});
			if (create_response.error != null) {
				throw new GLib.IOError.FAILED(create_response.error.message);
			}
			stdout.printf("✓ Project created\n\n");
		}

		stdout.printf("Scanning folder for files...\n");
		var scan_response = yield this.rpc.call(new OLLMrpc.Request() {
			method = "ProjectManager.activate_project",
			param = new OLLMfilesd.ProjectParams() {
				path = project_path,
				skip_scan = false
			}
		});
		if (scan_response.error != null) {
			throw new GLib.IOError.FAILED(scan_response.error.message);
		}
		stdout.printf("✓ Filesystem scan complete\n\n");

		if (opt_project_summary) {
			stdout.printf("=== Project summary ===\n\n");
			var summary_response = yield this.rpc.call(new OLLMrpc.Request() {
				method = "Folder.project_description",
				param = new OLLMfilesd.FolderParams() { path = project_path }
			});
			if (summary_response.error != null) {
				throw new GLib.IOError.FAILED(summary_response.error.message);
			}
			if (summary_response.msg == "") {
				stdout.printf("(no project summary in database)\n");
			} else {
				stdout.printf("%s\n", summary_response.msg);
			}
			stdout.printf("\n=== Project summary complete ===\n");
			return;
		}

		if (opt_only_file != "") {
			stdout.printf(
				"Starting indexing process...\n" +
				"Indexing folder: %s\n" +
				"Only file: %s\n\n",
				project_path,
				opt_only_file
			);
		} else {
			stdout.printf(
				"Starting indexing process...\n" +
				"Indexing folder: %s (recurse=%s)\n\n",
				project_path,
				opt_recurse.to_string()
			);
		}

		stdout.printf("=== Indexing ===\n");

		var index_done = new Gee.Promise<bool>();
		var index_finished = false;
		this.rpc.notification.connect((notif) => {
			if (index_finished) {
				return;
			}
			if (notif.method != "event.vector.scan_update") {
				return;
			}
			var space = notif.message.index_of(" ");
			if (space < 0) {
				return;
			}
			var queue_text = notif.message.substring(0, space);
			var current_file = notif.message.substring(space + 1);
			if (current_file != "") {
				stdout.printf(
					"\r%s %s",
					queue_text,
					GLib.Path.get_basename(current_file)
				);
				stdout.flush();
			}
			if (notif.message.has_prefix("0 ")) {
				index_finished = true;
				index_done.set_value(true);
			}
		});

		var start_response = yield this.rpc.call(new OLLMrpc.Request() {
			method = "Codebase.start",
			param = new OLLMfilesd.VectorParams() {
				path = project_path,
				only_file = opt_only_file
			}
		});
		if (start_response.error != null) {
			throw new GLib.IOError.FAILED(start_response.error.message);
		}
		yield index_done.future.wait_async();

		stdout.printf("\n✓ Indexing completed\n");
		stdout.printf("=== Indexing Complete ===\n");
	}
}

int main(string[] args)
{
	var app = new VectorIndexerApp();
	return app.run(args);
}
