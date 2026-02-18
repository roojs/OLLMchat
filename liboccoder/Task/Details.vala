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
	// — stored task content (exact keys only, see class doc)
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
	 * Call from parsing process, not from ctor.
	 * Accepts: #anchor (e.g. #project-description), output:task_name, http(s) URL, absolute file path (must exist).
	 */
	public void validate_references()
	{
		foreach (var link in this.reference_targets) {
			var href = link.href;
			if (href.has_prefix("#")) {
				// FIXME: validate #anchor format and existence; defer for now
				continue;
			}
			if (href.has_prefix("output:")) {
				continue;
			}
			if (href.has_prefix("http://") || href.has_prefix("https://")) {
				continue;
			}
			if (GLib.Path.is_absolute(href)) {
				if (!GLib.File.new_for_path(href).query_exists()) {
					this.issues += "\n" + "Invalid reference target \"" + href + "\": file does not exist.";
				}
				continue;
			}
			this.issues += "\n" + "Invalid reference target \"" + href + "\". "
				+ "Use only: #anchor (e.g. #project-description), output:task_name, http(s) URL, or absolute file path (must exist).";
		}
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
		var definition = this.skill_manager.fetch(this);
		var tpl = OLLMcoder.Skill.PromptTemplate.template("task_refinement.md");
		yield this.fill_model();
		var previous_output = "";
		for (var i = 0; i < 5; i++) {
			var file = this.runner.sr_factory.current_file();
			var messages = new Gee.ArrayList<OLLMchat.Message>();
			messages.add(new OLLMchat.Message("system", tpl.system_fill()));
			messages.add(new OLLMchat.Message("user", tpl.fill(
				"coarse_task", this.coarse_task_markdown(),
				"previous_output_issues", this.result_parser.issues == "" ? "" :
					tpl.header("Previous Output Issues", this.result_parser.issues),
				"previous_output", previous_output == "" ? "" :
					tpl.header("Previous Output", previous_output),
				"environment", this.runner.env(),
				// TODO: project description from active_project when available (OLLMfiles.Folder has no summary()); stubbed empty.
				// "project_description", this.runner.project_manager.active_project != null ? this.runner.project_manager.active_project.summary() : "",
				"project_description", "",
				"current_file", file == null ? "" : 
					tpl.header("Current File - " + file.path, file.get_contents(200)),
				"task_reference_contents", this.reference_contents(),
				"skill_details", definition.full_content)));
			

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
			previous_output = response_text;
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
	 * Coarse task as bulleted list: bold key, value (no "Key: value" line format).
	 * Note: no strip() on to_markdown() — Block does not add line breaks for paragraph/default.
	 */
	private string coarse_task_markdown()
	{
		return "- **What is needed** — " + this.task_data.get("What is needed").to_markdown() + "\n"
			+ "- **Skill** — " + this.task_data.get("Skill").to_markdown() + "\n"
			+ "- **References** — " + this.task_data.get("References").to_markdown() + "\n"
			+ "- **Expected output** — " + this.task_data.get("Expected output").to_markdown();
	}

	/**
	 * Resolved reference block for this task: loop reference_targets; for each,
	 * get content. File paths (absolute): from project manager, or File.new_fake
	 * if not in project; then create_buffer and get_contents. #section / output:
	 * from runner.
	 */
	private string reference_contents()
	{
		var ret = "";
		foreach (var link in this.reference_targets) {
			if (!GLib.Path.is_absolute(link.href)) {
				ret += this.reference_link_contents(link, this.runner.reference_content(link.href));
				continue;
			}
			var found = this.runner.sr_factory.project_manager.get_file_from_active_project(link.href);
			if (found == null) {
				found = new OLLMfiles.File.new_fake(this.runner.sr_factory.project_manager, link.href);
			}
			this.runner.sr_factory.project_manager.buffer_provider.create_buffer(found);
			ret += this.reference_link_contents(link, found.get_contents(0));
		}
		return ret;
	}

	private string reference_link_contents(Markdown.Document.Format link, string contents)
	{
		if (contents == "") {
			return "";
		}
		var fence = (contents.contains("\n```") || contents.has_prefix("```")) ? "~~~~" : "```";
		return "Reference information for " + link.title + "\n\nThe contents of " + link.href + "\n\n" + fence + "\n" + contents + "\n" + fence + "\n\n";
	}

	/**
	 * One reference: header (e.g. ### target) then body in a fenced code block. Use a fence that does not appear at line-start in content so nested ``` does not close our block (CommonMark: use tildes when content has ```).
	 */
	private string reference_block(string target, string content)
	{
		if (content == "") {
			return "";
		}
		var fence = (content.contains("\n```") || content.has_prefix("```")) ? "~~~~" : "```";
		return "### " + target + "\n\n" + fence + "\n" + content + "\n" + fence + "\n\n";
	}

	/**
	 * Executor precursor: reference_contents() (same refs as refine) then
	 * each tool call (name + JSON) and its output as headed blocks.
	 */
	private string executor_precursor()
	{
		var ret = this.reference_contents();
		foreach (var e in this.tool_outputs.entries) {
			ret += this.reference_block("Tool call " + e.key,
				Json.gobject_to_data(this.tool_calls.get(e.key), null));
			ret += this.reference_block("Tool call " + e.key + " Output", e.value);
		}
		return ret;
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
