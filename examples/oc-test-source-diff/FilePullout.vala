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
 * Phone and tablet file page on {@link SelectorPull}.
 *
 * The page is one list. Phone shows one folder at a time,
 * the tree, then that folder's files. Back from the files
 * returns to the tree. Tablet shows one file list. Search
 * sits on the pull-over. Opening the page leaves search
 * unfocused.
 *
 * == Example ==
 *
 * {{{
 * var files = new FilePullout(manager, "phone", pull);
 * cover.add_overlay(pull);
 * }}}
 */
class FilePullout : FileNav
{
	/**
	 * Shared phone and tablet surface.
	 */
	public SelectorPull pull { get; set; }

	private Gtk.ListBox pull_rows;
	private uint file_wait = 0;

	/**
	 * Build the file page on the shared pull-over.
	 *
	 * @param manager Connected manager. Rows come from the project.
	 * @param form ''phone'' or ''tablet''
	 * @param pull Shared phone and tablet surface
	 */
	public FilePullout(OLLMfiles.ProjectManager manager, string form, SelectorPull pull)
	{
		base(manager, form);
		this.pull = pull;
		this.append(this.button);
		this.folder_tree.selected.connect((folder) => {
			if (this.form != "phone") {
				return;
			}
			this.file_list.visible = true;
			this.pull.current.label = folder.path_basename;
		});
		this.pull_rows = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.SINGLE,
			activate_on_single_click = true,
			hexpand = true,
			vexpand = true,
		};
		this.pull_rows.row_activated.connect((line) => {
			var file = line.get_data<OLLMfiles.File>("file");
			if (file == null) {
				return;
			}
			this.choose(file);
		});
		var pull_page = (Gtk.Widget) this.pull_rows;
		if (this.form == "phone") {
			this.file_list.visible = false;
			var browse = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
			};
			browse.append(this.folder_tree);
			browse.append(this.file_list);
			pull_page = browse;
		}
		var pull_scroll = new Gtk.ScrolledWindow() {
			child = pull_page,
			hexpand = true,
			vexpand = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
		};
		this.pull.pages.add_named(pull_scroll, "file");
		this.pull.back.connect(() => {
			if (this.form != "phone" || this.pull.kind != "file" || !this.file_list.visible) {
				return false;
			}
			this.file_list.visible = false;
			this.folder_tree.show();
			this.pull.current.label = this.project.path_basename;
			return true;
		});
		this.pull.search.search_changed.connect(() => {
			if (this.pull.kind != "file") {
				return;
			}
			if (this.file_wait != 0) {
				GLib.Source.remove(this.file_wait);
			}
			this.file_wait = GLib.Timeout.add(200, () => {
				this.file_wait = 0;
				this.on_search_changed_tree();
				return false;
			});
		});
		this.button.clicked.connect(() => {
			switch (this.form) {
			case "phone":
				this.pull.kind = "file";
				this.pull.heading.label = "Files";
				this.pull.current.label = this.project.path_basename;
				this.pull.pages.visible_child_name = "file";
				this.pull.search.placeholder_text = "Search files";
				this.pull.visible = true;
				this.file_list.visible = false;
				this.folder_tree.show();
				if (!this.project.is_project) {
					return;
				}
				if (this.folder_tree.folders.loaded.contains(this.project.path)) {
					this.pull.search.text = " ";
					this.pull.search.text = "";
					return;
				}
				this.folder_tree.folders.load.begin(this.project, (obj, res) => {
					this.folder_tree.folders.load.end(res);
					this.pull.search.text = " ";
					this.pull.search.text = "";
				});
				return;

			case "tablet":
				this.pull.kind = "file";
				this.pull.heading.label = "Files";
				this.pull.current.label = this.label.label;
				if (this.button.tooltip_text != "") {
					this.pull.current.label = this.button.tooltip_text;
				}
				this.pull.pages.visible_child_name = "file";
				this.pull.search.placeholder_text = "Search files";
				this.pull.visible = true;
				this.pull.search.text = " ";
				this.pull.search.text = "";
				return;

			default:
				return;
			}
		});
		this.notify["project"].connect(() => {
			if (!this.project.is_project) {
				return;
			}
			this.pull_epoch++;
			this.clear(this.pull_rows);
		});
		this.chosen.connect(() => {
			this.pull.visible = false;
		});
	}

	/**
	 * Update the folder tree from the pull-over search box.
	 *
	 * An empty query clears the tree filter. A name query marks
	 * matching folders. On the phone, an empty query shows the
	 * folder tree and hides the file list. A name query shows both.
	 * Tablet fills the file list instead of the tree.
	 */
	private void on_search_changed_tree()
	{
		var query = this.pull.search.text.strip();
		if (!this.project.is_project) {
			return;
		}
		if (query == "" && this.form != "tablet") {
			this.folder_tree.search_reset();
			this.folder_tree.filter.changed(Gtk.FilterChange.DIFFERENT);
			this.file_list.notice = "";
			this.file_list.query = "";
			this.label.label = this.path_text;
			this.folder_tree.show();
			this.file_list.visible = false;
			return;
		}
		if (this.form != "tablet") {
			this.file_list.query = query;
			this.folder_tree.show();
			this.file_list.visible = true;
			this.search_epoch++;
			var epoch = this.search_epoch;
			this.project.fetch_files.begin(50, query, {}, false, false, (obj, res) => {
				this.on_load_results(epoch, res);
			});
			return;
		}
		this.pull_epoch++;
		this.load(query, this.pull_rows, false, this.pull_epoch, "pull");
	}
}
