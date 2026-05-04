/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMcoder.Task
{

/**
 * {@link GLib.ListModel} of {@link ProgressItem} rows: {@link Details} from completed work,
 * zero or more {@link ProgressRunner} rows (e.g. one for task creation and one for iteration — each
 * {@link PhaseEnum.COMPLETED} when that slice is done), pending {@link Details} from
 * ''runner.pending''. A {@link Step} uses {@link PhaseEnum.COMPLETED_DONE} once it lives on
 * ''runner.completed''. {@link GLib.ListModel.get_item_type} returns ''typeof(ProgressItem)''.
 *
 * @see OLLMfiles.ProjectList
 */
public class ProgressList : GLib.Object, GLib.ListModel
{
	/**
	 * Owning runner; held weakly to avoid a reference cycle with {@link OLLMcoder.Skill.Runner.progress}.
	 */
	public weak OLLMcoder.Skill.Runner runner { get; private set; }

	private Gee.ArrayList<ProgressItem> rows = new Gee.ArrayList<ProgressItem>();

	public ProgressList(OLLMcoder.Skill.Runner r)
	{
		Object();
		this.runner = r;
	}

	public Type get_item_type()
	{
		return typeof(ProgressItem);
	}

	public uint get_n_items()
	{
		return (uint) this.rows.size;
	}

	public Object? get_item(uint position)
	{
		if (position >= (uint) this.rows.size) {
			return null;
		}
		return this.rows[(int) position];
	}

	/**
	 * Resync only the uncompleted (pending) segment.
	 */
	public void rebuild()
	{
		GLib.debug(
			"REBUILD idx_tail=%d n=%d replay=%s pend_steps=%u comp_steps=%u",
			this.rows.size > 0 ? this.rows.get(this.rows.size - 1).msg_idx : -1,
			this.rows.size,
			this.runner.in_replay.to_string (),
			this.runner.pending.steps.size,
			this.runner.completed.steps.size);
		var n0 = this.rows.size;
		this.clear_pending(false);
		var after_clear = this.rows.size;
		var k = n0 - after_clear;
		this.add_pending(false);
		var n1 = this.rows.size;
		GLib.debug(
			"REBUILD before=%d drop_pending=%d after=%d idx_tail=%d replay=%s pend_steps=%u comp_steps=%u",
			n0,
			k,
			n1,
			this.rows.size > 0 ? this.rows.get(this.rows.size - 1).msg_idx : -1,
			this.runner.in_replay.to_string (),
			this.runner.pending.steps.size,
			this.runner.completed.steps.size);
		if (k == 0 && n1 == after_clear) {
			return;
		}
		this.items_changed((uint) after_clear, (uint) k, (uint) (n1 - after_clear));
	}

	/**
	 * Appends a {@link ProgressRunner} row supplied by {@link OLLMcoder.Skill.Runner}. Caller constructs
	 * {@link r} and sets try fields / phase before calling. Starts with {@link clear_pending}
	 * (no signal); then one {@link GLib.ListModel.items_changed} for tail removals (if any)
	 * plus the new row.
	 */
	public void add(ProgressRunner r)
	{
		var old_size = this.rows.size;
		this.clear_pending(false);
		var after_clear = this.rows.size;
		var removed = old_size - after_clear;
		this.rows.add(r);
		GLib.debug(
			"RUNNER idx_tail=%d creation=%s clear_pending=%d",
			r.msg_idx,
			r.in_creation.to_string(),
			removed);
		this.items_changed((uint) after_clear, (uint) removed, 1u);
	}

	/**
	 * Remove {@link Details} rows whose {@link Step} is still in {@link Runner.pending}
	 * ({@link Step#status} not {@link PhaseEnum.COMPLETED_DONE}). Keeps {@link ProgressRunner} rows and
	 * rows for tasks whose step already moved to {@link Runner.completed}.
	 */
	public void clear_pending(bool call_changed = false)
	{
		GLib.debug(
			"CLRPD idx_before=%d",
			this.rows.size > 0 ? this.rows.get(this.rows.size - 1).msg_idx : -1);
		var old_size = this.rows.size;
		for (var i = this.rows.size - 1; i >= 0; i--) {
			var pi = this.rows.get(i);
			var det = pi as Details;
			if (det == null) {
				continue;
			}
			if (det.step.status == PhaseEnum.COMPLETED_DONE) {
				GLib.debug(
					"CLRPD keep idx=%d slug=%s step_phase=%s detail_phase=%s step_list=%s",
					det.msg_idx,
					det.slug(),
					typeof (PhaseEnum).enum_to_string ((int) det.step.status),
					typeof (PhaseEnum).enum_to_string ((int) det.status),
					det.step.list == null
						? "null"
						: (det.step.list == this.runner.pending
							? "pending"
							: (det.step.list == this.runner.completed
								? "completed"
								: "other")));
				continue;
			}
			GLib.debug(
				"CLRPD drop slug=%s msg_idx=%d step_phase=%s detail_phase=%s step_list=%s pend_steps=%u comp_steps=%u",
				det.slug(),
				det.msg_idx,
				typeof (PhaseEnum).enum_to_string ((int) det.step.status),
				typeof (PhaseEnum).enum_to_string ((int) det.status),
				det.step.list == null
					? "null"
					: (det.step.list == this.runner.pending
						? "pending"
						: (det.step.list == this.runner.completed
							? "completed"
							: "other")),
				this.runner.pending.steps.size,
				this.runner.completed.steps.size);
			this.rows.remove_at(i);
		}
		var removed = old_size - this.rows.size;
		GLib.debug(
			"CLRPD idx_after=%d removed=%d rows_now=%d emit=%s",
			this.rows.size > 0 ? this.rows.get(this.rows.size - 1).msg_idx : -1,
			removed,
			this.rows.size,
			call_changed ? "y" : "n");
		if (removed == 0 || !call_changed) {
			return;
		}
		this.items_changed((uint) this.rows.size, (uint) removed, 0);
	}

	public void add_pending(bool call_changed = false)
	{
		var pos = this.rows.size;
		var added = 0;
		foreach (var step in this.runner.pending.steps) {
			foreach (var d in step.children) {
				this.rows.add(d);
				GLib.debug("ADDPD idx=%d slug=%s", d.msg_idx, d.slug());
				added++;
			}
		}
		GLib.debug(
			"ADDPD idx_tail=%d add=%d emit=%s replay=%s pend_steps=%u comp_steps=%u",
			this.rows.size > 0 ? this.rows.get(this.rows.size - 1).msg_idx : -1,
			added,
			call_changed ? "y" : "n",
			this.runner.in_replay.to_string (),
			this.runner.pending.steps.size,
			this.runner.completed.steps.size);
		if (added == 0 || !call_changed) {
			return;
		}
		this.items_changed((uint) pos, 0, (uint) added);
	}

	/**
	 * Refresh the model after {@link List.move_step_to_completed}. That call sets
	 * {@link Step#status} to {@link PhaseEnum.COMPLETED_DONE} before this runs, so
	 * {@link clear_pending} keeps existing {@link Details} rows for the finished step
	 * (they are not re-appended). {@link add_pending} then attaches the remaining
	 * pending work only.
	 *
	 * @param step the step that was just moved; used for debug only
	 */
	public void add_completed(Step step)
	{
		var n0 = this.rows.size;
		this.clear_pending(false);
		var after_clear = this.rows.size;
		var k = n0 - after_clear;
		this.add_pending(false);
		var n1 = this.rows.size;
		GLib.debug(
			"STEPDN step=%s tasks=%d drop_pending=%d rows_before=%d rows_final=%d last_task_idx=%d",
			step.title,
			step.children.size,
			k,
			n0,
			n1,
			step.children.size > 0 ? step.children.get(step.children.size - 1).msg_idx : -1);
		if (k == 0 && n1 == after_clear) {
			return;
		}
		this.items_changed((uint) after_clear, (uint) k, (uint) (n1 - after_clear));
	}

	public void clear()
	{
		var old_n = this.rows.size;
		if (old_n == 0) {
			return;
		}
		this.rows.clear();
		GLib.debug("CLRALL rows=%d", old_n);
		this.items_changed(0, (uint) old_n, 0);
	}
}

}
