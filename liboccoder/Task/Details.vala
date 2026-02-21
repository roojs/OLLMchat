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
	EXECUTION
}

/**
 * One task in the plan. Built from task list output; updated from refinement output.
 *
 * Task list (input): each list item under a task section heading has a nested list
 * with labels ''What is needed'', ''Skill'', ''References'', ''Expected output''.
 * Links in References: project_description, current_file, paths, plan:...
 * Keys are exactly these labels (no other format accepted):
 * "What is needed", "Skill", "References", "Expected output", "Requires user approval".
 *
 * Refined task (refinement output): section "Refined task" with same list plus
 * ''Skill call'' and an optional fenced code block. Parser uses ListItem.to_key_map()
 * for both; update_props(refined_map); code added directly to code_blocks.
 */
public class Details : OLLMchat.Agent.Base
{
	// - stored task content (exact keys only, see class doc)
	/**
	 * Map from ListItem.to_key_map(); keys are exact labels only. All task content is read from here.
	 */
	public Gee.Map<string, Markdown.Document.Block> task_data {
		get; set; default = new Gee.HashMap<string, Markdown.Document.Block>(); }

	/**
	 * True when this task should gate execution (e.g. modifies files); from task list format.
	 */
	public bool requires_user_approval { get; set; default = false; }

	/**
	 * True after post_evaluate success; result and result_document then valid.
	 */
	public bool exec_done { get; set; default = false; }

	/**
	 * Validation errors; append with this.issues += "\n" + msg. Parser checks and appends with section context.
	 */
	public string issues { get; set; default = ""; }

	/**
	 * Executor output summary (Result summary section).
	 */
	public string result { get; set; default = ""; }

	/**
	 * Runner; used for env, content_for_reference when filling prompts.
	 */
	public weak OLLMcoder.Skill.Runner runner { get; set; }

	/** Alias to runner.sr_factory.skill_manager (no setter). */
	public OLLMcoder.Skill.Manager skill_manager {
		get { return this.runner.sr_factory.skill_manager; }
	}

	/**
	 * Parser for last refine or executor response; result/result_document valid after exec_done.
	 * Initialized in ctor so issues is always available.
	 */
	public ResultParser result_parser { get; set; }

	/**
	 * Executor output document.
	 */
	public Markdown.Document.Document? result_document { get; set; default = null; }

	/**
	 * Markdown links from references block (project_description, paths, plan:...);
	 * Runner resolves for prompt fill. Filled in fill_task_data().
	 */
	public Gee.ArrayList<Markdown.Document.Format> reference_targets { 
		get; set; default = new Gee.ArrayList<Markdown.Document.Format>(); }

	/**
	 * Tool calls to run (key = tool name); filled by parsing code_blocks in run_tools.
	 */
	public Gee.HashMap<string, OLLMchat.Response.ToolCall> tool_calls { 
		get; set; default = new Gee.HashMap<string, OLLMchat.Response.ToolCall>(); }

	/**
	 * Tool outputs by name; used in executor precursor.
	 */
	public Gee.HashMap<string, string> tool_outputs {
		 get; set; default = new Gee.HashMap<string, string>(); }

	/**
	 * Code blocks from refinement (parser); add directly. Details parses into tool_calls.
	 */
	public Gee.ArrayList<Markdown.Document.Block> code_blocks { 
		get; set; default = new Gee.ArrayList<Markdown.Document.Block>(); }

	/**
	 * Tool instances from ## Tool Calls section (ResultParser); run_tools() yields tool.execute() for each.
	 */
	public Gee.ArrayList<Tool> tools { get; set; default = new Gee.ArrayList<Tool>(); }

	/**
	 * Initial task_data from ListItem.to_key_map() for one task list item (keys: exact labels only, see class doc).
	 */
	public Details(
		OLLMcoder.Skill.Runner runner,
		OLLMchat.Agent.Factory factory,
		OLLMchat.History.SessionBase session,
		Gee.Map<string, Markdown.Document.Block> task_data)
	{
		base(factory, session);
		this.runner = runner;
		this.task_data = task_data;
		this.issues = "";
		this.result_parser = new ResultParser(this.runner, "");
		this.fill_task_data();
	}

	private void fill_task_data()
	{
		this.requires_user_approval = this.task_data.has_key("Requires user approval");
		string[] keys_to_fill = {
			"What is needed",
			"Skill",
			"References",
			"Expected output" };
		var empty = new Markdown.Document.Block(Markdown.FormatType.PARAGRAPH);
		foreach (var key in keys_to_fill) {
			if (!this.task_data.has_key(key)) {
				this.task_data.set(key, empty);
			}
		}
		this.reference_targets = this.task_data.get("References").links();
	}

	/**
	 * Apply refined task map: set each key from refined_map into this.task_data, then re-run fill.
	 */
	public void update_props(Gee.Map<string, Markdown.Document.Block> refined_map)
	{
		this.issues = "";
		foreach (var e in refined_map.entries) {
			this.task_data.set(e.key, e.value);
		}
		this.fill_task_data();
	}

	/**
	 * Validate reference_targets hrefs; append to issues on invalid.
	 * Call from parsing process after fill_names (pass list so task-output anchors can be validated).
	 * Accepts: #anchor (document section or task output e.g. #slug-N-results), http(s) URL (TODO: validate later, see 1.23.20), absolute file path (must exist).
	 */
	public void validate_references()
	{
		foreach (var link in this.reference_targets) {
			var href = link.href;
			if (href.has_prefix("#")) {
				var anchor = href.substring(1);
				if (anchor.has_suffix("-results")) {
					var name_slug = anchor.substring(0, anchor.length - "-results".length);
					if (!this.runner.task_list.has_slug(name_slug)) {
						this.issues += "\n" + "Invalid reference target \"" +
							 href + "\": no task for \"" + name_slug + "\".";
					}
					continue;
				}
				if (!this.runner.user_request.headings.has_key(anchor)) {
					this.issues += "\n" + "Invalid reference target \"" +
						 href + "\": unknown anchor \"" + anchor + "\".";
				}
				continue;
			}
			if (href.has_prefix("http://") || href.has_prefix("https://")) {
				// TODO: http(s) validation deferred to 1.23.20 (post-testing-changes)
				continue;
			}
			if (GLib.Path.is_absolute(href)) {
				if (!GLib.File.new_for_path(href).query_exists()) {
					this.issues += "\n" + "Invalid reference target \"" + href + "\": file does not exist.";
				}
				continue;
			}
			this.issues += "\n" + "Invalid reference target \"" + href + "\". "
				+ "Use only: #anchor (e.g. #project-description, #task-name-results), http(s) URL, or absolute file path (must exist).";
		}
	}

	/**
	 * If task_data has no "Name" or empty, set Name = (Skill or "Task") + " " + index. Single method.
	 */
	public void fill_name(int i)
	{
		var name_block = this.task_data.has_key("Name") ?
			this.task_data.get("Name").to_markdown().strip() : "";
		if (name_block != "") {
			return;
		}
		// Allow empty skill; validate_skills() will report this as a bad task.
		var skill = this.task_data.has_key("Skill") ?
			this.task_data.get("Skill").to_markdown().strip() : "";
		var name = (skill != "" ? skill : "Task") + " " + i.to_string();
		var b = new Markdown.Document.Block(Markdown.FormatType.PARAGRAPH);
		b.adopt(new Markdown.Document.Format.from_text(name));
		this.task_data.set("Name", b);
	}

	/**
	 * This task's name as slug (e.g. "Research 1" → "research-1"). "" if no Name in task_data or empty.
	 */
	public string slug()
	{
		if (!this.task_data.has_key("Name")) {
			return "";
		}
		var name = this.task_data.get("Name").to_markdown().strip();
		if (name == "") {
			return "";
		}
		var s = new GLib.Regex("[^a-z0-9]+").replace(name.down(), -1, 0, "-");
		return new GLib.Regex("^-+|-+$").replace(s, -1, 0, "");
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
	 * Build refinement prompt template (no current_file; reference_contents includes
	 * current file when in the task's References).
	 */
	public OLLMcoder.Skill.PromptTemplate refinement_prompt() throws GLib.Error
	{
		var definition = this.skill_manager.fetch(this);
		var tpl = OLLMcoder.Skill.PromptTemplate.template("task_refinement.md");
		tpl.system_fill();
		tpl.fill(
			"issues", tpl.header_raw("Issues with the current call", this.result_parser.issues),
			"task_data", tpl.header_raw("Task", this.to_markdown(MarkdownPhase.REFINEMENT)),
			"environment", this.runner.env(),
			"project_description", (this.runner.sr_factory.project_manager.active_project == null ?
				"" : this.runner.sr_factory.project_manager.active_project.project_description()),
			"task_reference_contents", this.reference_contents(),
			"skill_details", definition.full_content);
		return tpl;
	}

	/**
	 * Refinement: fill template. Caller has validated via skill_manager.validate(this);
	 * definition from skill_manager.fetch(this) is non-null. Details builds
	 * task_reference_contents by looping reference_targets and asking Runner for each item
	 * (see "Building the task reference block").
	 * Up to 5 refinement attempts; up to 3 communication retries per attempt.
	 * Caller (Runner) must catch and report to user; see 1.23.14.
	 */
	public async void refine() throws GLib.Error
	{
		this.refined_done = false;
		this.refine_error = null;
		yield this.fill_model();
		for (var i = 0; i < 5; i++) {
			var tpl = this.refinement_prompt();
			var messages = new Gee.ArrayList<OLLMchat.Message>();
			messages.add(new OLLMchat.Message("system", tpl.filled_system));
			messages.add(new OLLMchat.Message("user", tpl.filled_user));

			string response_text = "";
			for (var attempt = 0; attempt < 3; attempt++) {
				try {
					var response = yield this.chat_call.send(messages, null);
					response_text = response != null ? (response.message.content ?? "") : "";
					break;
				} catch (GLib.Error e) {
					if (attempt != 2) {
						continue;
					}
					this.refine_error = new GLib.IOError.INVALID_ARGUMENT("Task refinement: " + e.message);
					throw this.refine_error;
				}
			}
			this.result_parser = new ResultParser(this.runner, response_text);
			this.result_parser.extract_refinement(this);
			if (this.result_parser.issues == "") {
				this.refined_done = true;
				if (this.resume_refined != null) {
					this.resume_refined();
				}
				return;
			}
		}
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
			this.add_message(new OLLMchat.Message("ui", "skill using " + skill_model + " model."));
			return;
		}
		if (skill_model != "") {
			this.add_message(new OLLMchat.Message("ui-warning",
				"The skill requested the model \"" + skill_model + "\", but it was not available. Using your selected model instead."));
		}
		yield base.fill_model();
	}

	/**
	 * Task as markdown for a given phase. Does not add section headings (e.g. ## Task); caller adds header.
	 * COARSE: creation keys. REFINEMENT: task list + ## Tool Calls when tools exist. LIST: task list + Output when exec_done. EXECUTION: same as REFINEMENT for Tool Calls.
	 */
	public string to_markdown(MarkdownPhase phase)
	{
		string[] order = {
			"Name",
			"What is needed",
			"Skill",
			"References",
			"Expected output",
			"Output"
		};
		var ret = "";
		for (var i = 0; i < order.length; i++) {
			var key = order[i];
			switch (key) {
				case "Output":
					if (phase != MarkdownPhase.LIST || !this.exec_done || this.result == "") {
						continue;
					}
					ret += "- **Output** " + this.result.replace("\n", " ") + "\n";
					continue;
				default:
					if (!this.task_data.has_key(key)) {
						continue;
					}
					break;
			}
			ret += "- **" + key + "** " + this.task_data.get(key).to_markdown() + "\n";
		}
		// Include ## Tool Calls for REFINEMENT (retry) and EXECUTION. Omit section when no tools.
		if (phase != MarkdownPhase.REFINEMENT && phase != MarkdownPhase.EXECUTION && this.tools.size == 0) {
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


	/** Line + unfenced body. Use for reference #anchor. */
	private string header_raw(string line, string body)
	{
		if (body == "") {
			return "";
		}
		return line + "\n\n" + body + "\n\n";
	}

	/** Line + fenced body; content and language from file. Use for reference file path. Exception: we do output the header (and empty block if needed) when content is empty. */
	private string header_file(string line, OLLMfiles.File file)
	{
		var content = file.get_contents(0);
		var fence = (content.index_of("\n```") >= 0 || content.has_prefix("```")) ? "~~~~" : "```";
		return line + "\n\n"
			+ fence
			+ (file.language != "" ? file.language + "\n" : "\n")
			+ content + "\n"
			+ fence + "\n\n";
	}

	/** Line + fenced body with type (e.g. "json", "text"). Use for tool call/output. */
	private string header_fenced(string line, string body, string type = "")
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
	 * Resolved reference block for this task: loop reference_targets; for each,
	 * get content. File paths (absolute): from project manager, or File.new_fake
	 * if not in project; then create_buffer and get_contents. #anchor from runner.
	 */
	private string reference_contents()
	{
		var parts = "";
		foreach (var link in this.reference_targets) {
			if (!GLib.Path.is_absolute(link.href)) {
				var content = this.runner.reference_content(link.href);
				if (content != "") {
					parts += this.header_raw(
						"Reference information for " + link.title + "\n\nThe contents of " + link.href,
						content);
				}
				continue;
			}
			var found = this.runner.sr_factory.project_manager.get_file_from_active_project(link.href);
			if (found == null) {
				found = new OLLMfiles.File.new_fake(this.runner.sr_factory.project_manager, link.href);
			}
			this.runner.sr_factory.project_manager.buffer_provider.create_buffer(found);
			parts += this.header_file(
				"Reference information for " + link.title + "\n\nThe contents of " + link.href,
				found);
		}
		return parts;
	}

	/**
	 * Executor precursor: reference_contents() (same refs as refine) then
	 * each tool call (name + JSON) and its output as headed blocks.
	 */
	private string executor_precursor()
	{
		var parts = this.reference_contents();
		foreach (var e in this.tool_outputs.entries) {
			var json = Json.gobject_to_data(this.tool_calls.get(e.key), null);
			if (json != "") {
				parts += this.header_fenced("### Tool call " + e.key, json, "json");
			}
			if (e.value != "") {
				parts += this.header_fenced("### Tool call " + e.key + " Output", e.value, "text");
			}
		}
		return parts;
	}

	/** Run each tool in sequence. TODO: concurrent execution to be added later. */
	public async void run_tools() throws GLib.Error
	{
		foreach (var tool in this.tools) {
			yield tool.execute();
		}
	}

	/**
	 * Executor: fill template. Precursor = same reference content as refine
	 * (reference_contents()) plus this task's tool_outputs in same
	 * header+code-block format; Details builds from refs and tool_outputs.
	 * Definition from skill_manager.fetch(this).
	 * Up to 5 attempts; up to 3 communication retries per attempt (same as refine).
	 */
	public async void post_evaluate() throws GLib.Error
	{
		var definition = this.skill_manager.fetch(this);
		var tpl = OLLMcoder.Skill.PromptTemplate.template("task_execution.md");
		for (var i = 0; i < 5; i++) {
			var messages = new Gee.ArrayList<OLLMchat.Message>();
			messages.add(new OLLMchat.Message("system", tpl.system_fill()));
			messages.add(new OLLMchat.Message("user", tpl.fill(
				"query", this.task_data.get("What is needed").to_markdown(),
				"skill_definition", definition.full_content,
				"precursor", this.executor_precursor())));
			string response_text = "";
			for (var attempt = 0; attempt < 3; attempt++) {
				try {
					var response = yield this.chat_call.send(messages, null);
					response_text = response != null ? (response.message.content ?? "") : "";
					break;
				} catch (GLib.Error e) {
					if (attempt != 2) {
						continue;
					}
					throw e;
				}
			}
			this.result_parser = new ResultParser(this.runner, response_text);
			this.result_parser.extract_exec(this);
			if (this.result_parser.issues == "") {
				this.exec_done = true;
				return;
			}
		}
		throw new GLib.IOError.INVALID_ARGUMENT("Task executor: " + this.result_parser.issues);
	}
}

}
