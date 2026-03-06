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
 * Parses structured markdown responses from the LLM into task data and results.
 *
 * Purpose: Turn raw LLM output (planning, refinement, or executor responses) into
 * in-memory structures (List/Step/Details) and fill task properties. Validation
 * failures are accumulated in {@link issues} so the caller can retry or report.
 *
 * Constructor builds a ''Markdown.Document''; {@link parse_task_list},
 * {@link extract_refinement}, {@link extract_exec}, and {@link exec_extract} each expect specific
 * sections and populate task_list / task / issues accordingly.
 *
 * How it fits in the task flow:
 *
 *  * Planning: Runner receives the planning response → ''new ResultParser(this, response)'',
 *    ''parse_task_list()''; caller uses ''runner.task_list'' and ''parser.issues''.
 *  * Refinement: Details.refine() receives the refinement response → new
 *    ResultParser, ''extract_refinement(this)''; task is updated and
 *    ''result_parser.issues'' checked.
 *  * Execution: Tool.run() receives the executor response → new ResultParser,
 *    ''exec_extract(ex)''; ex.summary and ex.document are set. Details.run_exec() builds
 *    ''task.result'' from exec_runs summaries; on success Details sets ''exec_done''.
 *    ''extract_exec(Details)'' remains for legacy/test use (sets task.result only).
 *
 * @see List
 * @see Step
 * @see Details
 * @see Tool
 */
public class ResultParser : Object
{
	/**
	 * Document built in constructor; extraction methods read from this.
	 */
	private Markdown.Document.Document document;

	/**
	 * Runner used by {@link parse_task_list} to build {@link Details}. Set in constructor.
	 */
	private OLLMcoder.Skill.Runner runner;

	/**
	 * Raw response string passed to the constructor.
	 */
	public string proposal { get; set; default = ""; }

	/**
	 * Validation failure messages appended on each failure.
	 *
	 * Every message must include context so the LLM can locate the problem:
	 * which section/task, what is wrong, what to do. Caller checks ''issues == ""''
	 * for success.
	 */
	public string issues { get; set; default = ""; }

	/**
	 * Builds document from response (''Markdown.Document.Render''). Call
	 * ''parse_task_list'', ''extract_refinement'', ''extract_exec'', or ''exec_extract'' next.
	 *
	 * @param runner skill runner; used by ''parse_task_list()'' to build Details and List
	 * @param response raw LLM markdown response (planning, refinement, or executor)
	 */
	public ResultParser(OLLMcoder.Skill.Runner runner, string response)
	{
		this.runner = runner;
		this.proposal = response;
		var render = new Markdown.Document.Render();
		render.parse(response);
		this.document = render.document;
	}

	/**
	 * Parses task list from document; uses ''runner'' from constructor to build {@link Details}.
	 *
	 * Appends to {@link issues} on each failure. Caller checks ''parser.issues == ""''
	 * for success. Populates {@link runner}.task_list on success.
	 */
	public void parse_task_list()
	{
		this.issues = "";
		this.runner.task_list = null;

		foreach (var key in new string[] { "original-prompt", "goals-summary", "tasks" }) {
			if (!this.document.headings.has_key(key)) {
				this.issues += "\n" + "Top-level structure: the response must contain these ## sections:" + 
					" Original prompt, Goals / summary, Tasks. Missing or misnamed: \"" + key + "\".";
				continue;
			}
		}

		this.runner.task_list = new List(this.runner);
		// Require task sections (### Task section 1, …) as per task_creation_initial.md and task_list_iteration.md; do not change.
		foreach (var key in this.document.headings.keys) {
			if (!key.has_prefix("task-section-")) {
				continue;
			}
			var step = this.parse_step(this.document.headings.get(key));
			if (step == null) {
				continue;
			}
			this.runner.task_list.steps.add(step);
		}
		if (!this.document.headings.has_key("goals-summary")) {
			this.runner.task_list = null;
			return;
		}
		this.runner.task_list.goals_summary_md = 
			this.document.headings.get("goals-summary").to_markdown_with_content();
		this.runner.task_list.fill_names();
		var steps = this.runner.task_list.steps;
		for (var i = 0; i < steps.size; i++) {
			var step = steps.get(i);
			foreach (var t in step.children) {
				t.step_index = i;
				if (t.slug() != "") {
					this.runner.task_list.slugs.set(t.slug(), t);
				}
				t.validate_references();
				if (t.issues != "") {
					this.issues += "\n" + "Task (References): " + t.issues;
				}
			}
		}
		if (this.issues != "") {
			this.runner.task_list = null;
		}
	}

	/**
	 * Builds one {@link Step} from a task section heading.
	 *
	 * Walks ''section_heading.contents()'' in order. Ignores nodes that are not
	 * Block or List; Blocks that are not fenced code are skipped. Fenced code
	 * blocks are appended to ''last_task.code_blocks''; Lists are parsed as
	 * tasks (each list → one {@link Details} via ''List.to_key_map()'').
	 * Returns ''null'' only when the section has no list at all (appends to
	 * {@link issues}).
	 *
	 * Example of what we parse (under ### Task section 1, ### Task section 2, …):
	 * {{{
	 * - **What is needed** Add validation
	 *   **Skill** skill_name
	 *   **References** [file](path), [Project description](project_description)
	 *   **Expected output** Tests pass
	 *
	 * - **What is needed** Refactor X
	 *   **Skill** other_skill
	 *   **References** …
	 *   **Expected output** …
	 *
	 * ```optional code block (attaches to previous task)
	 * some code
	 * ```
	 * }}}
	 *
	 * @param section_heading the "Task section N" heading block
	 * @return the step, or ''null'' if section has no list
	 */
	private Step? parse_step(Markdown.Document.Block section_heading)
	{
		var step = new Step();
		Details? last_task = null;
		var found_any_list = false;
		foreach (var node in section_heading.contents()) {
			if (!(node is Markdown.Document.Block) && !(node is Markdown.Document.List)) {
				continue;
			}
			if (node is Markdown.Document.Block) {
				if (last_task == null) {
					continue;
				}
				var block = (Markdown.Document.Block) node;
				if (block.kind != Markdown.FormatType.FENCED_CODE_QUOTE 
					&& block.kind != Markdown.FormatType.FENCED_CODE_TILD) {
					continue;
				}
				last_task.code_blocks.add(block);
				continue;
			}
			// node is List; one list → one task (to_key_map returns map from list items)
			found_any_list = true;
			var list_block = (Markdown.Document.List) node;
			var task_data = list_block.to_key_map();
			var task = new Details(this.runner, this.runner.sr_factory, this.runner.session, task_data);
			step.children.add(task);
			last_task = task;
		}
		if (!found_any_list) {
			this.issues += "\n" + "Section \"" + section_heading.to_markdown() +
				 "\": this section must contain at least one list of tasks. " + 
				 "Each list item is one task (nested list with " + 
				 " **What is needed**, **Skill**, **References**, **Expected output**). "  + 
				 "No list was found under \"" + section_heading.to_markdown() + 
				 	"\" - add a list there as in the output format.";
			return null;
		}
		return step;
	}

	/**
	 * Parses single-task refinement output.
	 *
	 * Expects section "Task": walk contents - List → first
	 * ''List.to_key_map()'' → ''task.update_props(map)''; Block (FENCED_CODE)
	 * → ''task.code_blocks.add(block)''. Appends to {@link issues} on missing
	 * section/list or task validation. Content format: **What is needed**, **Skill**,
	 * **References**, **Expected output**, **Skill call**; optional fenced code block.
	 *
	 * @param task the task to update with refined props and code blocks
	 */
	public void extract_refinement(Details task)
	{
		if (!this.document.headings.has_key("task")) {
			this.issues += "\n" + "Output must include a \"Task\" section. " +
				"No such section was found. Produce a Task section with a list containing " +
				"**What is needed**, **Skill**, **References**, **Expected output**, and **Skill call**.";
			return;
		}
		var found_list = false;
		foreach (var node in this.document.headings.get("task").contents()) {
			if (!(node is Markdown.Document.Block) && !(node is Markdown.Document.List)) {
				continue;
			}
			if (node is Markdown.Document.Block) {
				var block = (Markdown.Document.Block) node;
				if (block.kind != Markdown.FormatType.FENCED_CODE_QUOTE 
					&& block.kind != Markdown.FormatType.FENCED_CODE_TILD) {
					continue;
				}
				task.code_blocks.add(block);
				continue;
			}
			found_list = true;
			var list_block = (Markdown.Document.List) node;
			if (list_block.children.size == 0) {
				this.issues += "\n" + "Section \"Task\": the list must contain at least one item " +
					"(**What is needed**, **Skill**, **References**, " +
					"**Expected output**, **Skill call**).";
				return;
			}
			task.update_props(list_block.to_key_map());
			if (task.issues != "") {
				this.issues += "\n" + "Section \"Task\" (References): " + task.issues;
			}
			break;
		}
		if (!found_list) {
			this.issues += "\n" + "Section \"Task\": must contain a list with one item " +
				"(nested list **What is needed**, **Skill**, **References**, **Expected output**, **Skill call**). " +
				"No list was found - add a list there as in the output format.";
			return;
		}
		if (!this.document.headings.has_key("tool-calls")) {
			this.document.headings.set("tool-calls", new Markdown.Document.Block(Markdown.FormatType.PARAGRAPH));
		}
		var factory = (OLLMchat.Agent.Factory) this.runner.sr_factory;
		var tool_index = 0;
		foreach (var node in this.document.headings.get("tool-calls").contents()) {
			if (!(node is Markdown.Document.Block)) {
				continue;
			}
			var block = (Markdown.Document.Block) node;
			if (block.kind != Markdown.FormatType.FENCED_CODE_QUOTE
				&& block.kind != Markdown.FormatType.FENCED_CODE_TILD) {
				continue;
			}
			var tool = new Tool(factory, this.runner.session, task, "");
			if (!tool.parse(block)) {
				this.issues += "\n" + tool.issues + 
					" Raw block:\n\n```json\n" + block.code_text + "\n```\n\n";
				continue;
			}
			tool_index++;
			tool.tool_call.id = tool.name + "_" + tool_index.to_string();
			if (!tool.validate()) {
				this.issues += "\n" + tool.issues + 
					" Raw block:\n\n```json\n" + block.code_text + "\n```\n\n";
				continue;
			}
			task.tools.add(tool);
		}
		// Require at least one of References or Tool calls so execution has precursor content.
		if (task.reference_targets.size == 0 && task.tools.size == 0) {
			this.issues += "\n" + "Refinement must provide at least one of References or Tool calls. " +
				"This task has neither; add markdown links in References and/or fenced JSON blocks in " +
				" ## Tool Calls so execution has precursor content.";
		}
	}

	/**
	 * Parse executor response into the given Tool (exec run). Called by Tool.run().
	 * On success sets ex.summary and ex.document; on failure appends to issues.
	 *
	 * @param ex the Tool (exec run) to fill with result summary and document
	 * @return true on success; false on missing Result summary (issues appended)
	 */
	public bool exec_extract(Tool ex)
	{
		if (!this.document.headings.has_key("result-summary")) {
			this.issues += "\n" + "This task's executor output must include a \"Result summary\" section (required). " +
				"It was missing or not found in the response. " +
				"Produce a result summary (what was found or produced; whether complete or more work needed).";
			return false;
		}
		var summary = this.document.headings.get("result-summary").to_markdown_with_content().strip();
		ex.summary = summary;
		ex.document = this.document;
		return true;
	}

	/**
	 * Fills in the result summary on the task from executor response.
	 *
	 * Single pass: find section "Result summary" → ''task.result'' = section content.
	 * If no "Result summary" section, appends to {@link issues}. No parsing of filename or other details.
	 * Used by legacy/test paths; normal execution uses exec_extract(Tool) and task.result from exec_runs.
	 *
	 * Content we expect (task_execution.md):
	 * {{{
	 * ## Result summary
	 * We have the information we need; it is complete.
	 * }}}
	 *
	 * @param task the task to set ''result'' on
	 */
	public void extract_exec(Details task)
	{
		task.result = "";
		if (!this.document.headings.has_key("result-summary")) {
			this.issues += "\n" + "This task's executor output must include a \"Result summary\" section (required). " +
				"It was missing or not found in the response. " +
				"Produce a result summary (what was found or produced; whether complete or more work needed).";
			return;
		}
		string[] parts = {};
		foreach (var node in this.document.headings.get("result-summary").contents()) {
			if (node is Markdown.Document.Block) {
				parts += ((Markdown.Document.Block) node).to_markdown();
			}
		}
		task.result = string.joinv("\n\n", parts).strip();
	}
}

}
