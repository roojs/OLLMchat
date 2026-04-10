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
 * Which task-list or executor ''phase'' is active for markdown generation, link validation,
 * and (on restore) transcript replay.
 *
 * ''Prompt / markdown:'' {@link Details.to_markdown}, {@link Step.to_markdown}, and
 * {@link List.to_markdown} take a ''PhaseEnum'' to include the right sections (e.g. tool calls,
 * result summary, references). ''Validation:'' {@link ValidateLink} and {@link ResolveLink}
 * branch on stage so list vs refinement vs executor output get the correct rules.
 *
 * ''Live wire ids:'' the skill runner adds ''agent-stage'' messages whose body is a short id
 * (''task_list_parse'', ''refinement'', ''exec'', …). {@link from_string} maps those strings
 * here; {@link to_string} maps back for stages the live flow emits (others yield '''').
 *
 * == Markdown and planning phases ==
 *
 *  * ''COARSE'' / ''REFINEMENT'' / ''LIST'' — task list and refinement: coarse creation keys,
 *    refined task block, or outstanding list (+ optional executor result summary when
 *    ''exec_done'') for prompts.
 *  * ''REFINE_COMPLETED'' — completed-task markdown for iteration prompts (omits certain
 *    reference sections; see {@link Details.to_markdown}).
 *  * ''EXECUTION'' / ''POST_EXEC'' — executor LLM output vs post-exec synthesis; used in
 *    {@link ResultParser.exec_extract}, {@link ResultParser.exec_post_extract}, and matching
 *    {@link ValidateLink} behavior.
 *
 * == Replay-only and sentinel ==
 *
 *  * ''NONE'' — not a live stage: {@link from_string} default for unknown ids; GTK replay uses
 *    it only until the first ''agent-stage'' applies.
 *  * ''TASK_LIST_ITERATION'' — parsing a revised list ({@link ResultParser.parse_task_list_iteration}).
 *  * ''EXEC_VALIDATE'' — validating executor writes after ''exec''; replay cursor advances here
 *    while consuming ''exec_validate'' / validate ''agent-issues'' rows.
 *
 * @see Details.to_markdown
 * @see List.to_markdown
 * @see ValidateLink
 * @see OLLMcoder.Skill.Runner.on_replay
 */
public enum PhaseEnum
{
	/**
	 * Task list ''creation'' keys only (initial planning shape); see {@link Details.to_markdown}.
	 */
	COARSE,
	/**
	 * Refined task block; refinement prompts and bounded file previews in references.
	 */
	REFINEMENT,
	/**
	 * Progress UI: refinement parse succeeded; awaiting **`run_exec`** (or **`wait_refined`** resume).
	 * Not shown in the status column — {@link to_human} returns empty (same as {@link NONE} for display).
	 */
	REFINED,
	/**
	 * Outstanding task list markdown (iteration / execution context); may include task result
	 * output when ''exec_done''.
	 */
	LIST,
	/**
	 * Progress UI: task list creation retry after parse failure ({@link OLLMcoder.Skill.Runner.send_async}).
	 */
	LIST_RETRY,
	/**
	 * Completed tasks aggregate for prompts (e.g. task list iteration); not a wire ''agent-stage'' id.
	 */
	REFINE_COMPLETED,
	/**
	 * Executor LLM output (''Result summary'', tool calls); {@link Tool.run} and
	 * {@link ResultParser.exec_extract}.
	 */
	EXECUTION,
	/**
	 * Post-execution synthesis ({@link ResultParser.exec_post_extract}, {@link Details.run_post_exec}).
	 */
	POST_EXEC,
	/**
	 * Sentinel: unknown stage id, or replay bootstrap before the first ''agent-stage'' message.
	 */
	NONE,
	/**
	 * Revised task list from iteration; pairs with wire ''task_list_iteration''.
	 */
	TASK_LIST_ITERATION,
	/**
	 * Progress UI: task list iteration retry after parse failure ({@link OLLMcoder.Skill.Runner.run_task_list_iteration}).
	 */
	TASK_LIST_ITERATION_RETRY,
	/**
	 * Post-exec validation of writes; pairs with wire ''exec_validate'' and replay validate steps.
	 */
	EXEC_VALIDATE,
	/**
	 * Progress UI: native tool hook in flight ({@link Tool.run}).
	 */
	TOOLS_RUNNING,
	/**
	 * Progress UI: same executor pass retrying after send / parse / validate failure ({@link Tool.run} loop).
	 */
	EXECUTION_RETRY,
	/**
	 * Progress UI: applying parsed write_file operations ({@link Tool.run}).
	 */
	EXEC_WRITE,
	/**
	 * Progress UI: retries exhausted or unrecoverable failure ({@link Tool.run},
	 * {@link OLLMcoder.Skill.Runner.send_async}, {@link OLLMcoder.Skill.Runner.run_task_list_iteration}).
	 */
	ERROR,
	/**
	 * Progress UI: row finished (task or tool pass).
	 */
	COMPLETED;

	/**
	 * Map a persisted ''agent-stage'' message body to a phase (e.g. ''task_list_parse'' → {@link LIST}).
	 *
	 * @param id wire content from an ''agent-stage'' row
	 * @return matching phase, or {@link NONE} if the id is not recognized
	 */
	public static PhaseEnum from_string(string id)
	{
		switch (id) {
		case "task_list_parse":
			return PhaseEnum.LIST;
		case "task_list_iteration":
			return PhaseEnum.TASK_LIST_ITERATION;
		case "refinement":
			return PhaseEnum.REFINEMENT;
		case "exec":
			return PhaseEnum.EXECUTION;
		case "post_exec":
			return PhaseEnum.POST_EXEC;
		case "exec_validate":
			return PhaseEnum.EXEC_VALIDATE;
		default:
			return PhaseEnum.NONE;
		}
	}

	/**
	 * Stable wire id for ''agent-stage'' messages for phases the live flow emits.
	 *
	 * Returns '''' for {@link NONE}, {@link COARSE}, {@link REFINED}, {@link REFINE_COMPLETED}, and any value
	 * not listed explicitly (those stages are not sent as ''agent-stage'' bodies).
	 *
	 * @return id string (''exec'', ''exec_validate'', …) or empty string
	 */
	public string to_string()
	{
		switch (this) {
		case NONE:
			return "";
		case LIST:
			return "task_list_parse";
		case TASK_LIST_ITERATION:
			return "task_list_iteration";
		case REFINEMENT:
			return "refinement";
		case EXECUTION:
			return "exec";
		case POST_EXEC:
			return "post_exec";
		case EXEC_VALIDATE:
			return "exec_validate";
		default:
			return "";
		}
	}

	/**
	 * Pango markup for the progress stage column ({@link ProgressItem.status_str}).
	 * Gtk: enable markup on the cell/renderer that binds **status-str**.
	 */
	public string to_human()
	{
		switch (this) {
		case NONE:
		case REFINED:
		case REFINE_COMPLETED:
			return "";
		case COARSE:
			return "<b>Planning</b>";
		case REFINEMENT:
			return "<b>Refine</b>";
		case LIST:
			return "<b>Creating</b>";
		case LIST_RETRY:
			return "<b>Retrying</b>";
		case TASK_LIST_ITERATION:
			return "<b>Reviewing</b>";
		case TASK_LIST_ITERATION_RETRY:
			return "<b>Retrying</b>";
		case EXECUTION:
			return "<b>Review output</b>";
		case TOOLS_RUNNING:
			return "<b>Running Tool</b>";
		case EXECUTION_RETRY:
			return "<b>Retry Review output</b>";
		case EXEC_WRITE:
			return "<b>Writing Files</b>";
		case POST_EXEC:
			return "<b>Post review</b>";
		case ERROR:
			return "<span foreground=\"#cc0000\"><b>Retry Failed</b></span>";
		case COMPLETED:
			return "<span foreground=\"#808080\">✓</span>";
		case EXEC_VALIDATE:
			// not shown in UI
		default:
			return "";
		}
	}
}

}
