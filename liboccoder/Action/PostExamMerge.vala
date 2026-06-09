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

namespace OLLMcoder.Action
{

/**
 * Post-execution synthesis when the execution queue has more than one run.
 * Copied from {@link Task.Details.run_post_exec} and {@link Task.Details.post_exec_prompt}.
 */
public class PostExamMerge : Base
{
	public PostExamMerge (Task.Details task)
	{
		base (task);
	}

	/**
	 * Parse post-execution synthesis response into the task.
	 *
	 * Called directly by this action and by replay/live compatibility callers.
	 */
	public void extract (Task.ResultParser parser)
	{
		if (!parser.document.headings.has_key ("result-summary")) {
			parser.issues += "\nPost-exec output must include ## Result summary.";
			return;
		}
		this.task.post_summary = parser.document.headings.get ("result-summary");
		this.task.out_doc = parser.document;
		var sum_render = new Markdown.Document.Render ();
		sum_render.parse (this.task.post_summary.to_markdown_with_content ());
		var vl_sum = new Task.ValidateLink (this.task.runner, this.task, Task.PhaseEnum.POST_EXEC) {
			document = parser.document
		};
		vl_sum.validate_all (sum_render.document.links);
		this.task.issues += vl_sum.issues;
		if (this.task.issues != "") {
			parser.issues += this.task.issues;
		}
	}

	public override async void run () throws GLib.Error
	{
		this.task.status = Task.PhaseEnum.POST_EXEC;
		this.task.runner.progress.active_item_changed (this.task);
		yield this.fill_model ();
		this.chat_call.tools.clear ();
		var response_text = "";
		var last_issues = "";
		for (var try_count = 0; try_count < 5; try_count++) {
			var tpl = this.post_exec_prompt (response_text, last_issues);
			var task_name = this.task.task_data.get ("name").to_markdown ().strip ();
			var model_label = this.task.session.model_usage.model != "" ?
				this.task.session.model_usage.display_name_with_size () : "Unknown model";
			this.task.add_message (new OLLMchat.Message ("ui",
				OLLMchat.Message.fenced (
					"markdown.oc-frame-info.collapsed Summarizing Tool outputs for " +
					task_name + " with " + model_label,
					tpl.filled_user)));
			var messages = new Gee.ArrayList<OLLMchat.Message> ();
			messages.add (new OLLMchat.Message ("system", tpl.filled_system));
			messages.add (new OLLMchat.Message ("user", tpl.filled_user));
			if (!this.task.runner.in_replay) {
				this.task.session.add_message (new OLLMchat.Message ("system", tpl.filled_system));
				this.task.session.add_message (new OLLMchat.Message ("user", tpl.filled_user));
			}
			this.task.add_message (new OLLMchat.Message ("ui-waiting",
				"waiting for " + model_label + " to reply"));
			this.task.add_message (new OLLMchat.Message ("agent-stage", "post_exec"));
			var response = yield this.chat_call.send (messages, null);
			response_text = response != null ? response.message.content : "";
			/* Next stage: progress Idx / scroll target — binding post_exec overwrites the row’s
			 * message with the synthesis response, so tree click scrolled to post_exec instead of
			 * refine. Keep refine as scroll anchor until we decide multi-anchor / phase UX.
			 * if (response != null) {
			 * 	this.assign_message(response.message);
			 * } */
			// GLib.debug(
			// 	"progress detail post_exec slug=%s msg_idx=%d",
			// 	this.slug(),
			// 	this.message != null ? this.message.idx : -1);
			// Ensure any literal {task_link_base} in model output is replaced so links validate
			var task_base = "task://" + this.task.slug () + ".md";
			response_text = response_text.replace ("{task_link_base}", task_base);
			// Before extraction: it copies task.issues into parser.issues after link checks.
			this.task.issues = "";
			var parser = new Task.ResultParser (this.task.runner, response_text);
			this.extract (parser);
			this.task.add_message (new OLLMchat.Message ("agent-issues", parser.issues));
			if (parser.issues == "") {
				this.task.runner.progress.active_item_changed (null);
				return;
			}
			this.task.issues += "\n" + parser.issues;
			last_issues = parser.issues.strip ();
			if (try_count < 4) {
				this.task.add_message (new OLLMchat.Message ("ui", OLLMchat.Message.fenced (
					"text.oc-frame-warning.collapsed Issues with summation of tool calls",
					last_issues)));
			}
		}
		this.task.status = Task.PhaseEnum.ERROR;
		var task_name_fail = this.task.task_data.get ("name").to_markdown ().strip ();
		this.task.add_message (new OLLMchat.Message ("ui", OLLMchat.Message.fenced (
			"text.oc-frame-danger.collapsed Summation of tool calls failed for \"" + task_name_fail + "\"",
			last_issues.strip ())));
		this.task.runner.progress.active_item_changed (null);
		throw new GLib.IOError.INVALID_ARGUMENT (
			"task_post_exec: " + last_issues);
	}

	/**
	 * Build post-execution prompt from task_post_exec.md.
	 * previous_response and retry_issues are used for retries (header_raw when non-empty).
	 * Copied from {@link Task.Details.post_exec_prompt}.
	 */
	private OLLMcoder.Skill.PromptTemplate post_exec_prompt (
			string previous_response, string retry_issues) throws GLib.Error
	{
		var tpl = OLLMcoder.Skill.PromptTemplate.template ("task_post_exec.md");
		tpl.system_fill (0);
		string[] run_blocks = {};
		foreach (var ex in this.task.tools ()) {
			run_blocks += ex.document.to_markdown ();
		}
		tpl.fill (6,
			"task_definition", this.task.to_markdown (Task.PhaseEnum.POST_EXEC),
			"skill_name", this.task.skill.header.get ("name"),
			"skill_execute_body", this.task.skill.execute,
			"tool_runs_combined", string.joinv ("\n\n---\n\n", run_blocks),
			"post_exec_previous_output",
			previous_response.strip () == "" ? "" :
				tpl.header_raw ("Your previous output", previous_response),
			"post_exec_retry_issues",
			retry_issues.strip () == "" ? "" :
				tpl.header_raw ("Issues with your previous output", retry_issues));
		return tpl;
	}
}

}
