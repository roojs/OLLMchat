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

namespace OLLMvector.Indexing
{
	public class ProjectAnalysis : VectorBase
	{
		private SQ.Database sql_db;
		private static PromptTemplate? project_template = null;
		private static PromptTemplate? dependencies_template = null;

		static construct
		{
			try {
				project_template = new PromptTemplate("analysis-prompt-project.txt");
				project_template.load();
				dependencies_template = new PromptTemplate("analysis-prompt-dependencies.txt");
				dependencies_template.load();
			} catch (GLib.Error e) {
				GLib.critical("Failed to load project/dependencies prompt templates: %s", e.message);
			}
		}

		public ProjectAnalysis(OLLMchat.Settings.Config2 config, SQ.Database sql_db)
		{
			base(config);
			this.sql_db = sql_db;
		}

		public async void extract_dependencies(OLLMfiles.Folder root_folder) throws GLib.Error
		{
			string[] file_ids = {};
			foreach (var pf in root_folder.project_files) {
				file_ids += pf.file.id.to_string();
			}
			if (file_ids.length == 0) {
				return;
			}
			var build_rows = new Gee.ArrayList<VectorMetadata>();
			yield VectorMetadata.query(this.sql_db).select_async(
				"WHERE file_id IN (" + string.joinv(",", file_ids) + ") AND category = 'build' AND element_type = 'file'",
				build_rows
			);
			if (build_rows.size == 0) {
				return;
			}
			string build_content = "";
			foreach (var m in build_rows) {
				var file = root_folder.project_files.get_by_id(m.file_id);
				if (file == null) {
					continue;
				}
				string content = "";
				try {
					content = file.get_contents(0);
				} catch (GLib.Error e) {
					GLib.warning("ProjectAnalysis: could not read build file %s: %s", file.path, e.message);
					continue;
				}
				build_content += "\n--- FILE: " + file.path + " ---\n" + content;
			}
			if (build_content.strip() == "") {
				return;
			}
			var user_message = dependencies_template.fill(
				"build_file_content", build_content.strip()
			);
			var messages = new Gee.ArrayList<OLLMchat.Message>();
			messages.add(new OLLMchat.Message("system", dependencies_template.system_message));
			messages.add(new OLLMchat.Message("user", user_message));
			string raw_response = "";
			try {
				raw_response = yield this.request_analysis(messages);
			} catch (GLib.Error e) {
				GLib.warning("ProjectAnalysis: extract_dependencies LLM failed: %s", e.message);
				return;
			}
			var deps_meta = new VectorMetadata() {
				element_type = "dependencies",
				element_name = "dependencies",
				start_line = 0,
				end_line = 0,
				description = raw_response.strip(),
				file_id = root_folder.id,
				vector_id = 0,
				ast_path = ""
			};
			deps_meta.saveToDB(this.sql_db, false);
			this.sql_db.backupDB();
		}

		public async VectorMetadata analyze(OLLMfiles.Folder root_folder) throws GLib.Error
		{
			var metadata_keymap = new Gee.HashMap<int, VectorMetadata>();
			string[] folder_lines = {};
			foreach (var folder in root_folder.project_files.folder_map.values) {
				var name = GLib.Path.get_basename(folder.path);
				if (!metadata_keymap.has_key((int)folder.id)) {
					folder_lines += "  - (folder) " + name;
					continue;
				}
				var vm = metadata_keymap.get((int)folder.id);
				if (vm.description == "") {
					folder_lines += "  - (folder) " + name;
					continue;
				}
				folder_lines += "  - (folder) " + name + ": " + vm.description;
			}
			string[] file_lines = {};
			foreach (var pf in root_folder.project_files) {
				var name = GLib.Path.get_basename(pf.file.path);
				if (!metadata_keymap.has_key((int)pf.file.id)) {
					file_lines += "  - (file) " + name;
					continue;
				}
				var vm = metadata_keymap.get((int)pf.file.id);
				if (vm.description == "") {
					file_lines += "  - (file) " + name;
					continue;
				}
				file_lines += "  - (file) " + name + ": " + vm.description;
			}
			string folders_and_files_list = string.joinv("\n", folder_lines) + "\n" + string.joinv("\n", file_lines);
			var user_message = project_template.fill(
				"project_path", root_folder.path != "" ? root_folder.path : "unknown",
				"folders_and_files_list", folders_and_files_list.strip()
			);
			var messages = new Gee.ArrayList<OLLMchat.Message>();
			messages.add(new OLLMchat.Message("system", project_template.system_message));
			messages.add(new OLLMchat.Message("user", user_message));
			string raw_response = "";
			try {
				raw_response = yield this.request_analysis(messages);
			} catch (GLib.Error e) {
				GLib.warning("ProjectAnalysis: analyze LLM failed: %s", e.message);
				return new VectorMetadata() {
					element_type = "project",
					element_name = GLib.Path.get_basename(root_folder.path),
					start_line = 0,
					end_line = 0,
					description = "",
					file_id = root_folder.id,
					vector_id = 0,
					ast_path = ""
				};
			}
			var project_meta = new VectorMetadata() {
				element_type = "project",
				element_name = GLib.Path.get_basename(root_folder.path),
				start_line = 0,
				end_line = 0,
				description = raw_response.strip(),
				file_id = root_folder.id,
				vector_id = 0,
				ast_path = ""
			};
			project_meta.saveToDB(this.sql_db, false);
			this.sql_db.backupDB();
			return project_meta;
		}
	}
}
