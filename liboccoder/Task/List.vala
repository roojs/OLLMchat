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
 * Ordered list of task steps produced by planning; runs refinement and
 * execution.
 *
 * Holds {@link steps} (each {@link Step} has {@link Details} children).
 * Created by {@link ResultParser.parse_task_list}; the Runner then calls
 * {@link refine}, then {@link run_until_user_approval} or {@link run_all_tasks}
 * to run tasks step-by-step. Refinement is started for all tasks up front;
 * execution waits for each task's refinement only when that task runs.
 *
 * @see Step
 * @see Details
 * @see ResultParser
 */
public class List : Object
{
	private OLLMcoder.Skill.Runner runner;

	public Gee.ArrayList<Step> steps { get; set; default = new Gee.ArrayList<Step>(); }

	/**
	 * Number of run_child (execution) callbacks still running for the current
	 * step. Caller sets = children.size before .begin(); each callback does
	 * num_exec_running-- and resumes ''resume_when_exec_done'' when it runs.
	 */
	private int num_exec_running = 0;

	/**
	 * Continuation for ''wait_exec_done''; set before yield, invoked by each
	 * run_child completion callback to wake the waiter.
	 */
	private GLib.SourceFunc? resume_when_exec_done = null;

	public List(OLLMcoder.Skill.Runner runner)
	{
		this.runner = runner;
	}

	/**
	 * True if any task has no execution result (output) yet; returns as soon
	 * as one is found.
	 */
	public bool has_pending_exec()
	{
		foreach (var step in this.steps) {
			foreach (var t in step.children) {
				if (!t.exec_done) {
					return true;
				}
			}
		}
		return false;
	}

	/**
	 * For each task (steps → children), call task.skill_manager.validate(task).
	 * When false, add issue line: skill must be one of the available skills.
	 * Returns combined issues string; "" when all tasks' skills exist.
	 */
	public string validate_skills()
	{
		var issues = "";
		foreach (var step in this.steps) {
			foreach (var t in step.children) {
				if (t.skill_manager.validate(t)) {
					continue;
				}
				var skill_name = t.task_data.get("Skill").to_markdown().strip();
				issues += "Task references skill \"" + skill_name + "\", which is not in the available skills list.\n";
			}
		}
		return issues;
	}

	/**
	 * Yields until execution of the current step's children is done
	 * (num_exec_running is 0). Caller sets num_exec_running before starting
	 * .begin() calls. Each run_child completion callback resumes this; we
	 * re-check and yield again until num_exec_running is 0.
	 */
	private async void wait_exec_done() throws GLib.Error
	{
		while (this.num_exec_running != 0) {
			this.resume_when_exec_done = wait_exec_done.callback;
			yield;
		}
		this.resume_when_exec_done = null;
	}

	/**
	 * Start refinement for all tasks (non-blocking). Launch each task's
	 * refine via .begin. Does not wait for any refinement to complete;
	 * run_child waits for that task's refinement when it runs.
	 */
	public async void refine() throws GLib.Error
	{
		foreach (var step in this.steps) {
			foreach (var t in step.children) {
				t.refine.begin();
			}
		}
	}

	/**
	 * For each Step: if size == 1 yield run_child(…); else num_exec_running =
	 * children.size, run_child.begin per child, yield wait_exec_done().
	 * Stops at first step that has a task requiring user approval.
	 */
	public async void run_until_user_approval() throws GLib.Error
	{
		foreach (var step in this.steps) {
			if (step.has_task_requiring_approval()) {
				break;
			}
			if (step.children.size == 1) {
				var single = step.children.get(0);
				if (!single.exec_done) {
					yield this.run_child(single);
				}
				continue;
			}
			this.num_exec_running = 0;
			foreach (var t in step.children) {
				if (!t.exec_done) {
					this.num_exec_running++;
				}
			}
			foreach (var t in step.children) {
				this.start_child(t);
			}
			yield this.wait_exec_done();
		}
	}

	/**
	 * Starts run_child for one task in the background; on completion
	 * decrements num_exec_running and resumes ''wait_exec_done'' if set.
	 * Skips tasks that are already done (''t.exec_done''). Caller must set
	 * num_exec_running to the number of children being started first.
	 */
	private void start_child(Details t)
	{
		if (t.exec_done) {
			return;
		}
		this.run_child.begin(t, (o, res) => {
			this.run_child.end(res);
			this.num_exec_running--;
			if (this.resume_when_exec_done == null) {
				return;
			}
			var cb = this.resume_when_exec_done;
			this.resume_when_exec_done = null;
			GLib.Idle.add(() => {
				cb();
				return false;
			});
		});
	}

	private async void run_child(Details t) throws GLib.Error
	{
		yield t.wait_refined();
		yield t.run_tools();
		yield t.post_evaluate();
	}

	public bool has_tasks_requiring_approval()
	{
		foreach (var step in this.steps) {
			if (step.has_task_requiring_approval()) {
				return true;
			}
		}
		return false;
	}

	/**
	 * For each Step: if size == 1 yield run_child(…); else num_exec_running =
	 * children.size, run_child.begin per child, yield wait_exec_done().
	 */
	public async void run_all_tasks() throws GLib.Error
	{
		foreach (var step in this.steps) {
			if (step.children.size == 1) {
				var single = step.children.get(0);
				if (!single.exec_done) {
					yield this.run_child(single);
				}
				continue;
			}
			this.num_exec_running = 0;
			foreach (var t in step.children) {
				if (!t.exec_done) {
					this.num_exec_running++;
				}
			}
			foreach (var t in step.children) {
				this.start_child(t);
			}
			yield this.wait_exec_done();
		}
	}
}

}
