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
		private OLLMfiles.Folder root_folder;
		private static PromptTemplate? project_template = null;
		private static PromptTemplate? dependencies_template = null;

		/**
		 * Id-indexed map of file/folder metadata used by analyze().
		 * Caller may set (e.g. from FolderAnalysis.analyze_children) before calling analyze();
		 * if unset or empty, analyze() builds the keymap from DB.
		 */
		public Gee.HashMap<int, OLLMfiles.SQT.VectorMetadata> metadata_keymap {
			 get; set; default = new Gee.HashMap<int, OLLMfiles.SQT.VectorMetadata>(); }

		static construct
		{
			project_template = new PromptTemplate("analysis-prompt-project.txt");
			project_template.load();
			dependencies_template = new PromptTemplate("analysis-prompt-dependencies.txt");
			dependencies_template.load();
		}

		public ProjectAnalysis(OLLMchat.Settings.Config2 config, SQ.Database sql_db, OLLMfiles.Folder root_folder)
		{
			base(config);
			this.sql_db = sql_db;
			this.root_folder = root_folder;
		}

		public async void analyze_dependencies() throws GLib.Error
		{
			string[] file_ids = {};
			foreach (var pf in this.root_folder.project_files) {
				file_ids += pf.file.id.to_string();
			}
			if (file_ids.length == 0) {
				return;
			}
			var build_rows = new Gee.ArrayList<OLLMfiles.SQT.VectorMetadata>();
			yield OLLMfiles.SQT.VectorMetadata.query(this.sql_db).select_async(
				"WHERE file_id IN (" + string.joinv(",", file_ids) + ") AND category = 'build' AND element_type = 'file'",
				build_rows
			);
			if (build_rows.size == 0) {
				return;
			}
			string build_content = "";
			foreach (var m in build_rows) {
				var file = this.root_folder.project_files.get_by_id(m.file_id);
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
				var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
				raw_response = yield this.request_analysis(messages, tool_config.analysis);
			} catch (GLib.Error e) {
				GLib.warning("ProjectAnalysis: analyze_dependencies LLM failed: %s", e.message);
				return;
			}
			var deps_meta = new OLLMfiles.SQT.VectorMetadata() {
				element_type = "dependencies",
				element_name = "dependencies",
				start_line = 0,
				end_line = 0,
				description = raw_response.strip(),
				file_id = this.root_folder.id,
				vector_id = 0,
				ast_path = ""
			};
			deps_meta.saveToDB(this.sql_db, false);
			this.sql_db.backupDB();
		}

		private async Gee.HashMap<int, OLLMfiles.SQT.VectorMetadata> build_keymap() throws GLib.Error
		{
			if (this.metadata_keymap != null && this.metadata_keymap.size > 0) {
				return this.metadata_keymap;
			}
			var keymap = new Gee.HashMap<int, OLLMfiles.SQT.VectorMetadata>();
			string[] id_strs = {};
			foreach (var folder in this.root_folder.project_files.folder_map.values) {
				id_strs += folder.id.to_string();
			}
			foreach (var pf in this.root_folder.project_files) {
				id_strs += pf.file.id.to_string();
			}
			if (id_strs.length == 0) {
				return keymap;
			}
			var rows = new Gee.ArrayList<OLLMfiles.SQT.VectorMetadata>();
			yield OLLMfiles.SQT.VectorMetadata.query(this.sql_db).select_async(
				"WHERE file_id IN (" + string.joinv(",", id_strs) + ") AND (element_type = 'file' OR element_type = 'folder')",
				rows
			);
			foreach (var m in rows) {
				keymap[(int)m.file_id] = m;
			}
			return keymap;
		}

		public async OLLMfiles.SQT.VectorMetadata analyze() throws GLib.Error
		{
			var keymap = yield this.build_keymap();
			if (keymap.size == 0) {
				return new OLLMfiles.SQT.VectorMetadata() {
					element_type = "project",
					element_name = GLib.Path.get_basename(this.root_folder.path),
					start_line = 0,
					end_line = 0,
					description = "",
					file_id = this.root_folder.id,
					vector_id = 0,
					ast_path = ""
				};
			}
			string[] folder_lines = {};
			foreach (var folder in this.root_folder.project_files.folder_map.values) {
				var name = GLib.Path.get_basename(folder.path);
				if (!keymap.has_key((int)folder.id)) {
					folder_lines += "  - (folder) " + name;
					continue;
				}
				var vm = keymap.get((int)folder.id);
				if (vm.description == "") {
					folder_lines += "  - (folder) " + name;
					continue;
				}
				folder_lines += "  - (folder) " + name + ": " + vm.description;
			}
			string[] file_lines = {};
			foreach (var pf in this.root_folder.project_files) {
				var name = GLib.Path.get_basename(pf.file.path);
				if (!keymap.has_key((int)pf.file.id)) {
					file_lines += "  - (file) " + name;
					continue;
				}
				var vm = keymap.get((int)pf.file.id);
				if (vm.description == "") {
					file_lines += "  - (file) " + name;
					continue;
				}
				file_lines += "  - (file) " + name + ": " + vm.description;
			}
			string folders_and_files_list = string.joinv("\n", folder_lines) + "\n" + string.joinv("\n", file_lines);
			var user_message = project_template.fill(
				"project_path", this.root_folder.path != "" ? this.root_folder.path : "unknown",
				"folders_and_files_list", folders_and_files_list.strip()
			);
			var messages = new Gee.ArrayList<OLLMchat.Message>();
			messages.add(new OLLMchat.Message("system", project_template.system_message));
			messages.add(new OLLMchat.Message("user", user_message));
			string raw_response = "";
			try {
				var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
				raw_response = yield this.request_analysis(messages, tool_config.analysis);
			} catch (GLib.Error e) {
				GLib.warning("ProjectAnalysis: analyze LLM failed: %s", e.message);
				return new OLLMfiles.SQT.VectorMetadata() {
					element_type = "project",
					element_name = GLib.Path.get_basename(this.root_folder.path),
					start_line = 0,
					end_line = 0,
					description = "",
					file_id = this.root_folder.id,
					vector_id = 0,
					ast_path = ""
				};
			}
			var project_meta = new OLLMfiles.SQT.VectorMetadata() {
				element_type = "project",
				element_name = GLib.Path.get_basename(this.root_folder.path),
				start_line = 0,
				end_line = 0,
				description = raw_response.strip(),
				file_id = this.root_folder.id,
				vector_id = 0,
				ast_path = ""
			};
			project_meta.saveToDB(this.sql_db, false);
			this.sql_db.backupDB();
			return project_meta;
		}
	}
}
