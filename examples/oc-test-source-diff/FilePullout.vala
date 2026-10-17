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

namespace OLLMapp
{
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
	 * var files = new FilePullout(manager, Form.PHONE, selector);
	 * cover.add_overlay(selector);
	 * }}}
	 */
	class FilePullout : FileNav
	{
		/**
		 * Shared phone and tablet surface.
		 */
		public SelectorPull selector { get; set; }

		private Gtk.ListBox list;
		private GLib.ListStore files;
		private uint file_wait = 0;

		/**
		 * Build the file page on the shared pull-over.
		 *
		 * @param manager Connected manager. Rows come from the project.
		 * @param form Phone or tablet
		 * @param selector Shared phone and tablet surface
		 */
		public FilePullout(OLLMfiles.ProjectManager manager, Form form, SelectorPull selector)
		{
			base(manager, form);
			this.selector = selector;
			this.append(this.button);
			this.folder_tree.selected.connect((folder) => {
				if (this.form != Form.PHONE) {
					return;
				}
				this.file_list.visible = true;
				this.selector.current.label = folder.path_basename;
			});
			this.files = new GLib.ListStore(typeof(OLLMfiles.File));
			this.list = new Gtk.ListBox() {
				hexpand = true,
				vexpand = true,
				activate_on_single_click = true,
			};
			this.list.bind_model(this.files, (item) => {
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
			this.list.set_placeholder(new Gtk.Label("No files") {
				xalign = 0,
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_top = 8,
				margin_bottom = 8,
				css_classes = { "dim-label" },
			});
			this.list.row_activated.connect((line) => {
				var file = (OLLMfiles.File) this.files.get_item((uint) line.get_index());
				if (file == null) {
					return;
				}
				this.choose(file);
			});
			var pull_page = (Gtk.Widget) this.list;
			if (this.form == Form.PHONE) {
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
			this.selector.pages.add_named(pull_scroll, "file");
			this.selector.back.connect(() => {
				if (this.form != Form.PHONE || this.selector.kind != "file" || !this.file_list.visible) {
					return false;
				}
				this.file_list.visible = false;
				this.folder_tree.show();
				this.selector.current.label = this.project.path_basename;
				return true;
			});
			this.selector.search.search_changed.connect(() => {
				if (this.selector.kind != "file") {
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
					case Form.PHONE:
						this.selector.kind = "file";
						this.selector.heading.label = "Files";
						this.selector.current.label = this.project.path_basename;
						this.selector.pages.visible_child_name = "file";
						this.selector.search.placeholder_text = "Search files";
						this.selector.visible = true;
						this.file_list.visible = false;
						this.folder_tree.show();
						if (!this.project.is_project) {
							return;
						}
						if (this.folder_tree.folders.loaded.contains(this.project.path)) {
							this.selector.search.text = " ";
							this.selector.search.text = "";
							return;
						}
						this.folder_tree.folders.load.begin(this.project, (obj, res) => {
							this.folder_tree.folders.load.end(res);
							this.selector.search.text = " ";
							this.selector.search.text = "";
						});
						return;

					case Form.TABLET:
						this.selector.kind = "file";
						this.selector.heading.label = "Files";
						this.selector.current.label = this.label.label;
						if (this.button.tooltip_text != "") {
							this.selector.current.label = this.button.tooltip_text;
						}
						this.selector.pages.visible_child_name = "file";
						this.selector.search.placeholder_text = "Search files";
						this.selector.visible = true;
						this.selector.search.text = " ";
						this.selector.search.text = "";
						return;

					default:
						return;
				}
			});
			this.notify["project"].connect(() => {
				if (!this.project.is_project) {
					return;
				}
				this.pullout_epoch++;
				this.files.remove_all();
			});
			this.chosen.connect(() => {
				this.selector.visible = false;
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
			var query = this.selector.search.text.strip();
			if (!this.project.is_project) {
				return;
			}
			if (query == "" && this.form != Form.TABLET) {
				this.folder_tree.search_reset();
				this.folder_tree.filter.changed(Gtk.FilterChange.DIFFERENT);
				this.file_list.notice = "";
				this.file_list.query = "";
				this.label.label = this.path_text;
				this.folder_tree.show();
				this.file_list.visible = false;
				return;
			}
			if (this.form != Form.TABLET) {
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
			this.pullout_epoch++;
			this.load(query, this.files, this.list,
				this.pullout_epoch, Slot.PULLOUT);
		}
	}
}
