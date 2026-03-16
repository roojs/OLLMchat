/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, see <https://www.gnu.org/licenses/>.
 */

namespace OLLMtools.WriteFile
{
	public class Request : OLLMchat.Tool.RequestBase
	{
		public string file_path { get; set; default = ""; }
		public string content { get; set; default = ""; }
		public string ast_path { get; set; default = ""; }
		public string location { get; set; default = ""; }
		public int start_line { get; set; default = -1; }
		public int end_line { get; set; default = -1; }
		public bool complete_file { get; set; default = false; }
		public bool overwrite { get; set; default = false; }

		internal string normalized_path = "";
		internal bool creating_file = false;
		private bool history_created = false;
		private OLLMfiles.File? file = null;

		public Request()
		{
		}

		protected override string normalize_file_path(string in_path)
		{
			var project_manager = ((Tool) this.tool).project_manager;
			if (project_manager != null && project_manager.active_project != null) {
				if (!GLib.Path.is_absolute(in_path)) {
					return GLib.Path.build_filename(project_manager.active_project.path, in_path);
				}
			}
			return base.normalize_file_path(in_path);
		}

		protected override bool build_perm_question()
		{
			if (this.file_path == "") {
				return false;
			}
			this.normalized_path = this.normalize_file_path(this.file_path);
			this.permission_target_path = this.normalized_path;
			this.permission_operation = OLLMchat.ChatPermission.Operation.WRITE;
			this.permission_question = "Write to file '" + this.normalized_path + "'?";
			var project_manager = ((Tool) this.tool).project_manager;
			if (project_manager.get_file_from_active_project(this.normalized_path) != null) {
				this.permission_question = "";
				return false;
			}
			if (project_manager.active_project != null) {
				var dir_path = GLib.Path.get_dirname(this.normalized_path);
				if (project_manager.active_project.project_files.folder_map.has_key(dir_path)) {
					this.permission_question = "";
					return false;
				}
			}
			return true;
		}

		private async void file_history() throws Error
		{
			if (this.history_created) {
				return;
			}
			var change_type = this.creating_file ? "added" : "modified";
			if (change_type != "added" && this.creating_file) {
				return;
			}
			var project_manager = ((Tool) this.tool).project_manager;
			try {
				var fh = new OLLMfiles.FileHistory(
					project_manager.db,
					this.file,
					change_type,
					new GLib.DateTime.now_local()
				);
				yield fh.commit();
				this.history_created = true;
			} catch (GLib.Error e) {
				GLib.warning("Cannot create FileHistory for write_file (%s): %s",
					this.normalized_path, e.message);
			}
		}

		protected override async string execute_request() throws Error
		{
			var err = yield OLLMtools.WriteFile.Tool.validate(
				((Tool) this.tool).project_manager,
				this.file_path,
				this.content,
				this.ast_path,
				this.location,
				this.start_line,
				this.end_line,
				this.complete_file,
				this.overwrite
			);
			if (err != "") {
				throw new GLib.IOError.INVALID_ARGUMENT(err);
			}
			var project_manager = ((Tool) this.tool).project_manager;
			if (project_manager == null) {
				throw new GLib.IOError.FAILED("ProjectManager is not available");
			}
			this.normalized_path = this.normalize_file_path(this.file_path);
			this.file = project_manager.get_file_from_active_project(this.normalized_path);
			if (this.file == null) {
				this.file = new OLLMfiles.File.new_fake(project_manager, this.normalized_path);
			}
			this.creating_file = !GLib.FileUtils.test(
				this.normalized_path, GLib.FileTest.IS_REGULAR);
			if (this.complete_file && !this.creating_file && !this.overwrite) {
				throw new GLib.IOError.EXISTS(
					"File already exists: " + this.normalized_path + ". Use overwrite=true to overwrite.");
			}

			OLLMfiles.FileChange change;
			if (this.complete_file) {
				change = new OLLMfiles.FileChange(this.file) { replacement = this.content };
			} else if (this.start_line >= 1 && this.end_line >= this.start_line) {
				change = new OLLMfiles.FileChange(this.file) {
					start = this.start_line,
					end = this.end_line,
					replacement = this.content
				};
			} else {
				var operation_type = OLLMfiles.OperationType.REPLACE;
				var include_comments = false;
				switch (this.location) {
					case "":
					case "replace":
						break;
					case "replace-with-comment":
					case "with-comment":
						include_comments = true;
						break;
					case "before":
						operation_type = OLLMfiles.OperationType.BEFORE;
						break;
					case "after":
						operation_type = OLLMfiles.OperationType.AFTER;
						break;
					case "remove":
						operation_type = OLLMfiles.OperationType.DELETE;
						include_comments = true;
						break;
					case "before-comment":
						operation_type = OLLMfiles.OperationType.BEFORE;
						include_comments = true;
						break;
					default:
						throw new GLib.IOError.INVALID_ARGUMENT(
							"location must be one of: replace, replace-with-comment, before, after, remove, before-comment");
				}
				change = new OLLMfiles.FileChange(this.file) {
					ast_path = this.ast_path.strip(),
					operation_type = operation_type,
					include_comments = include_comments,
					replacement = this.content
				};
			}

			project_manager.buffer_provider.create_buffer(this.file);
			if (!this.file.buffer.is_loaded) {
				try {
					yield this.file.buffer.read_async();
				} catch (GLib.Error e) {
					throw new GLib.IOError.FAILED("Failed to read file: " + e.message);
				}
			}
			var change_type = this.creating_file ? "added" : "modified";
			yield this.file_history();
			if (this.ast_path.strip() != "") {
				yield change.resolve_ast_path();
			}
			yield change.apply_change(this.complete_file);
			if (change.result != "applied") {
				var msg = change.result != "" ? change.result : "Change was not applied";
				throw new GLib.IOError.FAILED(msg);
			}

			var is_in_project = (this.file.id > 0);
			if (!is_in_project && project_manager.active_project != null) {
				var dir_path = GLib.Path.get_dirname(this.normalized_path);
				if (project_manager.active_project.project_files.folder_map.has_key(dir_path)) {
					is_in_project = true;
				}
			}
			try {
				yield this.file.buffer.sync_to_file();
			} catch (GLib.IOError e) {
				if (e is GLib.IOError.NOT_SUPPORTED) {
					var contents = this.file.buffer.get_text();
					yield this.file.buffer.write(contents);
				} else {
					throw e;
				}
			}
			this.agent.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced("text.oc-frame-success.collapsed Write File",
				"Successfully wrote file: " + this.normalized_path + "\nProject file: " + (is_in_project ? "yes" : "no"))));
			if (change_type == "added" && this.file.id <= 0 && is_in_project) {
				yield project_manager.convert_fake_file_to_real(this.file, this.normalized_path);
				this.file = project_manager.get_file_from_active_project(this.normalized_path);
				if (this.file != null) {
					project_manager.active_project.project_files.update_from(
						project_manager.active_project);
				}
			}
			yield this.file_history();
			this.file.is_need_approval = true;
			this.file.last_change_type = change_type;
			this.file.last_modified = new GLib.DateTime.now_local().to_unix();
			if (is_in_project || this.file.id > 0) {
				this.file.saveToDB(project_manager.db, null, false);
			}
			if (is_in_project) {
				project_manager.active_project.project_files.review_files.refresh();
			}
			project_manager.db.backupDB();
			this.creating_file = false;
			((Tool) this.tool).change_done(this.normalized_path, change);
			var lines = this.file.buffer.get_text().split("\n");
			return "File '" + this.normalized_path + "' written. " +
				lines.length.to_string() + " lines.";
		}
	}
}
