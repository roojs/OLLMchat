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
		/**
		 * Literal excerpt to find in an existing file when using
		 * search/replace mode. Mutually exclusive with ast_path line
		 * range and complete_file; use with {{{content}}} as the
		 * replacement. Empty when not using this mode.
		 */
		public string search_text { get; set; default = ""; }
		public string ast_path { get; set; default = ""; }
		public string location { get; set; default = ""; }
		public int start_line { get; set; default = -1; }
		public int end_line { get; set; default = -1; }
		public bool complete_file { get; set; default = false; }
		public bool overwrite { get; set; default = false; }

		internal string normalized_path = "";
		internal bool creating_file = false;
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

		public override string to_summary ()
		{
			if (this.file_path.strip () == "") {
				return "";
			}
			var norm = this.tool != null ? this.normalize_file_path (this.file_path) : this.file_path;
			string[] lines = {};
			lines += "File: " + norm;
			if (this.ast_path.strip () != "") {
				lines += "AST path: " + this.ast_path;
			} else if (this.start_line >= 1 && this.end_line >= this.start_line) {
				lines += "Lines: %d-%d".printf (this.start_line, this.end_line);
			} else if (this.complete_file) {
				lines += "Mode: complete file";
			} else if (this.search_text.strip () != "") {
				lines += "Mode: search/replace";
			}
			if (this.overwrite) {
				lines += "Overwrite: yes";
			}
			return string.joinv ("\n", lines);
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
			// Check if file is already in the project index (skip permission prompt if so)
			if (project_manager.file_cache.has_key(this.normalized_path)) {
				this.permission_question = "";
				return false;
			}
			// Check if file path is within project folder (even if file doesn't exist yet)
			if (project_manager.active_project != null) {
				var project_path = project_manager.active_project.path;
				var dir_path = GLib.Path.get_dirname(this.normalized_path);
				// V2: path-under-project check (shipping used project_files.folder_map)
				if (
					dir_path == project_path
					|| dir_path.has_prefix(project_path + "/")
				) {
					this.permission_question = "";
					return false;
				}
			}
			return true;
		}

		/**
		 * Structure, file existence (modify modes when project_manager is set),
		 * and AST resolution for ast_path mode. Returns "" if valid.
		 */
		private async string validate()
		{
			var project_manager = ((Tool) this.tool).project_manager;
			if (this.file_path.strip() == "") {
				return "file_path is required";
			}
			var has_ast = (this.ast_path.strip() != "");
			var has_lines = (this.start_line >= 1 && this.end_line >= this.start_line);
			var has_search = (this.search_text.strip() != "");
			if ((has_ast ? 1 : 0) + (has_lines ? 1 : 0) + (this.complete_file ? 1 : 0) + (has_search ? 1 : 0) != 1) {
				return "use exactly one of: ast_path, line numbers (start_line/end_line), complete_file, or search_text";
			}
			if (project_manager != null && this.complete_file) {
				var norm_cf = this.normalize_file_path(this.file_path);
				var probe = new OLLMfiles.File.new_fake(
					project_manager,
					norm_cf
				);
				if ((yield probe.exists()) == GLib.FileType.DIRECTORY) {
					return "file_path is a directory, not a file: " + norm_cf;
				}
			}
			if (this.start_line >= 1 || this.end_line >= 1) {
				if (this.start_line < 1 || this.end_line < this.start_line) {
					return "start_line must be >= 1 and end_line >= start_line";
				}
			}
			if (has_ast) {
				switch (this.location) {
					case "replace":
					case "replace-with-comment":
					case "before":
					case "after":
					case "remove":
					case "with-comment":
					case "before-comment":
						break;
					default:
						return "location must be one of: replace, replace-with-comment, before, after, remove, before-comment";
				}
			}
			if (project_manager != null && (has_ast || has_lines)) {
				var norm = this.normalize_file_path(this.file_path);
				var file = new OLLMfiles.File.new_fake(project_manager, norm);
				if (project_manager.active_project != null) {
					var indexed = yield project_manager.active_project.fetch_file(
						norm
					);
					if (indexed != null) {
						file = indexed;
					}
				}
				project_manager.buffer_provider.create_buffer(file);
				if ((yield file.exists()) != GLib.FileType.REGULAR) {
					return "file does not exist (required for ast_path / line_numbers mode)";
				}
				if (!(yield file.read())) {
					return "failed to read file";
				}
			}
			if (project_manager != null && has_search) {
				var norm = this.normalize_file_path(this.file_path);
				var file = new OLLMfiles.File.new_fake(project_manager, norm);
				if (project_manager.active_project != null) {
					var indexed = yield project_manager.active_project.fetch_file(
						norm
					);
					if (indexed != null) {
						file = indexed;
					}
				}
				project_manager.buffer_provider.create_buffer(file);
				if ((yield file.exists()) != GLib.FileType.REGULAR) {
					return "file does not exist (required for search_text mode)";
				}
				if (!(yield file.read())) {
					return "failed to read file";
				}
				var matches = file.buffer.locate(this.search_text, true, true);
				if (matches.size == 0) {
					return "search_text not found in file";
				}
				if (matches.size > 1) {
					return "search_text must match exactly once";
				}
				return "";
			}
			if (project_manager != null && has_ast) {
				var norm = this.normalize_file_path(this.file_path);
				var file = new OLLMfiles.File.new_fake(project_manager, norm);
				if (project_manager.active_project != null) {
					var indexed = yield project_manager.active_project.fetch_file(
						norm
					);
					if (indexed != null) {
						file = indexed;
					}
				}
				project_manager.buffer_provider.create_buffer(file);
				if ((yield file.exists()) != GLib.FileType.REGULAR) {
					return "failed to read file for AST validation";
				}
				if (!(yield file.read())) {
					return "failed to read file for AST validation";
				}
				var change = new OLLMfiles.FileChange(file) {
					ast_path = this.ast_path.strip(),
					replacement = this.content
				};
				yield change.resolve_ast_path();
				if (change.has_error || (change.result != "" && change.result != "applied")) {
					return change.result != "" ? change.result : "AST path did not resolve";
				}
			}
			return "";
		}

		protected override async string execute_request() throws Error
		{
			var err = yield this.validate();
			if (err != "") {
				throw new GLib.IOError.INVALID_ARGUMENT(err);
			}
			var project_manager = ((Tool) this.tool).project_manager;
			if (project_manager == null) {
				throw new GLib.IOError.FAILED("ProjectManager is not available");
			}
			this.normalized_path = this.normalize_file_path(this.file_path);
			// Try to get File from active project index
			if (project_manager.active_project != null) {
				this.file = yield project_manager.active_project.fetch_file(
					this.normalized_path
				);
			}
			// Create fake file if not yet tracked (register before File.write RPC)
			if (this.file == null) {
				this.file = new OLLMfiles.File.new_fake(project_manager, this.normalized_path);
			}
			this.file.manager.buffer_provider.create_buffer(this.file);
			this.creating_file = (yield this.file.exists()) != GLib.FileType.REGULAR;
			if (this.creating_file) {
				yield this.file.buffer.clear();
			} else if (!(yield this.file.read())) {
				throw new GLib.IOError.FAILED(
					"Failed to read file: " + this.normalized_path);
			}
			if (this.search_text.strip() != "") {
				if (this.creating_file) {
					throw new GLib.IOError.INVALID_ARGUMENT(
						"search_text requires an existing file");
				}
				var matches = this.file.buffer.locate(this.search_text, true, true);
				if (matches.size != 1) {
					throw new GLib.IOError.FAILED(
						"search_text match count inconsistent with validate");
				}
				var keys_arr = matches.keys.to_array();
				var match_block = matches.get(keys_arr[0]);
				var line_parts = match_block.split("\n");
				this.start_line = keys_arr[0] + 1;
				this.end_line = this.start_line + line_parts.length
					- (line_parts.length > 0 && line_parts[line_parts.length - 1] == "" ? 1 : 0);
				this.search_text = "";
			}
			if (this.complete_file && !this.creating_file && !this.overwrite) {
				throw new GLib.IOError.EXISTS(
					"File already exists: " + this.normalized_path + ". Use overwrite=true to overwrite.");
			}

			OLLMfiles.FileChange change;
			if (this.complete_file) {
				change = new OLLMfiles.FileChange(this.file) { replacement = this.content };
			} else if (this.start_line >= 1 && this.end_line >= this.start_line) {
				// Whitespace-only body deletes the range; normalize to a true
				// empty string so dummy buffers do not insert a spurious line.
				change = new OLLMfiles.FileChange(this.file) {
					start = this.start_line,
					end = this.end_line,
					replacement = this.content.strip() == "" ? "" : this.content
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

			var change_type = this.creating_file ? "added" : "modified";
			// V2: no client FileHistory pre-commit; daemon records on register/write
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
				if (yield project_manager.active_project.contains_folder(dir_path)) {
					is_in_project = true;
				}
			}
			// For added files: register on daemon before File.write
			if (change_type == "added" && this.file.id <= 0 && is_in_project) {
				try {
					yield project_manager.active_project.insert_file(
						this.file,
						this.normalized_path
					);
				} catch (GLib.Error e) {
					GLib.warning(
						"Cannot register new file (%s): %s",
						this.normalized_path,
						e.message
					);
				}
			}
			// Update approval flags locally before RPC write
			this.file.is_need_approval = true;
			this.file.last_change_type = change_type;
			this.file.last_modified = new GLib.DateTime.now_local().to_unix();
			if (!(yield this.file.write())) {
				throw new GLib.IOError.FAILED(
					"Failed to write file via RPC: " + this.normalized_path);
			}
			this.agent.add_message(new OLLMchat.Message("ui", 
				OLLMchat.Message.fenced("text.oc-frame-success Write File",
				"Successfully wrote file: " + this.normalized_path + 
					"\nProject file: " + (is_in_project ? "yes" : "no"))));
			if (is_in_project && project_manager.active_project != null) {
				yield new OLLMfiles.ReviewFiles(
					project_manager.active_project
				).refresh();
			}
			this.creating_file = false;
			((Tool) this.tool).change_done(this.normalized_path, change);
			var lines = this.file.buffer.get_text().split("\n");
			return "File '" + this.normalized_path + "' written. " +
				lines.length.to_string() + " lines.";
		}
	}
}
