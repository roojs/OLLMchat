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
 * One unit of the task list: either a single task or a concurrent group.
 *
 * Purpose: Step wraps a list of task {@link Details} (children). It is the
 * element over which the top-level {@link List} iterates sequentially;
 * within a step, children run either alone (''size == 1'') or concurrently
 * (''size > 1'').
 *
 * What it does:
 *
 *  * Exposes ''children'' (''Gee.ArrayList'' of {@link Details}).
 *  * {@link has_task_requiring_approval} returns ''true'' if any child
 *    requires user approval before execution continues.
 *  * {@link wait_refined} yields until the single child has finished
 *    refining when ''children.size == 1''; when ''size > 1'', refinement
 *    is waited per task inside {@link List.run_child}, so this method
 *    returns immediately.
 *
 * Task flow: {@link List} holds an ordered list of Step. Execution is
 * sequential at the step level; for each Step, List either runs one
 * run_child (single child) or starts run_child for each child and waits
 * for all via wait_exec_done (concurrent). Step is the boundary between
 * one task or concurrent group and the next step in sequence.
 *
 * @see List
 * @see Details
 */
public class Step : Object
{
	/**
	 * Tasks in this step. Size 1 = single task; size > 1 = concurrent group.
	 */
	public Gee.ArrayList<Details> children { get; set; default = new Gee.ArrayList<Details>(); }

	/**
	 * Whether any child task requires user approval before execution continues.
	 *
	 * @return ''true'' if at least one child has ''requires_user_approval''
	 */
	public bool has_task_requiring_approval()
	{
		foreach (var t in this.children) {
			if (t.requires_user_approval) {
				return true;
			}
		}
		return false;
	}

	/**
	 * When ''children.size == 1'', yields until that task has finished refining.
	 *
	 * For ''size > 1'', {@link List.run_child} waits per task; this method
	 * returns immediately.
	 *
	 * @throws GLib.Error propagated from refinement
	 */
	public async void wait_refined() throws GLib.Error
	{
		if (this.children.size != 1) {
			return;
		}
		yield this.children.get(0).wait_refined();
	}
}

}
