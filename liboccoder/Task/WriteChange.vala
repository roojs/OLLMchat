/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMcoder.Task
{
	/**
	 * One write operation parsed from a write-executor heading section (e.g. Change details).
	 *
	 * Populate with the `from_header` constructor. The `exec` method serializes only the
	 * tool-argument properties into JSON and runs the `write_file` tool (parser-only members
	 * are omitted via `serialize_property`).
	 */
	public class WriteChange : GLib.Object, Json.Serializable
	{
		// --- Parser-only (not sent to write_file) ---

		/** Non-empty when slug is not change-details, or Change-details body/shape failed. */
		public string issues { get; private set; default = ""; }
		/** From list: `fenced` or `next_section`; kept for logging/UI only. */
		public string output_mode { get; set; default = ""; }

		// --- write_file tool arguments (included in Json.gobject_serialize for exec) ---

		public string file_path { get; set; default = ""; }
		public string ast_path { get; set; default = ""; }
		public string location { get; set; default = ""; }
		public string content { get; set; default = ""; }
		public int start_line { get; set; default = -1; }
		public int end_line { get; set; default = -1; }
		public bool complete_file { get; set; default = false; }
		public bool overwrite { get; set; default = false; }

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		public Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "output_mode":
				case "output-mode":
				case "issues":
					return null;
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}

		private bool parse_keyvalue (Gee.Map<string, Markdown.Document.Block> kv)
		{
			var self_obj = (GLib.Object) this;
			foreach (var k in kv.keys) {
				var text = kv.get(k).to_markdown().strip();
				switch (k) {
					case "file_path":
					case "ast_path":
					case "location":
					case "output_mode":
						var sv = Value(typeof(string));
						sv.set_string(text);
						self_obj.set_property(k, sv);
						break;
					case "start_line":
					case "end_line":
						int iv;
						if (!int.try_parse(text, out iv)) {
							this.issues = "\nChange details: \"" + k + "\" must be an integer.";
							return false;
						}
						var nv = Value(typeof(int));
						nv.set_int(iv);
						self_obj.set_property(k, nv);
						break;
					case "complete_file":
					case "overwrite":
						var low = text.down();
						var bv = Value(typeof(bool));
						bv.set_boolean(low == "true" || low == "1");
						self_obj.set_property(k, bv);
						break;
					default:
						this.issues += "\nChange details: invalid list key \"" + k + "\". Use only: " +
							"file_path, ast_path, location, output_mode, start_line, end_line, complete_file, overwrite.";
						return false;
				}
			}
			return true;
		}

		/**
		 * Parses one heading section: bullet list key/values, then body into `content`.
		 *
		 * First: if `header.slug()` does not start with `change-details`, set `issues` and return.
		 * Then: if Change details but the shape is wrong, set `issues`.
		 * After key/value parse: fenced mode — next block is fence → `content`, `validate()`, return. `next_section` — walk `list_block.next()` / `Node.next()` to EOF → `content`, `validate()` (plan steps 4–5).
		 *
		 * @param header The heading `Block` for this section — must be a direct child of the document root (`header.parent == header.document()`). Caller skips nested headings.
		 */
		public WriteChange.from_header(Markdown.Document.Block header)
		{
			Object ();
			if (!header.slug().has_prefix("change-details")) {
				this.issues = "\nChange details: heading slug must start with \"change-details\".";
				return;
			}
			var section_nodes = header.contents(false);
			if (section_nodes.size == 0) {
				this.issues = "\nChange details: expected a bullet list immediately after the heading.";
				return;
			}
			var first_node = section_nodes.get(0);
			if (!(first_node is Markdown.Document.List)) {
				this.issues = "\nChange details: first block after heading must be a bullet list.";
				return;
			}
			var list_block = (Markdown.Document.List) first_node;
			if (!this.parse_keyvalue(list_block.to_key_map(GLib.CharacterSet.a_2_z))) {
				return;
			}
			if (this.output_mode.strip().down() != "next_section") {
				if (section_nodes.size < 2) {
					this.issues = "\nChange details: expected a fenced code block immediately after the bullet list (- file_path:, - output_mode:, …).";
					return;
				}
				var after_list = section_nodes.get(1);
				if (!(after_list is Markdown.Document.Block)) {
					this.issues = "\nChange details: second block after the list must be a fenced code block.";
					return;
				}
				var fence_block = (Markdown.Document.Block) after_list;
				if (fence_block.kind != Markdown.FormatType.FENCED_CODE_QUOTE
						&& fence_block.kind != Markdown.FormatType.FENCED_CODE_TILD) {
					this.issues = "\nChange details: second block after the list must be a fenced code block.";
					return;
				}
				var code = fence_block.code_text;
				if (code.has_suffix("\n")) {
					code = code.substring(0, code.length - 1);
				}
				this.content = code;
				this.validate();
				return;
			}
			string[] parts = {};
			for (Markdown.Document.Node? n = list_block.next(); n != null; n = n.next()) {
				parts += n.to_markdown();
			}
			var body = string.joinv("\n\n", parts);
			if (body.strip().length == 0) {
				this.issues = "\nChange details: output_mode next_section requires " + 
					" non-empty content after the bullet list (rest of document).";
				return;
			}
			this.content = body;
			this.validate();
		}

		/**
		 * Structural subset of write_file argument checks (sync). No extra
		 * properties on this class for validation.
		 *
		 * Empty body text after strip is allowed for a line range (deletes
		 * lines), for ast_path with location remove, or for complete_file
		 * (including an empty file).
		 *
		 * Cannot: resolve file_path against the project, FileUtils.test file
		 * existence (ast/line modes), async buffer read, resolve_ast_path, or
		 * FileChange — WriteFile.Request validation / execute when project_manager
		 * is set.
		 */
		public void validate ()
		{
			if (this.file_path.strip() == "") {
				this.issues += "\nwrite_file: file_path is required";
				return;
			}
			bool has_ast = (this.ast_path.strip() != "");
			bool has_lines = (this.start_line >= 1 && this.end_line >= this.start_line);
			if (this.content.strip() == "" && !has_lines
					&& !(has_ast && this.location == "remove")
					&& !this.complete_file) {
				this.issues += "\nwrite_file: content is required"
					+ " (empty allowed for line-range delete, AST remove,"
					+ " or complete_file)";
				return;
			}
			int modes = (has_ast ? 1 : 0) + (has_lines ? 1 : 0) + (this.complete_file ? 1 : 0);
			if (modes != 1) {
				this.issues += "\nwrite_file: use exactly one of: ast_path,"
					+ " line numbers (start_line/end_line), or complete_file";
				return;
			}
			if (this.start_line >= 1 || this.end_line >= 1) {
				if (this.start_line < 1 || this.end_line < this.start_line) {
					this.issues += "\nwrite_file: start_line must be >= 1"
						+ " and end_line >= start_line";
					return;
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
						this.issues += "\nwrite_file: location must be one of: replace, replace-with-comment, before, after, remove, with-comment, before-comment";
						return;
				}
			}
			// Not here: project-relative file_path, FileUtils.test(IS_REGULAR) for ast/line modes (needs PM + path).
			// Not here (async): buffer read, resolve_ast_path, FileChange — WriteFile.Request only.
		}

		/**
		 * Serializes this object to the `write_file` arguments object and runs the tool.
		 *
		 * @param run The execution `Tool` for this task run (provides chat, session, `parent`).
		 * @throws GLib.Error From the tool implementation or transport.
		 */
		public async void exec (Tool run) throws GLib.Error
		{
			var args = Json.gobject_serialize(this).get_object();
			var tc = new OLLMchat.Response.ToolCall.with_values("fake-write-id",
				new OLLMchat.Response.CallFunction.with_values("write_file", args));
			var impl = run.parent.runner.session.manager.tools.get("write_file");
			run.tool_run_result = yield impl.execute(run.chat(), tc, true);
		}
	}
}
