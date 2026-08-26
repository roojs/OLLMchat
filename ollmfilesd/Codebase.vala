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

namespace OLLMfilesd
{
	/**
	 * Server ''Codebase.*'' wire handlers — vector search, per-file metadata,
	 * debug embedding dump, database reset, and background index queue control.
	 *
	 * Registered once in {@link OllmfilesdApplication}. Arguments arrive on
	 * {@link OLLMrpc.Request.args}. See {@link OLLMrpc.Request.dispatch} for
	 * signal routing.
	 */
	public class Codebase : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Codebase", typeof(Codebase),
				"file_info", "s",
				"reset", "",
				"start", "ss",
				"stop", "",
				"rpc_search", "ssissss",
				"rpc_debug_get", "ss"
			);
		}

		public ProjectManager manager { get; construct; }
		public OLLMchat.Settings.Config2 config { get; construct; }

		private static string[] VALID_CATEGORIES = {
			"plan",
			"documentation",
			"rule",
			"configuration",
			"data",
			"license",
			"changelog",
			"other"
		};

		public Codebase(
			ProjectManager manager,
			OLLMchat.Settings.Config2 config
		)
		{
			GLib.Object(manager: manager, config: config);
		}

		/**
		 * ''Codebase.rpc_search'' — semantic vector search over the
		 * active project.
		 *
		 * Reply ''msg'' with markdown when ''format=tool'', or explanatory
		 * text when filters match nothing. ''response.error'' when the
		 * client cannot know the outcome (e.g. no active project).
		 *
		 * @param request inbound RPC
		 * @param path project path
		 * @param query search text
		 * @param max_results cap
		 * @param language language filter
		 * @param element_type element-type filter
		 * @param category category filter
		 * @param format ''tool'' or other
		 */
		public void rpc_search(
			OLLMrpc.Request request,
			string path, string query, int max_results,
			string language, string element_type, string category,
			string format
		) {
			this.search.begin(request, (obj, res) => {
				this.search.end(res);
			});
		}

		/**
		 * ''Codebase.rpc_debug_get'' — dump stored FAISS embedding for
		 * one AST path.
		 *
		 * Debug/admin only; CLI: ''oc-vector-search --dump-vector=AST_PATH''.
		 * Reply: ''msg'' with one float per line.
		 *
		 * @param request inbound RPC
		 * @param path project path
		 * @param ast_path AST path to dump
		 */
		public void rpc_debug_get(
			OLLMrpc.Request request,
			string path,
			string ast_path
		) {
			this.debug_get.begin(request, (obj, res) => {
				this.debug_get.end(res);
			});
		}

		/**
		 * ''Codebase.file_info'' — {@link SQT.VectorMetadata} rows for one file.
		 *
		 * Reply: ''result'' list (empty when the file is missing or not indexed)
		 * and ''msg'' row count — not an error.
		 *
		 * @param request inbound RPC
		 * @param file_path indexed file path
		 */
		public void file_info(OLLMrpc.Request request, string file_path)
		{
			var list = new Gee.ArrayList<GLib.Object>();
			var indexed = this.manager.get_file_from_active_project(file_path);
			if (indexed != null && indexed.id > 0) {
				var rows = new Gee.ArrayList<SQT.VectorMetadata>();
				SQT.VectorMetadata.query(
					this.manager.db
				).select(
					"WHERE file_id = " + indexed.id.to_string(),
					rows
				);
				foreach (var row in rows) {
					list.add(row);
				}
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				result = list,
				msg = list.size.to_string()
			});
		}

		/**
		 * ''Codebase.reset'' — wipe FAISS file, vector metadata, and scan dates.
		 *
		 * CLI: ''oc-vector-index --reset-database''. Reply ''msg'': ''ok''
		 * on success. ''response.error'' when reset I/O fails.
		 *
		 *  * Domain / I/O failure → ''response.error''
		 *  * Client API bugs propagate; no catch-all on this method
		 *
		 * @param request inbound RPC; no extra args
		 */
		public void reset(OLLMrpc.Request request)
		{
			try {
				OLLMvector2.SQT.VectorMetadata.reset_database(
					this.manager.db,
					this.manager.vector_db_path
				);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						e.message
					)
				});
				return;
			}
			this.manager.vector_scan.open_vector_db.begin((obj, res) => {
				try {
					this.manager.vector_scan.open_vector_db.end(res);
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error(
							OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
							e.message
						)
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "ok"
				});
			});
		}

		/**
		 * ''Codebase.start'' — enqueue stale files from DB and run the queue.
		 * Clears {@link OLLMfilesd.Vector.BackgroundScan.stop_requested} from a
		 * prior ''Codebase.stop''. ''path'' must already exist (CLI scans via
		 * ''ProjectManager.activate_project'' first).
		 *
		 * @param request inbound RPC
		 * @param path project path
		 * @param only_file optional single-file filter; empty string if unused
		 */
		public void start(OLLMrpc.Request request, string path, string only_file)
		{
			var scan = this.manager.vector_scan;
			scan.stop_requested = false;
			scan.queueProject.begin(
				path,
				only_file,
				true,
				(obj, res) => {
					var queued_count = scan.queueProject.end(res);
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = queued_count > 0
							? queued_count.to_string()
							: "ok"
					});
				}
			);
		}

		/**
		 * ''Codebase.stop'' — pause indexing after the current file; queue
		 * entries are preserved.
		 *
		 * @param request inbound RPC; no extra args
		 */
		public void stop(OLLMrpc.Request request)
		{
			this.manager.vector_scan.stop_requested = true;
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = "ok"
			});
		}

		/**
		 * ''Codebase.search'' handler — filter ''vector_metadata'', run FAISS
		 * {@link OLLMvector2.Search}, reply markdown in {@link OLLMrpc.Response.msg}.
		 *
		 * @param request inbound RPC; search fields on {@link OLLMrpc.Request.args}
		 */
		private async void search(OLLMrpc.Request request)
		{
			var path = request.args.get(0).get_string();
			var query = request.args.get(1).get_string();
			var max_results_arg = request.args.get(2).get_int();
			var language = request.args.get(3).get_string();
			var element_type = request.args.get(4).get_string();
			var category = request.args.get(5).get_string();
			var format = request.args.get(6).get_string();
			var project = this.manager.project_root(path);
			if (project == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"No active project. Please open a project first."
					)
				});
				return;
			}

			if (element_type.strip().down() == "project") {
				var description = project.project_description();
				if (description == "") {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = "No project summary is indexed yet for this project."
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "## Project summary\n\n" + description
				});
				return;
			}

			if (project.project_files.get_n_items() == 0) {
				yield project.load_files_from_db();
			}

			var file_ids = project.project_files.get_ids(language);

			if (file_ids.size == 0) {
				if (language != "") {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = "No files in the project match the language filter \""
							+ language + "\". "
							+ "Try the same query without the language parameter to search all languages, or use a different language."
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "No files found in the project folder. Check that the project is open and has indexed files."
				});
				return;
			}

			var filtered_vector_ids = new Gee.ArrayList<int>();

			var sql = "SELECT DISTINCT vector_id FROM vector_metadata WHERE file_id IN ("
				+ string.joinv(",", file_ids.to_array()) + ")";

			var search_both_function_and_method = false;
			if (element_type != "") {
				var normalized_type = element_type.strip().down();
				if (normalized_type == "function" || normalized_type == "method") {
					sql = sql + " AND element_type IN ('function', 'method')";
					search_both_function_and_method = true;
				} else {
					sql = sql + " AND element_type = $element_type";
				}
			}
			if (category != "") {
				sql = sql + " AND file_id IN "
					+ "(SELECT file_id FROM vector_metadata fvm WHERE fvm.category = $category) "
					+ "AND element_type IN ('document','section')";
			}

			GLib.debug(
				"codebase_search vector filter: file_ids_count=%d, element_type='%s', category='%s', sql='%s'",
				file_ids.size,
				element_type != "" ? element_type : "none",
				category != "" ? category : "none",
				sql
			);

			var vector_query = OLLMvector2.SQT.VectorMetadata.query(this.manager.db);
			var vector_stmt = vector_query.selectPrepare(sql);

			if (element_type != "" && !search_both_function_and_method) {
				vector_stmt.bind_text(
					vector_stmt.bind_parameter_index("$element_type"),
					element_type
				);
			}
			if (category != "") {
				vector_stmt.bind_text(
					vector_stmt.bind_parameter_index("$category"),
					category
				);
			}

			foreach (var vector_id_str in vector_query.fetchAllString(vector_stmt)) {
				filtered_vector_ids.add((int) int64.parse(vector_id_str));
			}

			GLib.debug(
				"codebase_search vector filter: found %d vector_id(s) matching filter",
				filtered_vector_ids.size
			);

			if (filtered_vector_ids.size == 0) {
				if (category != "") {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = "No document matches the criteria (category=\""
							+ category + "\"). "
							+ "Try the same query without the category filter to search all docs, "
							+ "or use a different category. Valid categories: "
							+ string.joinv(", ", VALID_CATEGORIES) + "."
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "No document matches the criteria (current filters returned no indexed content). "
						+ "Try the same query with fewer or different filters (e.g. omit element_type), "
						+ "or broaden the query."
				});
				return;
			}

			var filter_array = new int64[filtered_vector_ids.size];
			for (var i = 0; i < filtered_vector_ids.size; i++) {
				filter_array[i] = filtered_vector_ids.get(i);
			}

			var max_results = (uint64) (max_results_arg > 0 ? max_results_arg : 10);
			var vector_search = new OLLMvector2.Search(
				this.manager.vector_db,
				this.manager.db,
				this.config
			) {
				query = query,
				max_results = max_results
			};

			var hits = yield vector_search.execute(filter_array);

			GLib.debug(
				"codebase_search output: found %d result(s) for query '%s'",
				hits.size,
				query
			);

			var results = new Gee.ArrayList<Vector.SearchResult>();
			foreach (var hit in hits) {
				results.add(new Vector.SearchResult(
					project,
					hit.faiss.vector_id,
					hit.faiss.distance,
					hit.metadata
				));
			}

			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = format == "json"
					? yield this.format_results_json(results)
					: yield this.format_results(results)
			});
		}

		/**
		 * Build markdown for {@link OLLMrpc.Response.msg} from FAISS hits.
		 *
		 * Loads each result file buffer so {@link Vector.SearchResult.to_markdown}
		 * can include code snippets.
		 *
		 * @param results wrapped search hits
		 * @return markdown body for the RPC reply
		 */
		private async string format_results(
			Gee.ArrayList<Vector.SearchResult> results
		)
		{
			if (results.size == 0) {
				return "No results found.";
			}
			const int max_snippet_lines = 50;
			foreach (var result in results) {
				var file = result.file();
				file.manager.buffer_provider.create_buffer(file);
				if (file.buffer.is_loaded) {
					continue;
				}
				try {
					yield file.buffer.read_async();
				} catch (GLib.Error e) {
					GLib.debug(
						"codebase_search format: Failed to load %s: %s",
						file.path,
						e.message
					);
				}
			}
			var output = "Found %d result(s):\n\n".printf(results.size);
			foreach (var result in results) {
				output += result.to_markdown(max_snippet_lines);
			}
			return output;
		}

		/**
		 * JSON array of search hits for format ''json''.
		 */
		private async string format_results_json(
			Gee.ArrayList<Vector.SearchResult> results
		)
		{
			if (results.size == 0) {
				return "[]";
			}
			const int max_snippet_lines = 50;
			foreach (var result in results) {
				var file = result.file();
				file.manager.buffer_provider.create_buffer(file);
				if (file.buffer.is_loaded) {
					continue;
				}
				try {
					yield file.buffer.read_async();
				} catch (GLib.Error e) {
					GLib.debug(
						"codebase_search json: Failed to load %s: %s",
						file.path,
						e.message
					);
				}
			}
			var json_array = new Json.Array();
			foreach (var result in results) {
				var file = result.file();
				var meta = result.metadata;
				var builder = new Json.Builder();
				builder.begin_object();
				builder.set_member_name("distance");
				builder.add_double_value(result.distance);
				builder.set_member_name("file");
				builder.add_string_value(file != null ? file.path : "");
				builder.set_member_name("element_name");
				builder.add_string_value(meta.element_name);
				builder.set_member_name("element_type");
				builder.add_string_value(meta.element_type);
				builder.set_member_name("start_line");
				builder.add_int_value(meta.start_line);
				builder.set_member_name("end_line");
				builder.add_int_value(meta.end_line);
				builder.set_member_name("ast_path");
				builder.add_string_value(meta.ast_path);
				builder.set_member_name("category");
				builder.add_string_value(meta.category);
				builder.set_member_name("description");
				builder.add_string_value(meta.description);
				builder.set_member_name("snippet");
				builder.add_string_value(result.code_snippet(max_snippet_lines));
				builder.end_object();
				json_array.add_element(builder.get_root());
			}
			var root = new Json.Node.alloc().init_array(json_array);
			var generator = new Json.Generator();
			generator.set_root(root);
			generator.set_pretty(true);
			generator.set_indent(2);
			return generator.to_data(null);
		}

		/**
		 * ''Codebase.debug_get'' handler — resolve ''ast_path'' to
		 * ''vector_id'', reconstruct from FAISS, reply one float per line in
		 * {@link OLLMrpc.Response.msg}.
		 *
		 * @param request inbound RPC; path and ast_path on {@link OLLMrpc.Request.args}
		 */
		private async void debug_get(OLLMrpc.Request request)
		{
			var path = request.args.get(0).get_string();
			var ast_path = request.args.get(1).get_string();
			if (ast_path == "") {
				GLib.error("RPC-Codebase.debug_get: ast_path is required");
			}
			var project = this.manager.project_root(path);
			if (project == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"No active project. Please open a project first."
					)
				});
				return;
			}

			if (project.project_files.get_n_items() == 0) {
				yield project.load_files_from_db();
			}

			var file_ids = project.project_files.get_ids("");
			if (file_ids.size == 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"No files found in folder"
					)
				});
				return;
			}

			var rows = new Gee.ArrayList<SQT.VectorMetadata>();
			SQT.VectorMetadata.query(this.manager.db).select(
				"WHERE file_id IN (" + string.joinv(",", file_ids.to_array())
					+ ") AND ast_path = '" + ast_path.replace("'", "''")
					+ "' ORDER BY id DESC LIMIT 1",
				rows
			);
			if (rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"No vector found for AST path: " + ast_path
					)
				});
				return;
			}

			float[] vector;
			try {
				vector = this.manager.vector_db.reconstruct_vector(
					rows.get(0).vector_id
				);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						e.message
					)
				});
				return;
			}
			// Embed dimension is hundreds of floats — StringBuilder exception.
			var output = new StringBuilder();
			for (var i = 0; i < vector.length; i++) {
				output.append_printf("%.9g\n", vector[i]);
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = output.str
			});
		}
	}
}
