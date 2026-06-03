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
 * Path C — shared references only: lone exec {@link Task.Tool}, copy executor output.
 * Copied from {@link Task.Details.run_exec}.
 */
public class RefOnly : Base
{
	public RefOnly (Task.Details task)
	{
		base (task);
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
