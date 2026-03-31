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
 * {@link run_step_until_approval} or {@link run_step} to run tasks step-by-step.
 * Each step is refined (all its tasks) immediately before that step runs, so refinement
 * and execution are interleaved per step in order.
 *
 * @see Step
 * @see Details
 * @see ResultParser
 */
public class List : Object
{
	public OLLMcoder.Skill.Runner runner { get; private set; }

	public Gee.ArrayList<Step> steps { get; set; default = new Gee.ArrayList<Step>(); }

	public string goals_summary_md { get; set; default = ""; }

	/**
	 * Slug → task (Details). Populated when the list is built; callers use
	 * .set(), .has_key(), .get() directly. Used for link resolution (task URI slug).
	 */
	public Gee.HashMap<string,Details> slugs { get; private set; default = new Gee.HashMap<string,Details>(); }

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
	 * Write content to session task dir under filename. Content is typically
	 * from the LLM (initial or iteration). Use for task_list.md,
	 * task_list_latest.md, task_list_completed.md.
	 *
	 * @param filename e.g. "task_list.md", "task_list_latest.md", "task_list_completed.md"
	 * @param content full body to write
	 */
	public void write(string filename, string content)
	{
		var path = GLib.Path.build_filename(this.runner.session.task_dir(), filename);
		try {
			GLib.FileUtils.set_contents(path, content);
		} catch (GLib.FileError e) {
			GLib.warning("Failed to write %s: %s", filename, e.message);
			throw e;
		}
	}

	/**
	 * Returns only ## Tasks and task sections. Runner assembles lead content
	 * (original prompt, goals_summary_md) when building current_task_list.
	 * LIST: all tasks with ##### Result summary when exec_done. REFINE_COMPLETED: only completed
	 * tasks (exec_done and exec_runs non-empty), Name + ##### Result summary (raw); no References, no Tool Calls.
	 */
	public string to_markdown(MarkdownPhase phase)
	{
		var ret = "## Tasks\n\n";
		var section = 0;
		foreach (var step in this.steps) {
			section++;
			var step_out = step.to_markdown(phase);
			ret += (step_out == "" ? "" : "### Task section " + section.to_string() + "\n\n" + step_out);
		}
		return ret;
	}

	/**
	 * Call fill_name(index) on each task in order.
	 */
	public void fill_names()
	{
		var index = 0;
		foreach (var step in this.steps) {
			foreach (var t in step.children) {
				t.fill_name(++index);
			}
		}
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
				var skill_name = t.task_data.get("skill").to_markdown().strip();
				issues += t.issue_label() + " references skill \"" + skill_name + 
					"\", which is not in the available skills list.\n";
			}
		}
		if (issues != "") {
			var names = new Gee.ArrayList<string>();
			names.add_all(this.runner.sr_factory.skill_manager.by_name.keys);
			names.sort();
			issues += "\nAvailable skills: " + string.joinv(", ", names.to_array());
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
	 * Run refinement for the first step's tasks only (one after another).
	 * Refinement and execution are interleaved per step: refine first step →
	 * execute first step → (iteration) → refine next step → execute next step.
	 */
	public async void refine(GLib.Cancellable? cancellable = null) throws GLib.Error
	{
		if (this.steps.size == 0) {
			return;
		}
		var step = this.steps.get(0);
		foreach (var t in step.children) {
			if (cancellable != null && cancellable.is_cancelled()) {
				return;
			}
			yield t.refine(cancellable);
		}
	}

	/**
	 * Run the first step only. Stops if that step has a task requiring user approval.
	 * When the step completes (all children exec_done), move it to runner.completed
	 * and remove from this list. Caller (Runner) should call run_task_list_iteration() when true.
	 *
	 * @return true if step was run and completed (caller must run iteration)
	 */
	public async bool run_step_until_approval() throws GLib.Error
	{
		if (this.steps.size == 0) {
			return false;
		}
		var step = this.steps.get(0);
		if (step.has_task_requiring_approval()) {
			return false;
		}
		if (step.children.size == 1) {
			var single = step.children.get(0);
			if (!single.exec_done) {
				yield this.run_child(single);
			}
		} else {
			// Run tasks in the step sequentially (one after another)
			foreach (var t in step.children) {
				if (!t.exec_done) {
					yield this.run_child(t);
				}
			}
		}
		var all_done = true;
		foreach (var t in step.children) {
			if (!t.exec_done) {
				all_done = false;
				break;
			}
		}
		if (!all_done) {
			this.runner.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
				"text.oc-frame-danger.collapsed Step did not complete",
				"Stopping.")));
			return false;
		}
		this.runner.completed.steps.add(step);
		step.list = this.runner.completed;
		foreach (var t in step.children) {
			this.runner.completed.slugs.set(t.slug(), t);
		}
		this.steps.remove_at(0);
		return true;
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
		t.build_exec_runs();
		yield t.run_exec();
		t.write();
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
	 * Run the first step only. When it completes (all children exec_done), move
	 * to runner.completed and remove from this list. Caller (Runner) should call
	 * run_task_list_iteration() when true.
	 *
	 * @return true if step was run and completed (caller must run iteration)
	 */
	public async bool run_step() throws GLib.Error
	{
		if (this.steps.size == 0) {
			return false;
		}
		var step = this.steps.get(0);
		if (step.children.size == 1) {
			var single = step.children.get(0);
			if (!single.exec_done) {
				yield this.run_child(single);
			}
		} else {
			// Run tasks in the step sequentially (one after another)
			foreach (var t in step.children) {
				if (!t.exec_done) {
					yield this.run_child(t);
				}
			}
		}
		var all_done = true;
		foreach (var t in step.children) {
			if (!t.exec_done) {
				all_done = false;
				break;
			}
		}
		if (!all_done) {
			this.runner.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
				"text.oc-frame-danger.collapsed Step did not complete",
				"Stopping.")));
			return false;
		}
		this.runner.completed.steps.add(step);
		step.list = this.runner.completed;
		foreach (var t in step.children) {
			this.runner.completed.slugs.set(t.slug(), t);
		}
		this.steps.remove_at(0);
		return true;
	}
}

}
