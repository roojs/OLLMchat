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
 * Base for task execution runners (lifted from {@link Task.Details.run_exec} /
 * {@link Task.Details.run_post_exec}). Extraction wired; {@link run} dispatch — plan 7.16.1b.
 */
public abstract class Base : OLLMchat.Agent.Base
{
	protected Task.Details task;

	protected Base (Task.Details task)
	{
		base (task.runner.sr_factory, task.session);
		this.task = task;
		this.replace_chat (task.chat ());
	}

	public abstract async void run () throws GLib.Error;

	/**
	 * Parse a tool executor response into the execution run.
	 *
	 * @param parser parsed executor response and issue accumulator
	 * @param ex execution run to fill with summary and document
	 * @return true when the response is valid
	 */
	public virtual async bool extract_result (Task.ResultParser parser, Task.Tool ex)
	{
		if (!parser.document.headings.has_key ("result-summary")) {
			parser.issues += "\n" + "This task's executor output must include a \"Result summary\" section (required). " +
				"It was missing or not found in the response. " +
				"Produce ## Result summary (what was found or produced; whether needs are met or gaps remain).";
			return false;
		}
		ex.summary = parser.document.headings.get ("result-summary");
		ex.document = parser.document;
		var sum_render = new Markdown.Document.Render ();
		sum_render.parse (ex.summary.to_markdown_with_content ());
		var vl_sum = new Task.ValidateLink (this.task.runner, this.task, Task.PhaseEnum.EXECUTION) {
			writes = ex.writes,
			document = sum_render.document
		};
		yield vl_sum.validate_all (sum_render.document.links);
		if (vl_sum.issues != "") {
			parser.issues += vl_sum.issues;
			return false;
		}
		foreach (var link in sum_render.document.links) {
			if (link.path != "" || link.hash == "") {
				continue;
			}
			foreach (var wc in ex.writes) {
				if (!wc.document.headings.has_key (link.hash)) {
					continue;
				}
				link.up_relpath (wc.file_path.strip ());
				break;
			}
		}
		if (sum_render.document.headings.has_key ("result-summary")) {
			ex.summary = sum_render.document.headings.get ("result-summary");
		}
		return true;
	}

	/**
	 * Parse an executor response into a synthetic execution run.
	 *
	 * Used by legacy/test paths that do not already have a queued run.
	 *
	 * @param parser parsed executor response and issue accumulator
	 * @return synthetic execution run, or null when invalid
	 */
	public Task.Tool? extract_tool (Task.ResultParser parser)
	{
		if (!parser.document.headings.has_key ("result-summary")) {
			parser.issues += "\n" + "This task's executor output must include a \"Result summary\" section (required). " +
				"It was missing or not found in the response. " +
				"Produce ## Result summary (what was found or produced; whether needs are met or gaps remain).";
			return null;
		}
		var ex = new Task.Tool ((OLLMchat.Agent.Factory) this.task.runner.sr_factory,
			this.task.runner.session, this.task, "exec");
		ex.summary = parser.document.headings.get ("result-summary");
		ex.document = parser.document;
		return ex;
	}

	protected override async void fill_model ()
	{
		if (!this.task.skill.header.has_key ("model")) {
			yield base.fill_model ();
			return;
		}
		var skill_model = this.task.skill.header.get ("model").strip ();
		if (skill_model != "" && this.connection.models.has_key (skill_model)) {
			this.chat_call.model = skill_model;
			return;
		}
		if (skill_model != "") {
			this.task.add_message (new OLLMchat.Message ("ui", OLLMchat.Message.fenced (
				"text.oc-frame-warning.collapsed Model unavailable",
				"The skill requested the model \"" + skill_model +
					 "\", but it was not available. Using your selected model instead.")));
		}
		yield base.fill_model ();
	}
}

}
