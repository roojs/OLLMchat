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
	/** Server {@code Codebase.*} — semantic codebase search for tools. */
	public class Codebase : GLib.Object
	{
		public static void rpc_register()
		{
			VectorParams.rpc_register();
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

		public signal void call_search(OLLMrpc.Request request);

		construct
		{
			this.call_search.connect((request) => {
				this.search.begin(request, (obj, res) => {
					try {
						this.search.end(res);
					} catch (GLib.Error e) {
						request.reply(new OLLMrpc.Response() {
							id = request.id,
							error = new OLLMrpc.Error(
								OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
								e.message
							)
						});
					}
				});
			});
		}

		private async void search(OLLMrpc.Request request) throws GLib.Error
		{
			var p = (VectorParams) request.param;
			var project = this.manager.project_root(p.path);
			if (project == null) {
				throw new GLib.IOError.FAILED(
					"No active project. Please open a project first."
				);
			}

			if (this.manager.db == null) {
				throw new GLib.IOError.FAILED("Database not available");
			}
			if (this.manager.vector_db == null) {
				throw new GLib.IOError.FAILED("Vector database not available");
			}

			if (project.project_files.get_n_items() == 0) {
				yield project.load_files_from_db();
			}

			var file_ids = project.project_files.get_ids(p.language);

			if (file_ids.size == 0) {
				if (p.language != "") {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = "No files in the project match the language filter \""
							+ p.language + "\". "
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
			if (p.element_type != "") {
				var normalized_type = p.element_type.strip().down();
				if (normalized_type == "function" || normalized_type == "method") {
					sql = sql + " AND element_type IN ('function', 'method')";
					search_both_function_and_method = true;
				} else {
					sql = sql + " AND element_type = $element_type";
				}
			}
			if (p.category != "") {
				sql = sql + " AND file_id IN "
					+ "(SELECT file_id FROM vector_metadata fvm WHERE fvm.category = $category) "
					+ "AND element_type IN ('document','section')";
			}

			GLib.debug(
				"codebase_search vector filter: file_ids_count=%d, element_type='%s', category='%s', sql='%s'",
				file_ids.size,
				p.element_type != "" ? p.element_type : "none",
				p.category != "" ? p.category : "none",
				sql
			);

			var vector_query = OLLMvector2.SQT.VectorMetadata.query(this.manager.db);
			var vector_stmt = vector_query.selectPrepare(sql);

			if (p.element_type != "" && !search_both_function_and_method) {
				vector_stmt.bind_text(
					vector_stmt.bind_parameter_index("$element_type"),
					p.element_type
				);
			}
			if (p.category != "") {
				vector_stmt.bind_text(
					vector_stmt.bind_parameter_index("$category"),
					p.category
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
				if (p.category != "") {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = "No document matches the criteria (category=\""
							+ p.category + "\"). "
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

			var max_results = (uint64) (p.max_results > 0 ? p.max_results : 10);
			var vector_search = new OLLMvector2.Search(
				this.manager.vector_db,
				this.manager.db,
				this.config
			) {
				query = p.query,
				max_results = max_results
			};

			var hits = yield vector_search.execute(filter_array);

			GLib.debug(
				"codebase_search output: found %d result(s) for query '%s'",
				hits.size,
				p.query
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
				msg = yield this.format_results(results)
			});
		}

		/**
		 * Format search results for LLM consumption using SearchResult.to_markdown().
		 * Loads each result's file buffer so code snippets are populated.
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
			var output = new StringBuilder();
			output.append_printf("Found %d result(s):\n\n", results.size);
			foreach (var result in results) {
				output.append(result.to_markdown(max_snippet_lines));
			}
			return output.str;
		}
	}
}
