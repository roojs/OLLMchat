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
 * Path D — write skills: lone exec {@link Task.Tool} (write_file handled inside {@link Task.Tool.run}).
 * Copied from {@link Task.Details.run_exec}.
 */
public class WriteExec : Base
{
	public WriteExec (Task.Details task)
	{
		base (task);
	}

	/**
	 * Parse a write executor response into the execution run.
	 *
	 * Called when the skill uses {{{ write_file }}}.
	 */
	public override bool extract_result (Task.ResultParser parser, Task.Tool ex)
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
		ex.writes.clear ();
		foreach (var slug in parser.document.header_list) {
			if (slug == "result-summary") {
				continue;
			}
			var hb = parser.document.headings.get (slug);
			if (hb.parent != parser.document) {
				continue;
			}
			if (!slug.has_prefix ("change-details")) {
				parser.issues += "\nWrite executor: unexpected top-level section (use ## Change details or Path 2 only): \"" + slug + "\".";
				continue;
			}
			var wc = new Task.WriteChange.from_header (hb, this.task.runner.sr_factory.project_manager);
			if (wc.issues != "") {
				parser.issues += "\n"
					+ "Change details — " + hb.text_content ().strip () + ":"
					+ wc.issues.strip ();
				continue;
			}
			ex.writes.add (wc);
			if (wc.output_mode.strip ().down () == "next_section") {
				break;
			}
		}
		if (parser.issues != "") {
			return false;
		}
		var vl_sum = new Task.ValidateLink (this.task.runner, this.task, Task.PhaseEnum.EXECUTION) {
			writes = ex.writes,
			document = sum_render.document
		};
		vl_sum.validate_all (sum_render.document.links);
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
		if (ex.writes.size > 0) {
			return true;
		}
		if (parser.document.to_markdown ().strip ().down ().contains ("**no changes needed**")) {
			return true;
		}
		parser.issues += "\nWrite executor output must include a recognizable Change details section, or Path 2 (full markdown must contain **no changes needed**).";
		return false;
	}

	public override async void run () throws GLib.Error
	{
		this.task.status = Task.PhaseEnum.TOOLS_RUNNING;
		this.task.runner.progress.active_item_changed (this.task);
		var task_name = this.task.task_data.get ("name").to_markdown ().strip ();
		var run_idx = 0;
		foreach (var ex in this.task.tools ()) {
			run_idx++;
			this.task.runner.progress.active_item_changed (ex);
			this.task.add_message (new OLLMchat.Message ("ui",
				(ex.exam_reference != null
					? "Examining " + ex.exam_reference.link_display_text ()
					: "Executing task: " + task_name)
				+ " (" + run_idx.to_string () + " of " + this.task.tools ().size.to_string () + ")"));
			yield ex.run ();
		}
		// Multi-run: post-exec summarizes combined tool runs (write_file runs are included inside each run).
		// Single run: no synthesis pass — copy that run's executor output.
		// Invariant: build_run_queue() leaves tools().size >= 1 before run_exec().
		if (this.task.tools ().size > 1) {
			yield new PostExamMerge (this.task).run ();
			this.task.exec_done = true;
			this.task.status = Task.PhaseEnum.COMPLETED;
			this.task.runner.progress.active_item_changed (null);
			return;
		}
		var last = this.task.tools ().get_at (this.task.tools ().size - 1);
		this.task.post_summary = last.summary;
		this.task.out_doc = last.document;
		this.task.exec_done = true;
		this.task.status = Task.PhaseEnum.COMPLETED;
		this.task.runner.progress.active_item_changed (null);
	}
}

}
