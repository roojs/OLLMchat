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
- ast_path (preferred): edit at AST path (e.g. Namespace-Class-Method).
  location is required.
- start_line and end_line: replace the line range (1-based, start inclusive,
  end exclusive). Empty content deletes those lines (same as ast_path +
  location remove).
- complete_file: replace or create entire file; content = full file body.
  Use overwrite=true to overwrite existing file.

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
@param end_line {int} [optional] End line (1-based, exclusive). Empty
  content deletes lines in [start_line, end_line).
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

		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(Request), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}
