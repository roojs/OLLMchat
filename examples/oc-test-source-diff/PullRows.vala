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

/**
 * Pull-over view of {@link FileRows}.
 *
 * Keeps every file in the page. The placeholder is
 * ''No files''.
 *
 * == Example ==
 *
 * {{{
 * var list = new PullRows();
 * list.replace(response);
 * }}}
 */
class PullRows : FileRows
{
	/**
	 * Search page for the phone and tablet pull-over.
	 */
	public PullRows()
	{
		base();
		this.vexpand = true;
		this.set_placeholder(new Gtk.Label("No files") {
			xalign = 0,
			halign = Gtk.Align.START,
			margin_start = 12,
			margin_top = 8,
			margin_bottom = 8,
			css_classes = { "dim-label" },
		});
	}
}
