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
 * List of {@link Tool} rows for one {@link Details}. Backing store for {@link ProgressItem.children}
 * on {@link Details} once **7.14.1.3** wires the execution queue; implements {@link GLib.ListModel},
 * {@link Gee.Iterable}, and {@link Gee.Traversable} so call sites can ''foreach'' over tools.
 *
 * @see Details.build_exec_runs
 */
public class ToolList : GLib.Object, GLib.ListModel, Gee.Traversable<Tool>, Gee.Iterable<Tool>
{
	private Gee.ArrayList<Tool> items = new Gee.ArrayList<Tool>();

	public ToolList()
	{
		Object();
	}

	public Type get_item_type()
	{
		return typeof(ProgressItem);
	}

	public uint get_n_items()
	{
		return (uint) this.items.size;
	}

	public Object? get_item(uint position)
	{
		if (position >= this.items.size) {
			return null;
		}
		return this.items[(int) position];
	}

	/**
	 * Append — matches ''Gee.ArrayList.add'' / {@link ResultParser} call sites.
	 */
	public void append(Tool t)
	{
		this.items.add(t);
		this.items_changed(this.items.size - 1, 0, 1);
	}

	/**
	 * Alias for {@link append}.
	 */
	public void add(Tool t)
	{
		this.append(t);
	}

	/**
	 * Index access — matches ''Gee.ArrayList.get''.
	 */
	public Tool get_at(int index)
	{
		return this.items[index];
	}

	/**
	 * Item count — matches ''.size'' on Gee list.
	 */
	public int size {
		get { return this.items.size; }
	}

	public bool foreach(Gee.ForallFunc<Tool> f)
	{
		return this.items.foreach(f);
	}

	public Gee.Iterator<Tool> iterator()
	{
		return this.items.iterator();
	}

	/**
	 * Remove all items. If already empty, return without calling ''items.clear()''.
	 */
	public void clear()
	{
		var old_n = (uint) this.items.size;
		if (old_n == 0) {
			return;
		}
		this.items.clear();
		this.items_changed(0, old_n, 0);
	}
}

}
