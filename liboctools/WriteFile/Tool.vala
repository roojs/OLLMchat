/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

namespace OLLMtools.WriteFile
{
	/**
	 * One-shot file write tool. Same semantics as EditMode (permissions, backups)
	 * but content and mode are in the call; no streaming.
	 */
	public class Tool : OLLMchat.Tool.BaseTool
	{
		public override string name { get { return "write_file"; } }

		public override Type config_class() { return typeof(OLLMchat.Settings.BaseToolConfig); }
		public override string title { get { return "Write File Tool"; } }
		public override string example_call {
			get {
				return "{\"name\": \"write_file\", \"arguments\": {\"file_path\": \"src/App.vala\", \"content\": \"// implementation\", \"ast_path\": \"App-MainWindow-on_activate\", \"location\": \"replace\"}}";
			}
		}
		public override string description { get {
			return """
Write content to a file in one call (no streaming).

Prefer ast_path when editing existing code; use complete_file only for new files or full replacement.

Modes (use exactly one):
- ast_path (preferred): edit at AST path (e.g. Namespace-Class-Method). location is required.
- start_line and end_line: replace line range (1-based, start inclusive, end exclusive).
- complete_file: replace or create entire file; content = full file body. Use overwrite=true to overwrite existing file.

Location (when using ast_path):
  replace — replace the target at the path.
  replace-with-comment — replace the target including any preceding comment block.
  before — insert content before the target.
  after — insert content after the target.
  remove — delete the target.
  before-comment — insert before the target's preceding comment block.""";
		} }

		public override string parameter_description { get {
			return """
@param file_path {string} [required] Path to the file.
@param content {string} [required] Text to write.
@param ast_path {string} [optional] AST path (e.g. Namespace-Class-Method). Required with location when using AST mode.
@param location {string} [optional] Required when ast_path is set. replace, replace-with-comment, before, after, remove, before-comment.
@param start_line {int} [optional] Start line (1-based inclusive).
@param end_line {int} [optional] End line (1-based exclusive).
@param complete_file {boolean} [optional] If true, content is full file. Default false.
@param overwrite {boolean} [optional] If true and complete_file and file exists, overwrite. Default false.""";
		} }

		public signal void change_done(string file_path, OLLMfiles.FileChange change);

		public OLLMfiles.ProjectManager? project_manager { get; set; default = null; }

		public Tool(OLLMfiles.ProjectManager? project_manager = null)
		{
			base();
			this.project_manager = project_manager;
		}

		public OLLMchat.Tool.BaseTool? clone()
		{
			return new Tool(this.project_manager);
		}

		/**
		 * Validate write_file arguments. For use by skill/refine stage.
		 * When project_manager is null: structure only. When set: structure + file existence (modify modes) + AST resolution (ast_path mode).
		 * Returns "" if valid, otherwise error string (first error found).
		 * Use start_line/end_line = -1 when not using line-number mode.
		 */
		public static async string validate(
			OLLMfiles.ProjectManager? project_manager,
			string file_path,
			string content,
			string ast_path,
			string location,
			int start_line,
			int end_line,
			bool complete_file,
			bool overwrite
		)
		{
			if (file_path.strip() == "") {
				return "file_path is required";
			}
			bool has_ast = (ast_path.strip() != "");
			bool has_lines = (start_line >= 1 && end_line >= start_line);
			int modes = (has_ast ? 1 : 0) + (has_lines ? 1 : 0) + (complete_file ? 1 : 0);
			if (modes != 1) {
				return "use exactly one of: ast_path, line numbers (start_line/end_line), or complete_file";
			}
			if (start_line >= 1 || end_line >= 1) {
				if (start_line < 1 || end_line < start_line) {
					return "start_line must be >= 1 and end_line >= start_line";
				}
			}
			if (has_ast) {
				switch (location) {
					//case "":
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
				string norm = (!GLib.Path.is_absolute(file_path) && project_manager.active_project != null)
					? GLib.Path.build_filename(project_manager.active_project.path, file_path)
					: file_path;
				if (!GLib.FileUtils.test(norm, GLib.FileTest.IS_REGULAR)) {
					return "file does not exist (required for ast_path / line_numbers mode)";
				}
			}
			if (project_manager != null && has_ast) {
				string norm = (!GLib.Path.is_absolute(file_path) && project_manager.active_project != null)
					? GLib.Path.build_filename(project_manager.active_project.path, file_path)
					: file_path;
				var file = project_manager.get_file_from_active_project(norm);
				if (file == null) {
					file = new OLLMfiles.File.new_fake(project_manager, norm);
				}
				project_manager.buffer_provider.create_buffer(file);
				if (!file.buffer.is_loaded) {
					try {
						yield file.buffer.read_async();
					} catch (GLib.Error e) {
						return "failed to read file: " + e.message;
					}
				}
				var change = new OLLMfiles.FileChange(file) { 
					ast_path = ast_path.strip(), 
					replacement = content };
				yield change.resolve_ast_path();
				if (change.has_error || (change.result != "" && change.result != "applied")) {
					return change.result != "" ? change.result : "AST path did not resolve";
				}
			}
			return "";
		}

		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(Request), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}
