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

class VectorIndexerApp : VectorAppBase
{
	protected static bool opt_recurse = true;
	protected static bool opt_reset_database = false;
	protected static bool opt_create_project = false;
	protected static string? opt_embed_model = null;
	protected static string? opt_analyze_model = null;
	protected static string? opt_data_dir = null;
	
	private string db_path;
	private string vector_db_path;
	
	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <file_or_folder_path>

Index files or folders for vector search.

Examples:
  {ARG} libocvector/Database.vala
  {ARG} --debug libocvector/Database.vala
  {ARG} libocvector/
  {ARG} --recurse libocvector/
  {ARG} --create-project libocvector/
  {ARG} --data-dir=/custom/path libocvector/
  {ARG} --reset-database
"""; }
	
	protected const OptionEntry[] local_options = {
		{ "recurse", 'r', 0, OptionArg.NONE, ref opt_recurse, "Recurse into subfolders (default: true)", null },
		{ "reset-database", 0, 0, OptionArg.NONE, ref opt_reset_database, "Reset the vector database (delete vectors, metadata, and reset scan dates)", null },
		{ "create-project", 0, 0, OptionArg.NONE, ref opt_create_project, "Create the folder as a project if it's not already one", null },
		{ "data-dir", 0, 0, OptionArg.STRING, ref opt_data_dir, "Data directory for database files (default: ~/.local/share/ollmchat)", "DIR" },
		{ "embed-model", 0, 0, OptionArg.STRING, ref opt_embed_model, "Embedding model name (default: bge-m3)", "MODEL" },
		{ "analyze-model", 0, 0, OptionArg.STRING, ref opt_analyze_model, "Analysis model name (default: qwen3-coder:30b)", "MODEL" },
		{ null }
	};
	
	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		opt_context.add_main_entries(base_options, null);
		
		var app_group = new OptionGroup("oc-vector-index", "Code Vector Indexer Options", "Show Code Vector Indexer options");
		app_group.add_entries(local_options);
		opt_context.add_group(app_group);
		
		return opt_context;
	}
	
	public VectorIndexerApp()
	{
		base("org.roojs.oc-vector-index");
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
		// Reset option variables to defaults before parsing (so parsed values are preserved)
		opt_recurse = true;
		opt_reset_database = false;
		opt_create_project = false;
		opt_embed_model = null;
		opt_analyze_model = null;
		opt_data_dir = null;
		
		return base.command_line(command_line);
	}
	
	protected override string? validate_args(string[] remaining_args)
	{
		// Apply data_dir from parsed options
		if (opt_data_dir != null && opt_data_dir != "") {
			this.data_dir = opt_data_dir;
		}
		
		// Build paths at start
		this.db_path = GLib.Path.build_filename(this.data_dir, "files.sqlite");
		this.vector_db_path = GLib.Path.build_filename(this.data_dir, "codedb.faiss.vectors");
		
		string? path = null;
		if (remaining_args.length > 1) {
			path = remaining_args[1];
		}
		
		if (path == null && !opt_reset_database) {
			return help.replace("{ARG}", remaining_args[0]);
		}
		
		return null;
	}
	
	protected override string get_app_name()
	{
		return "Code Vector Indexer";
	}
	
	protected override async void run_test(ApplicationCommandLine command_line, string[] remaining_args) throws Error
	{
		// Handle reset-database case
		if (opt_reset_database) {
			GLib.debug("opt_reset_database is true - resetting database");
			var sql_db = new SQ.Database(this.db_path, false);
			OLLMfiles.SQT.VectorMetadata.reset_database(sql_db, this.vector_db_path);
			stdout.printf("✓ Database reset complete\n");
			return;
		}
		
		GLib.debug("opt_reset_database is false - proceeding with normal indexing");
		
		string? path = null;
		if (remaining_args.length > 1) {
			path = remaining_args[1];
		}
		
		if (path == null) {
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
		bool is_folder = file_info.get_file_type() == GLib.FileType.DIRECTORY;
		
		if (is_folder) {
			if (opt_recurse) {
				stdout.printf("Folder: %s\nRecursion: enabled\n\n", abs_path);
			} else {
				stdout.printf("Folder: %s\n\n", abs_path);
			}
		} else {
			stdout.printf("File: %s\n\n", abs_path);
		}
		
		this.ensure_data_dir();
		
		var sql_db = new SQ.Database(this.db_path, false);
		GLib.debug("Using database: %s", this.db_path);
		
		var manager = new OLLMfiles.ProjectManager(sql_db);
		// Use base BufferProviderBase (not GTK-based) - correctly maps .js to "javascript"
		// manager.buffer_provider defaults to BufferProviderBase which is sufficient for indexing
		// manager.git_provider defaults to GitProviderBase which is sufficient for indexing
		
		OLLMchat.Client embed_client;
		OLLMchat.Client analysis_client;
		
		if (this.config.loaded) {
			yield this.ensure_config();
		} else {
			// Ensure config exists before setting up tool config
			yield this.ensure_config(opt_url, opt_api_key);
		}
		
		// Ensure tool config exists
		new OLLMvector.Tool.CodebaseSearchTool(null).setup_tool_config_default(this.config);
		
		// Inline tool config access
		if (!this.config.tools.has_key("codebase_search")) {
			GLib.error("Codebase search tool config not found");
		}
		var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
		
		if (this.config.loaded) {
			embed_client = yield this.tool_config_client("embed");
			analysis_client = yield this.tool_config_client("analysis");
		} else {
			// Get clients and verify models (tool_config_client will check model availability and apply CLI overrides)
			embed_client = yield this.tool_config_client("embed", opt_url, opt_api_key, opt_embed_model);
			analysis_client = yield this.tool_config_client("analysis", opt_url, opt_api_key, opt_analyze_model);
			
			// Save config after all checks are complete
			this.save_config();
		}
		
		// Phase 3: model is not on Client, get from tool_config
		stdout.printf("Analysis Model: %s\n" +
		              "Embed Model: %s\n\n",
		              tool_config.analysis.model, tool_config.embed.model);
		
		// Get dimension first, then create database
		var temp_db = new OLLMvector.Database(this.config, 
			this.vector_db_path, OLLMvector.Database.DISABLE_INDEX);
		var dimension = yield temp_db.embed_dimension();
		var vector_db = new OLLMvector.Database(this.config, this.vector_db_path, dimension);
		
		GLib.debug("Using vector database: %s", this.vector_db_path);
		
		var indexer = new OLLMvector.Indexing.Indexer(
			this.config,
			vector_db,
			sql_db,
			manager
		);
		
		string? current_file_path = null;
		int current_file_num = 0;
		int total_files = 0;
		
		indexer.progress.connect((current, total, file_path, success) => {
			if (success) {
				sql_db.backupDB();
				return;
			}
			int percentage = (int)((current * 100.0) / total);
			// Trim any trailing whitespace from file_path in case of database corruption
			var clean_path = file_path.strip();
			current_file_path = clean_path;
			current_file_num = current;
			total_files = total;
			stdout.printf("\r%d/%d files %d%% done - %s", current, total, percentage, clean_path);
			stdout.flush();
		});
		
		indexer.element_scanned.connect((element_name, element_number, total_elements) => {
			if (current_file_path != null) {
				int percentage = (int)((current_file_num * 100.0) / total_files);
				stdout.printf("\r%d/%d files %d%% done - %s - %s (%d/%d)", 
					current_file_num, total_files, percentage, current_file_path, element_name, element_number, total_elements);
				stdout.flush();
			}
		});
		
		stdout.printf("=== Indexing ===\n");
		
		// Look up FileBase object from database
		var results_list = new Gee.ArrayList<OLLMfiles.FileBase>();
		var query = OLLMfiles.FileBase.query(sql_db, manager);
		var stmt = query.selectPrepare(
				"SELECT " + string.joinv(",", query.getColsExcept(null)) +
					 " FROM filebase WHERE path = $path AND delete_id = 0");
		stmt.bind_text(stmt.bind_parameter_index("$path"), abs_path);
		query.selectExecute(stmt, results_list);
		
		OLLMfiles.FileBase? filebase = null;
		if (results_list.size > 0) {
			filebase = results_list[0];
		}
		
		// Check error conditions first
		if (filebase == null && !opt_create_project) {
			throw new GLib.IOError.INVALID_ARGUMENT(
				"Folder '%s' is not in the database. Use --create-project to create it as a project first.".printf(abs_path)
			);
		}
		
		if (filebase != null && !(filebase is OLLMfiles.Folder)) {
			throw new GLib.IOError.INVALID_ARGUMENT("Only folders can be indexed, not files");
		}
		
		// Get or create folder object
		var folder_obj = filebase == null ?  new OLLMfiles.Folder(manager) :
				(OLLMfiles.Folder)filebase;
		if (filebase == null) {
			
			folder_obj.path = abs_path;
			folder_obj.display_name = GLib.Path.get_basename(abs_path);
		} 
		
		// Check error condition: folder must be a project
		if (!folder_obj.is_project && !opt_create_project) {
			throw new GLib.IOError.INVALID_ARGUMENT(
				"Folder '%s' is not a project. Use --create-project to create it as a project first.".printf(abs_path)
			);
		}
		
		// Create or convert to project if needed
		if (!folder_obj.is_project) {
			stdout.printf(filebase == null ? 
				"Creating folder as project: %s\n" : "Converting folder to project: %s\n", 
				abs_path);
			
			folder_obj.is_project = true;
			folder_obj.display_name = GLib.Path.get_basename(abs_path);
			folder_obj.saveToDB(sql_db, null, false);
			
			// Add to projects list
			manager.projects.append(folder_obj);
			stdout.printf("✓ Project created\n\n");
		}
		stdout.printf("Starting indexing process...\n" +
		              "Indexing folder: %s (recurse=%s)\n",
		              folder_obj.path, opt_recurse.to_string());
		
		// Set up folder for indexing: scan files and update project_files
		// Disable background_recurse to ensure file scan completes before indexing
		// (No need to restore - process exits at end)
		OLLMfiles.Folder.background_recurse = false;
		
		// Load children from database if needed
		if (folder_obj.children.items.size == 0) {
			stdout.printf("Loading folder children from database...\n");
			yield folder_obj.load_files_from_db();
		}
		
		// Scan the folder (like the desktop does)
		stdout.printf("Scanning folder for files...\n");
		var scan_time = new DateTime.now_local().to_unix();
		yield folder_obj.read_dir(scan_time, true);
		
		// Update project_files to get the list of files to index
		// This filters ignored/non-text files and handles removals
		stdout.printf("Updating project files list...\n");
		folder_obj.project_files.update_from(folder_obj);
		
		try {
			stdout.printf("Calling indexer.index_filebase...\n");
			int files_indexed = yield indexer.index_filebase(folder_obj, opt_recurse, false);
			stdout.printf("\n" +
			              "index_filebase returned: %d files indexed\n" +
			              "✓ Indexing completed\n" +
			              "  Files indexed: %d\n" +
			              "  Total vectors: %llu\n" +
			              "  Vector dimension: %llu\n\n",
			              files_indexed, files_indexed, vector_db.vector_count, vector_db.dimension);
			
			// Set last_vector_scan timestamp after successful indexing
			var vector_scan_time = new DateTime.now_local().to_unix();
			folder_obj.last_vector_scan = vector_scan_time;
			folder_obj.saveToDB(sql_db, null, true);
		} catch (GLib.Error e) {
			stdout.printf("Error during indexing: %s\n", e.message);
			throw e;
		}
		
		try {
			vector_db.save_index();
			GLib.debug("Saved vector database: %s", this.vector_db_path);
		} catch (GLib.Error e) {
			GLib.warning("Failed to save vector database: %s", e.message);
		}
		
		stdout.printf("=== Indexing Complete ===\n" +
		              "Database: %s\n" +
		              "Vector database: %s\n",
		              this.db_path, this.vector_db_path);
	}
}

int main(string[] args)
{
	var app = new VectorIndexerApp();
	return app.run(args);
}
