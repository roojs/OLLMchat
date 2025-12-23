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

class VectorIndexerApp : Application
{
	private static bool opt_debug = false;
	private static bool opt_recurse = false;
	private static bool opt_reset_database = false;
	
	private string data_dir;
	private string db_path;
	private string vector_db_path;
	
	const OptionEntry[] options = {
		{ "debug", 'd', 0, OptionArg.NONE, ref opt_debug, "Enable debug output", null },
		{ "recurse", 'r', 0, OptionArg.NONE, ref opt_recurse, "Recurse into subfolders (only for folders)", null },
		{ "reset-database", 0, 0, OptionArg.NONE, ref opt_reset_database, "Reset the vector database (delete vectors, metadata, and reset scan dates)", null },
		{ null }
	};
	
	public VectorIndexerApp()
	{
		Object(
			application_id: "org.roojs.oc-vector-index",
			flags: ApplicationFlags.HANDLES_COMMAND_LINE
		);
	}
	
	protected override int command_line(ApplicationCommandLine command_line)
	{
		// Reset static option variables at start of each command line invocation
		opt_reset_database = false;
		opt_debug = false;
		opt_recurse = false;
		
		string[] args = command_line.get_arguments();
		var opt_context = new OptionContext("Code Vector Indexer");
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
		
		string? path = null;
		if (args.length > 1) {
			path = args[1];
		}
		
		if (path == null && !opt_reset_database) {
			var usage = @"Usage: $(args[0]) [OPTIONS] <file_or_folder_path>

Index files or folders for vector search.

Options:
  -d, --debug          Enable debug output
  -r, --recurse        Recurse into subfolders (only for folders)
  --reset-database     Reset the vector database (delete vectors, metadata, and reset scan dates)

Examples:
  $(args[0]) libocvector/Database.vala
  $(args[0]) --debug libocvector/Database.vala
  $(args[0]) libocvector/
  $(args[0]) --recurse libocvector/
  $(args[0]) --reset-database
";
			command_line.printerr("%s", usage);
			return 1;
		}
		
		if (opt_reset_database) {
			GLib.debug("opt_reset_database is true - resetting database");
			try {
				var sql_db = new SQ.Database(this.db_path, false);
				OLLMvector.VectorMetadata.reset_database(sql_db, this.vector_db_path);
				stdout.printf("✓ Database reset complete\n");
			} catch (Error e) {
				command_line.printerr("Error: %s\n", e.message);
				return 1;
			}
			return 0;
		}
		
		GLib.debug("opt_reset_database is false - proceeding with normal indexing");
		
		// Hold the application to keep main loop running during async operations
		this.hold();
		
		this.run_index.begin(path, (obj, res) => {
			try {
				this.run_index.end(res);
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
			var folder_info = opt_recurse ? 
				@"Folder: $(abs_path)
Recursion: enabled

" : 
				@"Folder: $(abs_path)

";
			stdout.printf("%s", folder_info);
		} else {
			stdout.printf("File: %s\n\n", abs_path);
		}
		
		var data_dir_file = GLib.File.new_for_path(this.data_dir);
		if (!data_dir_file.query_exists()) {
			try {
				data_dir_file.make_directory_with_parents(null);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to create data directory: " + e.message);
			}
		}
		
		var sql_db = new SQ.Database(this.db_path, false);
		GLib.debug("Using database: %s", this.db_path);
		
		var manager = new OLLMfiles.ProjectManager(sql_db);
		// Use base BufferProviderBase (not GTK-based) - correctly maps .js to "javascript"
		// manager.buffer_provider defaults to BufferProviderBase which is sufficient for indexing
		// manager.git_provider defaults to GitProviderBase which is sufficient for indexing
		
		var analysis_config_path = GLib.Path.build_filename(
			GLib.Environment.get_home_dir(), ".config", "ollmchat", "analysis.json"
		);
		
		if (!GLib.FileUtils.test(analysis_config_path, GLib.FileTest.EXISTS)) {
			throw new GLib.IOError.NOT_FOUND("Analysis config not found at " + analysis_config_path);
		}
		
		GLib.debug("Loading analysis config from: %s", analysis_config_path);
		var parser = new Json.Parser();
		parser.load_from_file(analysis_config_path);
		var obj = parser.get_root().get_object();
		 
		var analysis_client = new OLLMchat.Client(new OLLMchat.Config() {
			url = obj.get_string_member("url"),
			model = obj.get_string_member("model"),
			api_key = obj.get_string_member("api-key")
		});
		analysis_client.options = new OLLMchat.Call.Options() {
			temperature = 0.0,
			num_ctx = 65536,
			top_k = 1405,
			top_p = 0.9,
			min_p = 0.1
		};
		
		var embed_config_path = GLib.Path.build_filename(
			GLib.Environment.get_home_dir(), ".config", "ollmchat", "embed.json"
		);
		
		if (!GLib.FileUtils.test(embed_config_path, GLib.FileTest.EXISTS)) {
			throw new GLib.IOError.NOT_FOUND("Embed config not found at " + embed_config_path);
		}
		
		GLib.debug("Loading embed config from: %s", embed_config_path);
		var parser2 = new Json.Parser();
		parser2.load_from_file(embed_config_path);
		var obj2 = parser2.get_root().get_object();
	 
		var embed_client = new OLLMchat.Client(new OLLMchat.Config() {
			url = obj2.get_string_member("url"),
			model = obj2.get_string_member("model"),
			api_key = obj2.get_string_member("api-key")
		});
		embed_client.options = new OLLMchat.Call.Options() {
			temperature = 0.0,
			num_ctx = 2048
		};
		
		var model_info = @"Analysis Model: $(analysis_client.config.model)
Embed Model: $(embed_client.config.model)

";
		stdout.printf("%s", model_info);
		
		// Get dimension first, then create Database with it
		var dimension = yield OLLMvector.Database.get_embedding_dimension(embed_client);
		var vector_db = new OLLMvector.Database(embed_client, this.vector_db_path, dimension);
		
		GLib.debug("Using vector database: %s", this.vector_db_path);
		
		var indexer = new OLLMvector.Indexing.Indexer(
			analysis_client,
			embed_client,
			vector_db,
			sql_db,
			manager
		);
		
		indexer.progress.connect((current, total, file_path) => {
			int percentage = (int)((current * 100.0) / total);
			stdout.printf("\r%d/%d files %d%% done - %s", current, total, percentage, file_path);
		});
		
		stdout.printf("=== Indexing ===\n");
		
		// Look up FileBase object from database
		var results_list = new Gee.ArrayList<OLLMfiles.FileBase>();
		var query = OLLMfiles.FileBase.query(sql_db, manager);
		var stmt = query.selectPrepare(
				"SELECT " + string.joinv(",", query.getColsExcept(null)) +
					 " FROM filebase WHERE path = $path");
		stmt.bind_text(stmt.bind_parameter_index("$path"), abs_path);
		query.selectExecute(stmt, results_list);
		
		OLLMfiles.FileBase? filebase = null;
		if (results_list.size > 0) {
			filebase = results_list[0];
		}
		
		if (filebase == null) {
			stdout.printf("Path not found in database. Adding to database first...\n");
			
			var file_info_detailed = file.query_info("standard::*", GLib.FileQueryInfoFlags.NONE, null);
			
			if (is_folder) {
				var folder = new OLLMfiles.Folder(manager);
				folder.path = abs_path;
				var mod_time = file_info_detailed.get_modification_date_time();
				if (mod_time != null) {
					folder.last_modified = mod_time.to_unix();
				}
				folder.saveToDB(sql_db, null, false);
				stdout.printf("Added folder to database (ID: %lld)\n\n", folder.id);
				filebase = folder;
			} else {
				var ollm_file = new OLLMfiles.File(manager);
				ollm_file.path = abs_path;
				var mod_time = file_info_detailed.get_modification_date_time();
				if (mod_time != null) {
					ollm_file.last_modified = mod_time.to_unix();
				}
				var content_type = file_info_detailed.get_content_type();
				ollm_file.is_text = content_type != null && content_type != "" && content_type.has_prefix("text/");
				var detected_lang = manager.buffer_provider.detect_language(ollm_file);
				if (detected_lang != null && detected_lang != "") {
					ollm_file.language = detected_lang;
				}
				ollm_file.saveToDB(sql_db, null, false);
				stdout.printf("Added file to database (ID: %lld, Language: %s)\n\n", ollm_file.id, ollm_file.language);
				filebase = ollm_file;
			}
		}
		
		if (filebase != null) {
			stdout.printf("Starting indexing process...\n");
			if (filebase is OLLMfiles.Folder) {
				var folder_obj = (OLLMfiles.Folder)filebase;
				stdout.printf("Indexing folder: %s (recurse=%s)\n", folder_obj.path, opt_recurse.to_string());
			} else if (filebase is OLLMfiles.File) {
				var file_obj = (OLLMfiles.File)filebase;
				stdout.printf("Indexing file: %s\n", file_obj.path);
			}
			try {
				stdout.printf("Calling indexer.index_filebase...\n");
				int files_indexed = yield indexer.index_filebase(filebase, opt_recurse, false);
				stdout.printf("\n");
				stdout.printf("index_filebase returned: %d files indexed\n", files_indexed);
				var completion_info = @"✓ Indexing completed
  Files indexed: $(files_indexed)
  Total vectors: $(vector_db.vector_count)
  Vector dimension: $(vector_db.dimension)

";
				stdout.printf("%s", completion_info);
			} catch (GLib.Error e) {
				stdout.printf("Error during indexing: %s\n", e.message);
				throw e;
			}
		} else {
			throw new GLib.IOError.FAILED("Failed to get or create filebase entry");
		}
		
		try {
			vector_db.save_index();
			GLib.debug("Saved vector database: %s", this.vector_db_path);
		} catch (GLib.Error e) {
			GLib.warning("Failed to save vector database: %s", e.message);
		}
		
		var final_info = @"=== Indexing Complete ===
Database: $(this.db_path)
Vector database: $(this.vector_db_path)
";
		stdout.printf("%s", final_info);
	}
}

int main(string[] args)
{
	var app = new VectorIndexerApp();
	return app.run(args);
}
