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

public enum MarkdownPhase
{
	COARSE,
	REFINEMENT,
	LIST,
	REFINE_COMPLETED,
	EXECUTION,
	POST_EXEC
}

/**
 * One task in the plan. Built from task list output; updated from
 * refinement output.
 *
 * Task list (input): each list item under a task section heading has a nested list
 * with labels ''What is needed'', ''Skill'', ''References'', ''Expected output''.
 * Links in References: current_file, paths, plan:...
 * Keys are lowercase labels from List.to_key_map(..., a_2_z), e.g.
 * "what is needed", "skill", "references", "expected output",
 * "requires user approval", "shared references", "examination references".
 *
 * Refined task (refinement output): section "Refined task" with same list plus
 * ''Skill call'' and an optional fenced code block. Parser uses
 * ListItem.to_key_map(..., a_2_z) for both; update_props(refined_map); code added
 * directly to code_blocks.
 *
 * Execution: after refinement, the runner calls build_exec_runs() then run_exec().
 * exec_runs holds one Tool per run; each Tool.run() runs the tool (if any)
 * then the LLM.
 * Summaries and documents live on each Tool in exec_runs.
 * (ex.document).
 */
public class Details : OLLMchat.Agent.Base
{
	// - stored task content (exact keys only, see class doc)
	/**
	 * Map from ListItem.to_key_map(..., a_2_z); keys are lowercase labels only.
	 * All task content is read from here.
	 */
	public Gee.Map<string, Markdown.Document.Block> task_data {
		get; set; default = new Gee.HashMap<string, Markdown.Document.Block>(); }

	/**
	 * True when this task should gate execution (e.g. modifies files);
	 * from task list format.
	 */
	public bool requires_user_approval { get; set; default = false; }

	/**
	 * True after run_exec success; exec_runs then hold summaries and documents.
	 */
	public bool exec_done { get; set; default = false; }

	/**
	 * Validation errors; append with this.issues += "\n" + msg.
	 * Parser checks and appends with section context.
	 */
	public string issues { get; set; default = ""; }

	/**
	 * Step index (0-based) of the section this task belongs to, or -1 if not set.
	 * Set when the task list is built (e.g. in ResultParser.parse_task_list) so we don't
	 * re-derive section from position later.
	 */
	public int step_index { get; set; default = -1; }

	/**
	 * Step this task belongs to; required so Details looks up the tree (step.list.runner)
	 * for runner, session, etc.
	 */
	public weak Step step { get; set; }

	/**
	 * Executor output summary (Result summary section).
	 */
	/**
	 * Runner; looked up from step.list.runner (tree: runner → list → step → details).
	 */
	public OLLMcoder.Skill.Runner runner {
		get { return this.step.list.runner; }
	}

	/**
	 * Alias to runner.sr_factory.skill_manager (no setter).
	 */
	public OLLMcoder.Skill.Manager skill_manager {
		get { return this.runner.sr_factory.skill_manager; }
	}

	/**
	 * Parser for last refine or executor response; exec_runs valid after exec_done
	 * (from exec_runs). Initialized in ctor so issues is always available.
	 */
	public ResultParser result_parser { get; set; }

	/**
	 * Markdown links from task "references" block (current_file, paths, plan:...);
	 * Runner resolves for prompt fill. Filled in fill_task_data().
	 */
	public Gee.ArrayList<Markdown.Document.Format> references {
		get; set; default = new Gee.ArrayList<Markdown.Document.Format>(); }
	/** Links from "shared references" task_data (refinement). */
	public Gee.ArrayList<Markdown.Document.Format> shared_references {
		get; set; default = new Gee.ArrayList<Markdown.Document.Format>(); }
	/** Links from "examination references" task_data (per-run execution). */
	public Gee.ArrayList<Markdown.Document.Format> exam_references {
		get; set; default = new Gee.ArrayList<Markdown.Document.Format>(); }

	/**
	 * Code blocks from refinement (parser); add directly.
	 */
	public Gee.ArrayList<Markdown.Document.Block> code_blocks { 
		get; set; default = new Gee.ArrayList<Markdown.Document.Block>(); }

	/**
	 * Tool instances from `## Tool Calls` section (ResultParser);
	 * build_exec_runs() uses them for scenario 1.
	 */
	public Gee.ArrayList<Tool> tools { get; set; default = new Gee.ArrayList<Tool>(); }

	/**
	 * Tool instances per execution run. Populated by build_* methods;
	 * run_exec() runs each (tool if needed, then LLM).
	 * REFINE_COMPLETED uses their summaries.
	 */
	public Gee.ArrayList<Tool> exec_runs { get; set; default = new Gee.ArrayList<Tool>(); }

	/**
	 * Single markdown document after post-exec synthesis. Headings used for
	 * {{{ task://slug.md }}} (full document) or optional fragment for one section.
	 * Empty until
	 * run_post_exec finishes.
	 */
	public Markdown.Document.Document out_doc {
		get; set; default = new Markdown.Document.Document();
	}

	/**
	 * Result summary block from post-exec (iteration + completed-task list).
	 */
	public Markdown.Document.Block post_summary {
		get; set; default = new Markdown.Document.Block(Markdown.FormatType.PARAGRAPH);
	}

	/**
	 * Initial task_data from ListItem.to_key_map(..., a_2_z) for one task list item
	 * (keys: lowercase labels only, see class doc). Runner and session come from step.list.runner (tree).
	 *
	 * @param step the step this task belongs to (provides list and runner via tree)
	 * @param task_data initial map from list item (lowercase keys only)
	 */
	public Details(Step step, Gee.Map<string, Markdown.Document.Block> task_data)
	{
		base(step.list.runner.factory, step.list.runner.session);
		this.step = step;
		this.task_data = task_data;
		this.issues = "";
		this.result_parser = new ResultParser(step.list.runner, "");
		this.fill_task_data();
		if (this.runner.in_replay) {
			this.chat_call = this.runner.chat_call;
		}
	}

	/**
	 * Ensure expected task_data keys exist (placeholder block if missing), then refresh
	 * fields derived from task_data (e.g. references, shared_references, exam_references).
	 * Called from the ctor and update_props after task_data changes — the name alone
	 * does not spell out that dual role.
	 */
	private void fill_task_data()
	{
		this.requires_user_approval = this.task_data.has_key("requires user approval");
		var empty = new Markdown.Document.Block(Markdown.FormatType.PARAGRAPH);
		string[] keys_to_fill = {
			"what is needed",
			"skill",
			"references",
			"expected output",
			"shared references",
			"examination references" };
		foreach (var key in keys_to_fill) {
			if (!this.task_data.has_key(key)) {
				this.task_data.set(key, empty);
			}
			switch (key) {
				case "references":
					this.references = this.task_data.get(key).links();
					break;
				case "shared references":
					this.shared_references = this.task_data.get(key).links();
					break;
				case "examination references":
					this.exam_references = this.task_data.get(key).links();
					break;
				default:
					break;
			}
		}
	}

	/**
	 * Write this task's result to session task dir.
	 * Writes a single slug.md from out_doc.
	 *
	 * @param suffix filename suffix (default "")
	 */
	public void write(string suffix = "")
	{
		var path = GLib.Path.build_filename(
			this.runner.session.task_dir(),
			this.slug() + suffix + ".md");
		var content = this.out_doc.to_markdown();
		try {
			GLib.FileUtils.set_contents(path, content);
		} catch (GLib.FileError e) {
			GLib.critical("Details.write: failed to write %s: %s", path, e.message);
		}
	}

	/**
	 * Apply refined task map: set each key from refined_map into this.task_data,
	 * then re-run fill.
	 *
	 * @param refined_map map from refined task list item (same key set as task_data)
	 */
	public void update_props(Gee.Map<string, Markdown.Document.Block> refined_map)
	{
		this.issues = "";
		foreach (var e in refined_map.entries) {
			// Keep original task's Skill; do not overwrite from refinement output.
			if (e.key == "skill") {
				continue;
			}
			this.task_data.set(e.key, e.value);
		}
		this.fill_task_data();
	}

	/**
	 * If task_data has no "name" or empty, set name = (skill or "Task") + " " + index.
	 * Single method.
	 *
	 * @param i step index (0-based) used for the default name
	 */
	public void fill_name(int i)
	{
		var name_block = this.task_data.has_key("name") ?
			this.task_data.get("name").to_markdown().strip() : "";
		if (name_block != "") {
			return;
		}
		// Allow empty skill; validate_skills() will report this as a bad task.
		var skill = this.task_data.has_key("skill") ?
			this.task_data.get("skill").to_markdown().strip() : "";
		var name = (skill != "" ? skill : "Task") + " " + i.to_string();
		var b = new Markdown.Document.Block(Markdown.FormatType.PARAGRAPH);
		b.adopt(new Markdown.Document.Format.from_text(name));
		this.task_data.set("name", b);
	}

	/**
	 * This task's name as slug (e.g. "Research 1" → "research-1").
	 * Returns "" if no name in task_data or empty.
	 *
	 * @return slug string for filenames and task refs
	 */
	public string slug()
	{
		if (!this.task_data.has_key("name")) {
			return "";
		}
		var name = this.task_data.get("name").to_markdown().strip();
		if (name == "") {
			return "";
		}
		var s = new GLib.Regex("[^a-z0-9]+").replace(name.down(), -1, 0, "-");
		return new GLib.Regex("^-+|-+$").replace(s, -1, 0, "");
	}

	/**
	 * Label for this task in issue messages: section number and name or slug
	 * (e.g. "section 2 \"Research 1\"" or "section 2 (slug: research-1)") so
	 * the LLM can locate the task in the task list.
	 */
	public string issue_label()
	{
		var section = (this.step.title != "") ?
			this.step.title : "section " + (this.step_index >= 0 ? (this.step_index + 1).to_string() : "?");
		var name = this.task_data.has_key("name") ?
			this.task_data.get("name").to_markdown().strip() : "";
		if (name != "") {
			return section + " \"" + name + "\"";
		}
		var s = this.slug();
		if (s != "") {
			return section + " (slug: " + s + ")";
		}
		return section + " (unnamed)";
	}

	private bool refined_done = false;
	private GLib.Error? refine_error = null;
	private GLib.SourceFunc? resume_refined = null;

	/**
	 * True when refinement failed after exhausting communication retries
	 * (e.g. send threw 3 times). Caller should report to user.
	 */
	public bool last_failure_was_communication { get; private set; default = false; }

	public async void wait_refined() throws GLib.Error
	{
		if (this.refined_done) {
			if (this.refine_error != null) {
				throw this.refine_error;
			}
			return;
		}
		this.resume_refined = wait_refined.callback;
		yield;
		this.resume_refined = null;
		if (this.refine_error != null) {
			throw this.refine_error;
		}
	}

	/**
	 * Fenced JSON blocks from the session tool registry for each name in the skill's tools list.
	 * Empty when there are no tools, the skill lists write_file, or nothing resolves to BaseTool.
	 */
	public string tool_instructions(OLLMcoder.Skill.Definition definition)
	{
		if (definition.tools.size < 1 || definition.tools.contains("write_file")) {
			return "";
		}
		string[] chunks = {};
		foreach (var tool_name in definition.tools) {
			var original = this.runner.session.manager.tools.get(tool_name);
			if (original == null || !(original is OLLMchat.Tool.BaseTool)) {
				continue;
			}
			var base_tool = (OLLMchat.Tool.BaseTool) original;
			var schema = new Json.Object();
			schema.set_string_member("name", base_tool.function.name);
			schema.set_string_member("description", base_tool.function.description);
			var param_node = Json.gobject_serialize(base_tool.function.parameters);
			param_node.get_object().set_string_member("type", base_tool.function.parameters.x_type);
			schema.set_object_member("parameters", param_node.get_object());
			var root = new Json.Node(Json.NodeType.OBJECT);
			root.set_object(schema);
			var gen = new Json.Generator();
			gen.set_root(root);
			var ret = gen.to_data(null);
			if (base_tool.example_call != "") {
				ret += "\nExample: " + base_tool.example_call;
			}
			chunks += "```json\n" + ret + "\n```\n\n";
		}
		if (chunks.length == 0) {
			return "";
		}
		return "## Registered tool definitions\n\n" + string.joinv("", chunks);
	}

	/**
	 * Build refinement prompt template (no current_file; reference_contents
	 * includes current file when in the task's References).
	 */
	public OLLMcoder.Skill.PromptTemplate refinement_prompt() throws GLib.Error
	{
		var definition = this.skill_manager.fetch(this);
		var tpl = OLLMcoder.Skill.PromptTemplate.template(
			definition.tools.size > 0 && !definition.tools.contains("write_file")
				? "task_refinement.md"
				: "task_refinement_references.md");
		tpl.system_fill(0);
		var completed_md = this.runner.completed.to_markdown(MarkdownPhase.REFINE_COMPLETED);
		tpl.fill(8,
			"issues", tpl.header_raw("Issues with the current call", this.result_parser.issues),
			"task_data", tpl.header_raw("Task", this.to_markdown(MarkdownPhase.REFINEMENT)),
			"environment", this.runner.env(),
			"project_description", (this.runner.sr_factory.project_manager.active_project == null ?
				"" : this.runner.sr_factory.project_manager.active_project.project_description()),
			"task_reference_contents", this.reference_contents(MarkdownPhase.REFINEMENT),
			"skill_details", definition.refine,
			"tool_instructions", this.tool_instructions(definition),
			"completed_task_list", (completed_md == "" ? "" :
				"## Completed tasks (so far) for your reference only\n\n" + completed_md));
		return tpl;
	}

	/**
	 * Refinement: fill template. Caller has validated via skill_manager.validate(this);
	 * definition from skill_manager.fetch(this) is non-null. Details builds
	 * task_reference_contents by looping references and asking Runner
	 * for each item (see "Building the task reference block").
	 * Up to 5 refinement attempts; up to 3 communication retries per attempt.
	 * Caller (Runner) must catch and report to user; see 1.23.14.
	 */
	public async void refine(GLib.Cancellable? cancellable = null) throws GLib.Error
	{
		this.refined_done = false;
		this.refine_error = null;
		this.add_message(new OLLMchat.Message("ui",
			OLLMchat.Message.fenced("markdown.oc-frame-info.collapsed Refining " +
				this.task_data.get("name").to_markdown().strip() + " with " +
				this.session.model_usage.display_name_with_size(),
					  this.to_markdown(MarkdownPhase.COARSE))));
		yield this.fill_model();
		// Refiner must not have tools; the model must only output text (Skill call + Tool Calls as text).
		this.chat_call.tools.clear();
		for (var i = 0; i < 5; i++) {
			if (cancellable != null && cancellable.is_cancelled()) {
				return;
			}
			// Clear state from any previous parse so we don't feed it back into the prompt
			// (task_data / to_markdown would include tools and code_blocks, causing the LLM
			// to echo them and producing combined output that fails to parse).
			this.tools.clear();
			this.code_blocks.clear();
			yield this.runner.load_links(this.references);
			this.add_message(new OLLMchat.Message("ui-waiting", "Waiting for response…"));
			var tpl = this.refinement_prompt();
			this.session.messages.add(new OLLMchat.Message("system", tpl.filled_system));
			this.session.messages.add(new OLLMchat.Message("user", tpl.filled_user));
			var messages = new Gee.ArrayList<OLLMchat.Message>();
			messages.add(new OLLMchat.Message("system", tpl.filled_system));
			messages.add(new OLLMchat.Message("user", tpl.filled_user));

			var response_text = "";
			for (var attempt = 0; attempt < 3; attempt++) {
				try {
					var response = yield this.chat_call.send(messages, cancellable);
					response_text = response != null ? response.message.content : "";
					break;
				} catch (GLib.Error e) {
					if (attempt != 2) {
						continue;
					}
					this.refine_error = new GLib.IOError.INVALID_ARGUMENT("Task refinement: " + e.message);
					throw this.refine_error;
				}
			}
			if (cancellable != null && cancellable.is_cancelled()) {
				return;
			}
			this.result_parser = new ResultParser(this.runner, response_text);
			this.result_parser.extract_refinement(this);
			var task_name = this.task_data.get("name").to_markdown().strip();
			if (this.runner.in_replay) {
				((OLLMchat.Call.ReplayChat) this.chat_call).report_replay_outcome(this.result_parser.issues);
			}
			if (this.result_parser.issues == "") {
				this.runner.replay_step("refinement_success: " + task_name, response_text);
				this.refined_done = true;
				if (this.resume_refined != null) {
					this.resume_refined();
				}
				return;
			}
			if (i < 4) {
				this.runner.replay_step("refinement_parse_issues: " + task_name,
					response_text + "\n\nParse issues:\n" + this.result_parser.issues);
				this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
					"text.oc-frame-danger.collapsed Refinement for \"" + 
						this.task_data.get("name").to_markdown().strip() + "\" had issues (retrying)",
					this.result_parser.issues.strip())));
			}
		}
		this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
			"text.oc-frame-danger.collapsed Refinement for \"" + 
				this.task_data.get("name").to_markdown().strip() + "\" failed after 5 tries",
			this.result_parser.issues.strip())));
		throw new GLib.IOError.INVALID_ARGUMENT("Task refinement: " + this.result_parser.issues);
	}

	/**
	 * Set chat_call.model from this task's skill definition when the skill
	 * header has an optional model and it is available; otherwise use default.
	 */
	protected override async void fill_model()
	{
		var definition = this.skill_manager.fetch(this);
		if (!definition.header.has_key("model")) {
			yield base.fill_model();
			return;
		}
		var skill_model = definition.header.get("model").strip();
		if (skill_model != "" && this.connection.models.has_key(skill_model)) {
			this.chat_call.model = skill_model;
			// this.add_message(new OLLMchat.Message("ui", "skill using " + skill_model + " model."));
			return;
		}
		if (skill_model != "") {
			this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
				"text.oc-frame-warning.collapsed Model unavailable",
				"The skill requested the model \"" + skill_model +
					 "\", but it was not available. Using your selected model instead.")));
		}
		yield base.fill_model();
	}

	/**
	 * Task as markdown for a given phase. Does not add section headings
	 * (e.g. `## Task`); caller adds header.
	 * COARSE: creation keys. REFINEMENT/EXECUTION: task list + `## Tool Calls` when tools exist.
	 * POST_EXEC: task list only (no Tool Calls). LIST: task list + ##### Result summary when exec_done.
	 *
	 * @param phase which phase (COARSE, REFINEMENT, LIST, REFINE_COMPLETED,
	 * EXECUTION, POST_EXEC)
	 * @return markdown string for this phase
	 */
	public string to_markdown(MarkdownPhase phase)
	{
		string[] order = {
			"name",
			"what is needed",
			"skill",
			"references",
			"shared references",
			"examination references",
			"expected output",
			"requires user approval",
			"output"
		};
		var ret = "";
		for (var i = 0; i < order.length; i++) {
			var key = order[i];
			switch (key) {
				case "references":
				case "shared references":
				case "examination references":
					if (phase == MarkdownPhase.REFINE_COMPLETED) {
						continue;
					}
					break;
				case "output":
					if ((phase != MarkdownPhase.LIST &&
							phase != MarkdownPhase.REFINE_COMPLETED)
							|| !this.exec_done) {
						continue;
					}
					// Executor output: always include the post-exec result summary (Result summary body).
					ret += "#### Task result\n\n";
					ret += this.post_summary.to_markdown_with_content()
						.strip() + "\n\n";
					// Other top-level headings in the output doc: bullet list of [title](#gfm-slug) for in-doc navigation.
					if (this.out_doc.header_list.size == 0) {
						continue;
					}
					string[] section_links = {};
					foreach (var slug in this.out_doc.header_list) {
						var hb = this.out_doc.headings.get(slug);
						var title = hb != null ? hb.text_content().strip() : slug;
						if (title == "") {
							title = slug;
						}
						section_links += "- [" + title + "](#" + slug + ")";
					}
					ret += "**Sections in this output:**\n\n"
						+ string.joinv("\n", section_links) + "\n\n";
					continue;
				default:
					break;
			}
			if (!this.task_data.has_key(key)) {
				continue;
			}
			var block = this.task_data.get(key);
			if (block.children.size == 0) {
				continue;
			}
			ret += "- **" + key.substring(0, 1).up() + key.substring(1) + "** "
				+ block.to_markdown() + "\n";
		}
		if (phase == MarkdownPhase.REFINE_COMPLETED || phase == MarkdownPhase.POST_EXEC ||
				this.tools.size == 0) {
			return ret;
		}
		ret += "\n## Tool Calls\n\n";
		foreach (var tool in this.tools) {
			var obj = new Json.Object();
			obj.set_string_member("name", tool.name);
			if (tool.tool_call != null && tool.tool_call.id != "") {
				obj.set_string_member("id", tool.tool_call.id);
			}
			if (tool.arguments != null) {
				obj.set_object_member("arguments", tool.arguments);
			}
			var node = new Json.Node(Json.NodeType.OBJECT);
			node.set_object(obj);
			var gen = new Json.Generator();
			gen.set_root(node);
			ret += "```json\n" + gen.to_data(null) + "\n```\n\n";
		}
		return ret;
	}


	/**
	 * Line + unfenced body. Use for reference `#anchor`.
	 *
	 * @param line heading or label line
	 * @param body unfenced body content
	 * @return line + body, or "" if body empty
	 */
	internal string header_raw(string line, string body)
	{
		if (body == "") {
			return "";
		}
		return line + "\n\n" + body + "\n\n";
	}

	/**
	 * Line + fenced body; content and language from file.
	 * Use for reference file path. Exception: we do output the header
	 * (and empty block if needed) when content is empty.
	 *
	 * @param line heading or label line
	 * @param file file to read content and language from
	 * @param start **-1** = no line-range fragment (head or refinement preview); else 1-based start line from **#L…** fragment
	 * @param end **-1** with **start == -1** = head / refinement preview; else 1-based end line (**#L…**)
	 * @return fenced block with line + content
	 */
	internal string header_file(string line, OLLMfiles.File file, MarkdownPhase stage,
		int start = -1, int end = -1)
	{
		var content = stage == MarkdownPhase.REFINEMENT
			? file.contents(int.max(start, 1), start == -1 ? 20 : int.min(end, start + 29))
			: file.contents(int.max(-1, start), start == -1 ? -1 : end);
		if (stage == MarkdownPhase.REFINEMENT
				&& (
					(start == -1 && file.line_count() > 20)
					|| (start != -1 && end > start + 29)
				)) {
			content += "\n\n**This has been abbreviated.** The full content has "
				+ file.line_count().to_string() + " lines.\n";
		}
		var fence = (content.index_of("\n```") >= 0 || content.has_prefix("```")) ? "~~~~" : "```";
		return line + "\n\n"
			+ fence
			+ (file.language != "" ? file.language + "\n" : "\n")
			+ content + "\n"
			+ fence + "\n\n";
	}

	/**
	 * Line + fenced body with type (e.g. "json", "text").
	 * Use for tool call/output.
	 *
	 * @param line heading or label line
	 * @param body body content to fence
	 * @param type optional language/info string (e.g. "json", "text")
	 * @return fenced block, or "" if body empty
	 */
	internal string header_fenced(string line, string body, string type = "")
	{
		if (body == "") {
			return "";
		}
		var fence = (body.index_of("\n```") >= 0 || body.has_prefix("```")) ? "~~~~" : "```";
		return line + "\n\n"
			+ fence
			+ (type != "" ? type + "\n" : "\n")
			+ body + "\n"
			+ fence + "\n\n";
	}

	/**
	 * Resolved content for a single reference link. Uses link.scheme (file, task,
	 * http(s), or path == "" for `#anchor`). File: project manager or
	 * File.new_fake, create_buffer, header_file. Other schemes:
	 * runner.reference_content(link, stage).
	 *
	 * @param link the reference link (scheme, path, href, title
	 * already parsed)
	 * @param stage markdown phase forwarded to runner / file preview
	 * @return fenced or file block for prompt, or "" if unresolved/empty
	 */
	internal string link_content(Markdown.Document.Format link, MarkdownPhase stage)
	{
		var name = link.title != "" ? link.title : (link.href != "" ? link.href : "unnamed reference");
		var ref_url = link.href != "" ? link.href : link.path;
		var title = "### Reference contents for " + name;
		if (ref_url != "") {
			title += " — " + ref_url;
		}
		if (link.path == "") {
			var body = this.runner.reference_content(link, stage);
			return body != "" ? this.header_fenced(title, body, "markdown") : "";
		}
		if (link.scheme == "http" || link.scheme == "https") {
			if (stage != MarkdownPhase.EXECUTION) {
				return "";
			}
			var body = this.runner.reference_content(link, stage);
			return body != "" ? this.header_fenced(title, body, "markdown") : "";
		}
		if (link.scheme == "task") {
			var body = this.runner.reference_content(link, stage);
			return body != "" ? this.header_fenced(title, body, "markdown") : "";
		}
		if (link.scheme != "file") {
			return "";
		}
		var project = this.runner.sr_factory.project_manager.active_project;
		var resolved_path = link.is_relative
			? (project == null ? "" : link.abspath(project.path))
			: link.path;
		if (resolved_path == "") {
			return "";
		}
		var found = this.runner.sr_factory.project_manager.get_file_from_active_project(resolved_path);
		if (found == null) {
			found = new OLLMfiles.File.new_fake(this.runner.sr_factory.project_manager, resolved_path);
		}
		this.runner.sr_factory.project_manager.buffer_provider.create_buffer(found);
		GLib.MatchInfo mi;
		if (new GLib.Regex(
				"^[Ll](\\d+)-[Ll](\\d+)$",
				GLib.RegexCompileFlags.OPTIMIZE | GLib.RegexCompileFlags.CASELESS)
				.match(link.hash, 0, out mi)) {
			return this.header_file(title, found, stage,
				int.parse(mi.fetch(1)), int.parse(mi.fetch(2)));
		}
		return this.header_file(title, found, stage);
	}

	/**
	 * Resolved reference block for this task: loop references; for each,
	 * get content via link_content(). When there are no references, returns "".
	 * When there are references, returns "## Reference Contents" plus each block.
	 */
	internal string reference_contents(MarkdownPhase stage)
	{
		string[] parts = {};
		foreach (var link in this.references) {
			GLib.debug("reference_contents: resolving link scheme=%s path=%s href=%s hash=%s",
				link.scheme, link.path, link.href, link.hash);
			var block = this.link_content(link, stage);
			if (block != "") {
				parts += block;
			}
		}
		foreach (var link in this.shared_references) {
			var block = this.link_content(link, stage);
			if (block != "") {
				parts += block;
			}
		}
		if (parts.length == 0) {
			return "";
		}
		return "## Reference Contents\n\n" + string.joinv("", parts);
	}

	public void build_exec_runs()
	{
		this.exec_runs.clear();
		var factory = (OLLMchat.Agent.Factory) this.runner.sr_factory;
		var idx = 0;
		if (this.exam_references.size > 0) {
			foreach (var exam in this.exam_references) {
				var ex = new Tool(factory, this.session, this, "exam-%d".printf(idx++));
				ex.exam_reference = exam;
				ex.references = this.shared_references;
				this.exec_runs.add(ex);
			}
			return;
		}
		if (this.tools.size > 0) {
			foreach (var ex in this.tools) {
				ex.id = "tool-%d".printf(idx++);
				ex.references = this.shared_references;
				this.exec_runs.add(ex);
			}
			return;
		}
		var lone = new Tool(factory, this.session, this, "exec");
		lone.references = this.shared_references;
		this.exec_runs.add(lone);
	}

	/**
	 * Run all Tool exec runs (tool if needed, then LLM). Breaks on has_task_complete();
	 * then runs post-exec synthesis. Summaries and canonical document from post-exec.
	 */
	public async void run_exec() throws GLib.Error
	{
		var task_name = this.task_data.get("name").to_markdown().strip();
		for (var i = 0; i < this.exec_runs.size; i++) {
			var ex = this.exec_runs.get(i);
			this.add_message(new OLLMchat.Message("ui",
				"Running Tools for Task " + task_name + " — Tool call " +
				(i + 1).to_string()));
			yield ex.run();
			if (ex.has_task_complete()) {
				this.add_message(new OLLMchat.Message("ui",
					"Tool evaluation indicated that **We have enough " +
					"information to complete task**."));
				break;
			}
		}
		// Multi-run: post-exec summarizes combined tool runs (write_file runs are included inside each run).
		// Single run: no synthesis pass — copy that run's executor output.
		// Invariant: build_exec_runs() leaves exec_runs.size >= 1 before run_exec().
		if (this.exec_runs.size > 1) {
			yield this.run_post_exec();
			this.exec_done = true;
			return;
		}
		var last = this.exec_runs.get(this.exec_runs.size - 1);
		this.post_summary = last.summary;
		this.out_doc = last.document;
		this.exec_done = true;
	}

	/**
	 * Build post-execution prompt from task_post_exec.md.
	 * previous_response and retry_issues are used for retries (header_raw when non-empty).
	 */
	public OLLMcoder.Skill.PromptTemplate post_exec_prompt(
			string previous_response, string retry_issues) throws GLib.Error
	{
		var definition = this.skill_manager.fetch(this);
		var tpl = OLLMcoder.Skill.PromptTemplate.template("task_post_exec.md");
		tpl.system_fill(0);
		string[] run_blocks = {};
		for (var i = 0; i < this.exec_runs.size; i++) {
			var ex = this.exec_runs.get(i);
			run_blocks += ex.document.to_markdown();
			if (ex.has_task_complete()) {
				break;
			}
		}
		tpl.fill(6,
			"task_definition", this.to_markdown(MarkdownPhase.POST_EXEC),
			"skill_name", definition.header.get("name"),
			"skill_execute_body", definition.execute,
			"tool_runs_combined", string.joinv("\n\n---\n\n", run_blocks),
			"post_exec_previous_output",
			previous_response.strip() == "" ? "" :
				tpl.header_raw("Your previous output", previous_response),
			"post_exec_retry_issues",
			retry_issues.strip() == "" ? "" :
				tpl.header_raw("Issues with your previous output", retry_issues));
		return tpl;
	}

	/**
	 * Post-execution synthesis: combine executor outputs, call LLM with task_post_exec.md,
	 * parse into post_summary and out_doc; validate links.
	 * Retry on parse/validation issues: refill with previous output and issues via header_raw (same pattern as refinement).
	 */
	public async void run_post_exec() throws GLib.Error
	{
		yield this.fill_model();
		this.chat_call.tools.clear();
		var response_text = "";
		var last_issues = "";
		for (var try_count = 0; try_count < 5; try_count++) {
			var tpl = this.post_exec_prompt(response_text, last_issues);
			var task_name = this.task_data.get("name").to_markdown().strip();
			var model_label = this.session.model_usage.model != "" ?
				this.session.model_usage.display_name_with_size() : "";
			var model_part = model_label != "" ? " with " + model_label : "";
			this.add_message(new OLLMchat.Message("ui",
				OLLMchat.Message.fenced(
					"markdown.oc-frame-info.collapsed Summarizing Tool outputs for " +
					task_name + model_part,
					tpl.filled_user)));
			var messages = new Gee.ArrayList<OLLMchat.Message>();
			messages.add(new OLLMchat.Message("system", tpl.filled_system));
			messages.add(new OLLMchat.Message("user", tpl.filled_user));
			this.session.messages.add(new OLLMchat.Message("system", tpl.filled_system));
			this.session.messages.add(new OLLMchat.Message("user", tpl.filled_user));
			this.add_message(new OLLMchat.Message("ui-waiting",
				model_label != "" ?
					"Waiting for response from " + model_label :
					"Waiting for response"));
			var response = yield this.chat_call.send(messages, null);
			response_text = response != null ? response.message.content : "";
			// Ensure any literal {task_link_base} in model output is replaced so links validate
			var task_base = "task://" + this.slug() + ".md";
			response_text = response_text.replace("{task_link_base}", task_base);
			// Before exec_post_extract: it copies task.issues into parser.issues after link checks.
			this.issues = "";
			var parser = new ResultParser(this.runner, response_text);
			parser.exec_post_extract(this);
			if (parser.issues == "") {
				return;
			}
			this.issues += "\n" + parser.issues;
			last_issues = parser.issues.strip();
			if (try_count < 4) {
				this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
					"text.oc-frame-warning.collapsed Issues with summation of tool calls",
					last_issues)));
			}
		}
		var task_name_fail = this.task_data.get("name").to_markdown().strip();
		this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
			"text.oc-frame-danger.collapsed Summation of tool calls failed for \"" + task_name_fail + "\"",
			last_issues.strip())));
		throw new GLib.IOError.INVALID_ARGUMENT(
			"task_post_exec: " + last_issues);
	}
}

}
