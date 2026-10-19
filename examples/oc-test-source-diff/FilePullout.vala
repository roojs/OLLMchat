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
	 * Phone shows one folder at a time: its child folders, then its
	 * files. The left arrow and the back key go up one directory.
	 * An X closes the page. Tree and Recent sit under the title.
	 * Search stays at the bottom of the pull-over. Tablet keeps one
	 * file list.
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
		private GLib.ListStore files; // suspect
		private Gtk.ListBox folders;
		private Gtk.Box browse;
		private Gtk.Box tree_box;
		private Gtk.ScrolledWindow recent_scroll;
		private Gtk.Stack filters;
		private Gtk.Box file_bar;
		private GLib.ListModel folder_model;
		private OLLMfiles.Folder level;
		private string chosen_path = "";
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
			this.level = this.project;
			this.folder_model = this.folder_tree.folders;
			this.append(this.button);
			this.files = new GLib.ListStore(typeof(OLLMfiles.File));
			this.list = new Gtk.ListBox() {
				hexpand = true,
				vexpand = true,
				activate_on_single_click = true,
			};
			this.list.bind_model(this.files, (item) => {
				var file = (OLLMfiles.File) item;
				if (this.form != Form.PHONE) {
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
				}
				return this.list_box_factory(file, "text-x-generic-symbolic");
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
			this.folders = new Gtk.ListBox() {
				hexpand = true,
				activate_on_single_click = true,
				selection_mode = Gtk.SelectionMode.NONE,
			};
			this.folders.row_activated.connect((line) => {
				var folder = (OLLMfiles.Folder) this.folder_model.get_item((uint) line.get_index());
				if (folder == null) {
					return;
				}
				this.refresh_folder(folder);
			});
			var file_sorted = new Gtk.SortListModel(this.file_list.files, new Gtk.StringSorter(
				new Gtk.PropertyExpression(typeof(OLLMfiles.File), null, "path_basename")
			) {
				ignore_case = true,
			});
			var file_box = new Gtk.ListBox() {
				hexpand = true,
				activate_on_single_click = true,
				selection_mode = Gtk.SelectionMode.NONE,
			};
			file_box.bind_model(file_sorted, (item) => {
				return this.list_box_factory((OLLMfiles.FileBase) item, "text-x-generic-symbolic");
			});
			file_box.set_placeholder(new Gtk.Label("No files") {
				xalign = 0,
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_top = 8,
				margin_bottom = 8,
				css_classes = { "dim-label" },
			});
			file_box.row_activated.connect((line) => {
				var file = (OLLMfiles.File) file_sorted.get_item((uint) line.get_index());
				if (file == null) {
					return;
				}
				this.choose(file);
			});
			this.browse = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
			};
			this.browse.append(this.folders);
			this.browse.append(file_box);
			this.tree_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
			};
			this.tree_box.append(this.browse);
			this.recent_scroll = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = true,
				hscrollbar_policy = Gtk.PolicyType.NEVER,
			};
			this.filters = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
			};
			var tree_scroll = new Gtk.ScrolledWindow() {
				child = this.tree_box,
				hexpand = true,
				vexpand = true,
				hscrollbar_policy = Gtk.PolicyType.NEVER,
			};
			this.filters.add_titled(tree_scroll, "tree", "Tree");
			this.filters.add_titled(this.recent_scroll, "recent", "Recent");
			var pull_page = (Gtk.Widget) new Gtk.ScrolledWindow() {
				child = this.list,
				hexpand = true,
				vexpand = true,
				hscrollbar_policy = Gtk.PolicyType.NEVER,
			};
			this.file_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				visible = false,
			};
			this.file_bar.append(this.folder_tree.ghost);
			this.file_bar.append(new Gtk.StackSwitcher() {
				stack = this.filters,
				hexpand = true,
			});
			if (this.form == Form.PHONE) {
				this.list.selection_mode = Gtk.SelectionMode.NONE;
				this.recent_scroll.child = this.list;
				this.selector.prepend(this.file_bar);
				var page = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
					hexpand = true,
					vexpand = true,
				};
				page.append(this.filters);
				pull_page = page;
			}
			this.selector.pages.add_named(pull_page, "file");
			this.selector.pages.notify["visible-child-name"].connect(() => {
				if (this.form != Form.PHONE) {
					return;
				}
				this.file_bar.visible = this.selector.pages.visible_child_name == "file";
			});
			this.selector.back.connect(() => {
				if (this.form != Form.PHONE || this.selector.kind != "file") {
					return false;
				}
				var up = this.level.parent;
				if (this.level.is_project || up == null) {
					return true;
				}
				this.refresh_folder(up);
				return true;
			});
			var keys = new Gtk.EventControllerKey();
			keys.key_pressed.connect((keyval, keycode, state) => {
				if (this.form != Form.PHONE || !this.selector.visible || this.selector.kind != "file") {
					return false;
				}
				if (keyval != Gdk.Key.Back && keyval != Gdk.Key.Escape) {
					return false;
				}
				var up = this.level.parent;
				if (this.level.is_project || up == null) {
					return true;
				}
				this.refresh_folder(up);
				return true;
			});
			this.selector.add_controller(keys);
			this.filters.notify["visible-child-name"].connect(() => {
				if (this.form != Form.PHONE) {
					return;
				}
				var on_tree = this.filters.visible_child_name == "tree";
				this.folder_tree.ghost.opacity = on_tree ? 1 : 0;
				this.folder_tree.ghost.sensitive = on_tree;
				if (this.selector.kind != "file") {
					return;
				}
				this.on_search_changed_tree();
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
				this.show_files();
			});
			this.notify["project"].connect(() => {
				if (!this.project.is_project) {
					return;
				}
				this.pullout_epoch++;
				this.level = this.project;
				if (!this.chosen_path.has_prefix(this.project.path + "/")) {
					this.chosen_path = "";
				}
				this.files.remove_all();
				this.file_list.files.clear();
				this.show_files();
			});
			this.chosen.connect((file) => {
				this.chosen_path = file.path;
				this.selector.visible = false;
			});
		}

		/**
		 * Open the file page for this layout. Phone shows the
		 * folder that holds the chosen file, or the project root.
		 * Search is left unfocused.
		 */
		private void show_files()
		{
			this.selector.kind = "file";
			this.selector.pages.visible_child_name = "file";
			this.selector.search.placeholder_text = "Search files";
			this.selector.visible = true;
			if (this.form == Form.PHONE) {
				this.selector.close.visible = true;
				this.file_bar.visible = true;
				this.filters.visible_child_name = "tree";
				if (this.selector.search.text != "") {
					this.selector.search.text = "";
				}
				if (!this.project.is_project) {
					return;
				}
				if (this.folder_tree.folders.loaded.contains(this.project.path)) {
					this.refresh_folder(this.file_folder());
					return;
				}
				this.folder_tree.folders.load.begin(this.project, (obj, res) => {
					this.folder_tree.folders.load.end(res);
					this.refresh_folder(this.file_folder());
				});
				return;
			}
			this.selector.heading.label = "Files";
			this.selector.close.visible = false;
			this.selector.previous.visible = true;
			this.selector.current.visible = true;
			this.selector.current.label = this.label.label;
			if (this.button.tooltip_text != "") {
				this.selector.current.label = this.button.tooltip_text;
			}
			this.selector.search.text = " ";
			this.selector.search.text = "";
		}

		/**
		 * Refresh the phone page to one folder. Child folders come
		 * from the folder tree kept in memory. Empty and ignored
		 * folders stay hidden while the ghost button is on, which
		 * is how it starts. Files come from {@link FileListStore}.
		 * The arrow is hidden at the project root.
		 *
		 * @param folder Folder now shown
		 */
		private void refresh_folder(OLLMfiles.Folder folder)
		{
			this.level = folder;
			this.pullout_epoch++;
			var place = folder.path;
			if (this.project.path != "" && place.has_prefix(this.project.path)) {
				place = place.substring(this.project.path.length);
			}
			if (place.has_prefix("/")) {
				place = place.substring(1);
			}
			this.selector.heading.label = this.project.path_basename;
			this.selector.current.label = place;
			this.selector.current.visible = place != "";
			this.selector.previous.visible = place != "";
			this.browse.visible = true;
			if (this.recent_scroll.child != this.list) {
				this.list.unparent();
				this.recent_scroll.child = this.list;
			}
			this.folders.visible = false;
			this.folders.bind_model(null, null);
			if (!this.folder_tree.folders.segments.has_key(folder.path)) {
				this.file_list.files.load.begin(folder);
				return;
			}
			var shown = new Gtk.FilterListModel(
				this.folder_tree.folders.segments.get(folder.path),
				this.folder_tree.filter
			);
			this.folder_model = shown;
			this.folders.bind_model(shown, (item) => {
				return this.list_box_factory((OLLMfiles.FileBase) item, "folder-symbolic");
			});
			this.folders.visible = shown.get_n_items() > 0;
			shown.items_changed.connect(() => {
				this.folders.visible = shown.get_n_items() > 0;
			});
			this.file_list.files.load.begin(folder);
		}

		/**
		 * Folder holding the chosen file. The project is used when
		 * no file is chosen, or when that folder is not in the tree.
		 *
		 * @return Folder the phone page should show
		 */
		private OLLMfiles.Folder file_folder()
		{
			if (this.chosen_path == "" || !this.chosen_path.has_prefix(this.project.path + "/")) {
				return this.project;
			}
			var slash = this.chosen_path.last_index_of_char('/');
			if (slash < 1) {
				return this.project;
			}
			var dir = this.chosen_path.substring(0, slash);
			if (!this.folder_tree.folders.path_map.has_key(dir)) {
				return this.project;
			}
			return this.folder_tree.folders.path_map.get(dir);
		}

		/**
		 * List box factory for a phone folder or file. The caller
		 * picks the icon, so the folder list and the file list can
		 * diverge later. The second line is the path relative to the
		 * project, including the item name. That line is absent at
		 * the project root. A long path drops the item name first,
		 * then keeps the first folder.
		 *
		 * @param item Folder or file for this list box
		 * @param icon_name Icon chosen by that list
		 * @return The list box child
		 */
		private Gtk.Widget list_box_factory(OLLMfiles.FileBase item, string icon_name)
		{
			var line = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 8,
			};
			line.append(new Gtk.Image.from_icon_name(icon_name) {
				valign = Gtk.Align.CENTER,
			});
			var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				hexpand = true,
			};
			column.append(new Gtk.Label(item.path_basename) {
				xalign = 0,
				halign = Gtk.Align.START,
				hexpand = true,
				ellipsize = Pango.EllipsizeMode.END,
				css_classes = { "body", "list-chat-title" },
			});
			var rel = item.path;
			if (this.project.path != "" && rel.has_prefix(this.project.path)) {
				rel = rel.substring(this.project.path.length);
			}
			if (rel.has_prefix("/")) {
				rel = rel.substring(1);
			}
			var below = rel.contains("/");
			if (below && rel.length > 36) {
				var cut = rel.last_index_of_char('/');
				if (cut > 0) {
					rel = rel.substring(0, cut);
				}
			}
			if (below && rel.contains("/") && rel.length > 36) {
				var first = rel.index_of_char('/');
				if (first > 0) {
					rel = rel.substring(0, first) + "/…";
				}
			}
			if (below) {
				column.append(new Gtk.Label(rel) {
					xalign = 0,
					halign = Gtk.Align.START,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.END,
					css_classes = { "caption", "dim-label" },
				});
			}
			line.append(column);
			return line;
		}

		/**
		 * Fill the visible phone or tablet list from the search box.
		 *
		 * An empty phone query on Tree shows the open folder. A
		 * query on Tree fills the pullout list. Recent fills that
		 * same list with viewed files. Tablet always fills it.
		 */
		private void on_search_changed_tree()
		{
			if (!this.project.is_project) {
				return;
			}
			if (this.form != Form.PHONE) {
				this.pullout_epoch++;
				this.load(this.selector.search.text.strip(), this.files, this.list,
					this.pullout_epoch, Slot.PULLOUT);
				return;
			}
			if (this.filters.visible_child_name == "recent") {
				if (this.recent_scroll.child != this.list) {
					this.list.unparent();
					this.recent_scroll.child = this.list;
				}
				this.history_epoch++;
				this.load(this.selector.search.text.strip(), this.files, this.list,
					this.history_epoch, Slot.HISTORY);
				return;
			}
			if (this.selector.search.text.strip() == "") {
				this.refresh_folder(this.level);
				return;
			}
			this.browse.visible = false;
			if (this.list.get_parent() != this.tree_box) {
				this.list.unparent();
				this.tree_box.append(this.list);
			}
			this.pullout_epoch++;
			this.load(this.selector.search.text.strip(), this.files, this.list,
				this.pullout_epoch, Slot.PULLOUT);
		}
	}
}
