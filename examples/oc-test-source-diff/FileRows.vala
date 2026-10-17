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
 * Bound file list. One row, one model.
 *
 * A fetch replaces the items in {@link files}. The list box
 * builds and drops the rows. Directories are left out. An
 * empty page shows the placeholder set by the view.
 * {@link HistoryRows} keeps viewed files. {@link PullRows}
 * keeps the whole page.
 *
 * == Example ==
 *
 * {{{
 * var list = new HistoryRows();
 * list.replace(response);
 * }}}
 */
class FileRows : Gtk.ListBox
{
	/**
	 * Files currently shown. A {@link replace} swaps these.
	 */
	public GLib.ListStore files { get; private set; default = new GLib.ListStore(typeof(OLLMfiles.File)); }

	/**
	 * Viewed files only. {@link HistoryRows} sets this.
	 */
	public bool recent { get; set; default = false; }

	/**
	 * Bind the row to {@link files}.
	 */
	public FileRows()
	{
		Object(
			hexpand: true,
			activate_on_single_click: true
		);
		this.bind_model(this.files, (item) => {
			var file = (OLLMfiles.File) item;
			var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 8,
			};
			column.append(new Gtk.Label(file.path_basename) {
				xalign = 0,
				halign = Gtk.Align.START,
				hexpand = true,
				ellipsize = Pango.EllipsizeMode.END,
				css_classes = { "body", "list-chat-title" },
			});
			column.append(new Gtk.Label(file.path) {
				xalign = 0,
				halign = Gtk.Align.START,
				hexpand = true,
				ellipsize = Pango.EllipsizeMode.START,
				css_classes = { "caption", "dim-label" },
			});
			return column;
		});
	}

	/**
	 * Drop every file. The list box drops the rows.
	 */
	public void clear()
	{
		this.files.remove_all();
	}

	/**
	 * Replace {@link files} with one fetch page.
	 *
	 * Directories are left out. When {@link recent} is set,
	 * a file with no last view is left out. The first row is
	 * marked for the keyboard. An empty page leaves the
	 * placeholder.
	 *
	 * @param response Daemon page from ''Folder.fetch_files''
	 */
	public void replace(OLLMrpc.Response response)
	{
		this.files.remove_all();
		if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
			var rows = (Gee.ArrayList<GLib.Object>) response.retval.get_object();
			foreach (var row in rows) {
				var file = (OLLMfiles.FileBase) row;
				if (file.base_type == "d" || file.base_type == "da") {
					continue;
				}
				if (this.recent && file.last_viewed < 1) {
					continue;
				}
				if (row is OLLMfiles.File) {
					this.files.append((OLLMfiles.File) row);
					continue;
				}
				var made = new OLLMfiles.File(file.manager);
				made.copy_from(file, { "manager" });
				this.files.append(made);
			}
		}
		if (this.files.get_n_items() < 1) {
			return;
		}
		var first = this.get_row_at_index(0);
		if (first == null || !first.activatable) {
			return;
		}
		first.add_css_class("selector-mark");
	}
}
