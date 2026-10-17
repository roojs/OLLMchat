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
 * Recent view of {@link FileRows}.
 *
 * Keeps files that have been viewed. The placeholder is
 * ''No recent files''. Selection is off so the keyboard mark
 * moves without a Gtk selection.
 *
 * == Example ==
 *
 * {{{
 * var list = new HistoryRows();
 * list.replace(response);
 * }}}
 */
class HistoryRows : FileRows
{
	/**
	 * Recent files, with no Gtk selection.
	 */
	public HistoryRows()
	{
		base();
		this.recent = true;
		this.selection_mode = Gtk.SelectionMode.NONE;
		this.can_focus = false;
		this.set_placeholder(new Gtk.Label("No recent files") {
			xalign = 0,
			halign = Gtk.Align.START,
			margin_start = 12,
			margin_top = 8,
			margin_bottom = 8,
			css_classes = { "dim-label" },
		});
	}
}
