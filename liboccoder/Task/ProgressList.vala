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
 * ''runner.pending''. {@link GLib.ListModel.get_item_type} returns ''typeof(ProgressItem)''.
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
		var n0 = this.rows.size;
		this.clear_pending(false);
		var after_clear = this.rows.size;
		var k = n0 - after_clear;
		this.add_pending(false);
		var n1 = this.rows.size;
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
		this.items_changed((uint) after_clear, (uint) removed, 1u);
	}

	/**
	 * Remove non-{@link PhaseEnum.COMPLETED} rows from the tail; stop at the first
	 * {@link PhaseEnum.COMPLETED} row. Used when replacing the pending segment (e.g. after a
	 * successful slice); not used on fatal-error exits, so {@link PhaseEnum.ERROR} is not special-cased here.
	 */
	public void clear_pending(bool call_changed = false)
	{
		var old_size = this.rows.size;
		for (var i = old_size; i > 0; i--) {
			var pi = this.rows.get(this.rows.size - 1);
			if (pi.status == PhaseEnum.COMPLETED) {
				break;
			}
			this.rows.remove_at(this.rows.size - 1);
		}
		var removed = old_size - this.rows.size;
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
				added++;
			}
		}
		if (added == 0 || !call_changed) {
			return;
		}
		this.items_changed((uint) pos, 0, (uint) added);
	}

	public void add_completed(Step step)
	{
		var n0 = this.rows.size;
		this.clear_pending(false);
		var after_clear = this.rows.size;
		var k = n0 - after_clear;
		foreach (var d in step.children) {
			this.rows.add(d);
		}
		this.add_pending(false);
		var n1 = this.rows.size;
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
		this.items_changed(0, (uint) old_n, 0);
	}
}

}
