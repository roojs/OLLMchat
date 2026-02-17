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
 * {@link extract_refinement}, and {@link extract_exec} each expect specific
 * sections and populate task_list / task / issues accordingly.
 *
 * How it fits in the task flow:
 *
 *  * Planning: Runner receives the planning response → ''new ResultParser(this, response)'',
 *    ''parse_task_list()''; caller uses ''parser.task_list'' and ''parser.issues''.
 *  * Refinement: Details.refine() receives the refinement response → new
 *    ResultParser, ''extract_refinement(this)''; task is updated and
 *    ''result_parser.issues'' checked.
 *  * Execution: Details.post_evaluate() receives the executor response → new
 *    ResultParser, ''extract_exec(this)''; ''task.result'' and
 *    ''task.result_document'' are set; on success Details sets ''exec_done''.
 *
 * @see List
 * @see Step
 * @see Details
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
	 * Parsed task list; set by {@link parse_task_list}. ''null'' until parsing succeeds.
	 */
	public List? task_list { get; set; default = null; }

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
	 * ''parse_task_list'', ''extract_refinement'', or ''extract_exec'' next.
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
	 * for success. Populates {@link task_list} on success.
	 */
	public void parse_task_list()
	{
		this.issues = "";
		this.task_list = null;

		foreach (var key in new string[] {
			"original-prompt",
			"goals-summary",
			"general-information-for-all-tasks",
			"tasks",
		}) {
			if (!this.document.headings.has_key(key)) {
				this.issues += "\n" + "Top-level structure: the response must contain these ## sections in order " +
					"— Original prompt, Goals / summary, General information for all tasks, Tasks. " +
					"Missing or misnamed: \"" + key + "\".";
				return;
			}
		}

		this.task_list = new List(this.runner);
		foreach (var key in this.document.headings.keys) {
			if (!key.has_prefix("task-section-")) {
				continue;
			}
			var step = this.parse_step(this.document.headings.get(key));
			if (step == null) {
				continue;
			}
			this.task_list.steps.add(step);
		}
	}

	/**
	 * Builds one {@link Step} from a task section heading.
	 *
	 * Walks ''section_heading.contents()'' in order. Ignores nodes that are not
	 * Block or List; Blocks that are not fenced code are skipped. Fenced code
	 * blocks are appended to ''last_task.code_blocks''; Lists are parsed as
	 * tasks (each list item → {@link Details} via ''ListItem.to_key_map()'').
	 * Returns ''null'' only when the section has no list at all (appends to
	 * {@link issues}).
	 *
	 * Example of what we parse (under ### Task section 1, ### Task section 2, …):
	 * {{{
	 * - **What is needed** — Add validation
	 *   **Skill** — skill_name
	 *   **References** — [file](path), [Project description](project_description)
	 *   **Expected output** — Tests pass
	 *
	 * - **What is needed** — Refactor X
	 *   **Skill** — other_skill
	 *   **References** — …
	 *   **Expected output** — …
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
			// node is List; list children are ListItem (per document model)
			found_any_list = true;
			var list_block = (Markdown.Document.List) node;
			foreach (var list_child in list_block.children) {
				var list_item = (Markdown.Document.ListItem) list_child;
				var task_data = list_item.to_key_map();
				var task = new Details(this.runner, this.runner.factory, this.runner.session, task_data);
				task.validate_references();
				if (task.issues != "") {
					this.issues += "\n" + "Section \"" + section_heading.to_markdown() +
						"\", a task in this section (References): " + task.issues;
					continue;
				}
				step.children.add(task);
				last_task = task;
			}
		}
		if (!found_any_list) {
			this.issues += "\n" + "Section \"" + section_heading.to_markdown() +
				 "\": this section must contain at least one list of tasks. " + 
				 "Each list item is one task (nested list with " + 
				 " **What is needed**, **Skill**, **References**, **Expected output**). "  + 
				 "No list was found under \"" + section_heading.to_markdown() + 
				 	"\" — add a list there as in the output format.";
			return null;
		}
		return step;
	}

	/**
	 * Parses single-task refinement output.
	 *
	 * Expects section "Task": walk contents — List → first
	 * ''ListItem.to_key_map()'' → ''task.update_props(map)''; Block (FENCED_CODE)
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
			var list_item = (Markdown.Document.ListItem) list_block.children.get(0);
			task.update_props(list_item.to_key_map());
			if (task.issues != "") {
				this.issues += "\n" + "Section \"Task\" (References): " + task.issues;
			}
			break;
		}
		if (!found_list) {
			this.issues += "\n" + "Section \"Task\": must contain a list with one item " +
				"(nested list **What is needed**, **Skill**, **References**, **Expected output**, **Skill call**). " +
				"No list was found — add a list there as in the output format.";
			return;
		}
		if (!this.document.headings.has_key("tool-calls")) {
			this.document.headings.set("tool-calls", new Markdown.Document.Block(Markdown.FormatType.PARAGRAPH));
		}
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
			var tool = new Tool(task);
			if (!tool.parse(block)) {
				task.issues += tool.issues;
				continue;
			} 
			tool_index++;
			tool.tool_call.id = tool.name + "_" + tool_index.to_string();
			if (!tool.validate()) {
				task.issues += tool.issues;
				continue;
			}
			
			task.tools.add(tool);
		}
	}

	/**
	 * Fills in the result summary on the task and sets ''task.result_document''.
	 *
	 * Single pass: find section "Result summary" → ''task.result'' = section
	 * content; ''task.result_document'' = this document. If no "Result summary"
	 * section, appends to {@link issues}. No parsing of filename or other details.
	 *
	 * Content we expect (task_execution.md / 1.23.6):
	 * {{{
	 * ## Result summary
	 * We have the information we need; it is complete.
	 * }}}
	 *
	 * @param task the task to set ''result'' and ''result_document'' on
	 */
	public void extract_exec(Details task)
	{
		task.result = "";
		task.result_document = this.document;
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
