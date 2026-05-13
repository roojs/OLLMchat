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

namespace MarkdownGtk
{
	/**
	 * Vertical Gtk.Box used as the live markdown target for {@link Render}.
	 *
	 * Each logical row is one content widget listed in {@link by_id}. The owning
	 * {@link Render} passes this box at construction; each row uses {@link appender}
	 * on this class so indices stay aligned without relying on Gtk.Box.append dispatch.
	 */
	public class RenderBox : Gtk.Box
	{
		/** Append order for scroll / id queries; updated only from {@link appender}. */
		public Gee.ArrayList<Gtk.Widget> by_id { get; private set; default = new Gee.ArrayList<Gtk.Widget>(); }

		/** Start index of the current span; set by {@link mark}. */
		public int first_id { get; private set; default = 0; }

		/** Last assigned id, or 0 when {@link by_id} is empty. */
		public int last_id {
			get {
				return this.by_id.size > 0 ? this.by_id.size - 1 : 0;
			}
		}

		public RenderBox()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
		}

		/**
		 * Append one content row: child, registered in {@link by_id}.
		 *
		 * @param child widget to append as the indexed row body
		 */
		public void appender(Gtk.Widget child)
		{
			/* base.append(new Gtk.Label(this.by_id.size.to_string())); */
			base.append(child);
			this.by_id.add(child);
		}

		/**
		 * Set {@link first_id} to the next index that {@link appender} will assign.
		 */
		public void mark()
		{
			this.first_id = this.by_id.size;
		}
	}
}
