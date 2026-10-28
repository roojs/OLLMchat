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

namespace OLLMcoder.File
{
	/**
	 * Phone file page on {@link SelectorPull}.
	 *
	 * One folder at a time: its child folders, then its files. The
	 * top row shows the project and open folders as buttons with a
	 * slash between them, shortened to ''...'' when needed, and an X
	 * that closes the page. The full relative path under that row is
	 * shown only when a folder button is shortened to ''...''. The
	 * back key goes up one directory. Tree and Recent sit above the
	 * path row. Search stays at the bottom of the pull-over. Tablet
	 * files are {@link Overlay}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var files = new Pullout(manager, Form.PHONE, selector);
	 * cover.add_overlay(selector);
	 * }}}
	 */
	public class Pullout : Nav
	{
		/**
		 * Phone pull-over. Tablet files are not on this page.
		 */
		public SelectorPull selector { get; set; }

		private Gtk.ListBox list;
		private GLib.ListStore files; // suspect
		private Folder.Browse browse;
		private Gtk.Box tree_box;
		private Gtk.ScrolledWindow recent_scroll;
		private Gtk.Stack filters;
		private Gtk.Box file_bar;
		private string chosen_path = "";
		private uint file_wait = 0;
		private Gtk.Label list_note;

		/**
		 * Build the file page on the shared pull-over.
		 *
		 * @param manager Connected manager. Rows come from the project.
		 * @param form Phone
		 * @param selector Phone pull-over
		 */
		public Pullout(OLLMfiles.ProjectManager manager, Form form, SelectorPull selector)
		{
			base(manager, form);
			this.selector = selector;
			this.level = this.project;
			this.browse = new Folder.Browse(this.folder_tree, this.file_list, this.project, true);
			this.browse.selected.connect((folder) => {
				this.refresh_folder(folder);
				if (this.search_open) {
					this.browse.query = this.selector.search.text.strip();
				}
			});
			this.browse.file_activated.connect((file) => {
				this.choose(file);
			});
			this.append(this.button);
			this.files = new GLib.ListStore(typeof(OLLMfiles.File));
			this.list = new Gtk.ListBox() {
				hexpand = true,
				vexpand = true,
				activate_on_single_click = true,
				can_focus = false,
			};
			this.list.bind_model(this.files, (item) => {
				var file = (OLLMfiles.File) item;
				return this.browse.list_box_factory(file);
			});
			this.list_note = new Gtk.Label("No files") {
				xalign = 0,
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_top = 8,
				margin_bottom = 8,
				css_classes = { "dim-label" },
			};
			this.list.set_placeholder(this.list_note);
			this.file_list.files.items_changed.connect(() => {
				if (!this.search_open || !this.search_wide) {
					return;
				}
				if (this.filters.visible_child_name == "recent") {
					return;
				}
				if (this.file_list.files.get_n_items() == 0 && !this.file_list.files.empty) {
					return;
				}
				var query = this.selector.search.text.strip();
				var shown = false;
				var count = this.file_list.files.get_n_items();
				for (var i = 0; i < count; i++) {
					var file = (OLLMfiles.File) this.file_list.files.get_item(i);
					if (file != null && file.path_basename.down().contains(query.down())) {
						shown = true;
						break;
					}
				}
				if (shown) {
					this.browse.query = query;
					this.browse.visible = true;
					return;
				}
				this.browse.visible = false;
				this.files.remove_all();
				this.list_note.label = "too many results";
				if (this.list.get_parent() != this.tree_box) {
					this.list.unparent();
					this.tree_box.append(this.list);
				}
			});
			this.file_list.files.notify["empty"].connect(() => {
				if (!this.search_open || !this.search_wide || !this.file_list.files.empty) {
					return;
				}
				if (this.filters.visible_child_name == "recent") {
					return;
				}
				this.browse.visible = false;
				this.files.remove_all();
				this.list_note.label = "too many results";
				if (this.list.get_parent() != this.tree_box) {
					this.list.unparent();
					this.tree_box.append(this.list);
				}
			});
			this.list.row_activated.connect((line) => {
				var file = (OLLMfiles.File) this.files.get_item((uint) line.get_index());
				if (file == null) {
					return;
				}
				this.choose(file);
			});
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
			this.list.selection_mode = Gtk.SelectionMode.NONE;
			this.recent_scroll.child = this.list;
			this.file_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				visible = false,
			};
			this.file_bar.append(this.folder_tree.ghost);
			this.file_bar.append(new Gtk.StackSwitcher() {
				stack = this.filters,
				hexpand = true,
			});
			this.selector.prepend(this.file_bar);
			var loading_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				visible = false,
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				can_target = false,
			};
			var spinner = new Gtk.Spinner() {
				width_request = 16,
				height_request = 16,
				valign = Gtk.Align.CENTER,
			};
			loading_row.append(spinner);
			loading_row.append(new Gtk.Label("Loading folders") {
				halign = Gtk.Align.START,
				valign = Gtk.Align.CENTER,
			});
			var body = new Gtk.Overlay() {
				hexpand = true,
				vexpand = true,
				child = this.filters,
			};
			body.add_overlay(loading_row);
			this.folder_tree.folders.notify["loading"].connect(() => {
				spinner.spinning = this.folder_tree.folders.loading;
				loading_row.visible = this.folder_tree.folders.loading;
				this.filters.opacity = this.folder_tree.folders.loading ? 0 : 1;
			});
			var page = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
			};
			page.append(body);
			this.selector.pages.add_named(page, "file");
			this.path_box.visible = false;
			this.path_box.insert_before(
				this.selector.close.get_parent(), this.selector.close);
			var crumb_click = new Gtk.GestureClick() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE,
			};
			crumb_click.pressed.connect((n, x, y) => {
				if (n != 1) {
					return;
				}
				var widget = this.path_box.pick(x, y, Gtk.PickFlags.DEFAULT);
				while (widget != null &&
					widget != this.path_box &&
					!(widget is Gtk.Button)) {
					widget = widget.get_parent();
				}
				if (!(widget is Gtk.Button)) {
					return;
				}
				var target = ((Gtk.Button) widget).get_data<OLLMfiles.Folder>("folder");
				if (target == null) {
					return;
				}
				GLib.Idle.add(() => {
					this.refresh_folder(target);
					if (this.search_open) {
						this.browse.query = this.selector.search.text.strip();
					}
					return false;
				});
			});
			this.path_box.add_controller(crumb_click);
			this.path_box.notify["width"].connect(() => {
				if (this.fitting_crumbs) {
					return;
				}
				if (this.place_gen == 0) {
					return;
				}
				if (this.path_box.get_width() == this.fitted_width) {
					return;
				}
				this.render_crumbs();
				this.selector.current.visible = this.crumbs_shortened;
			});
			this.selector.pages.notify["visible-child-name"].connect(() => {
				var on_file = this.selector.pages.visible_child_name == "file";
				this.file_bar.visible = on_file;
				this.path_box.visible = on_file;
				this.selector.heading.visible = !on_file;
			});
			var keys = new Gtk.EventControllerKey();
			keys.key_pressed.connect((keyval, keycode, state) => {
				if (!this.selector.visible || this.selector.kind != "file") {
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
				this.browse.project = this.project;
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
				this.get_root().set_focus(null);
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
			this.selector.close.visible = true;
			this.file_bar.visible = true;
			this.selector.previous.visible = false;
			this.selector.heading.visible = false;
			this.path_box.visible = true;
			this.filters.visible_child_name = "tree";
			this.search_open = false;
			this.search_epoch++;
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
		}

		/**
		 * Refresh the phone page to one folder. The path buttons follow
		 * that folder, and the subtext line is shown only when a button
		 * is shortened to ''...''. {@link Folder.Browse} shows the level.
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
			this.selector.current.label = place;
			this.place_gen++;
			this.render_crumbs();
			this.selector.current.visible = this.crumbs_shortened;
			this.browse.visible = true;
			if (this.recent_scroll.child != this.list) {
				this.list.unparent();
				this.recent_scroll.child = this.list;
			}
			this.browse.refresh_folder(folder);
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
		 * Fill the visible phone list from the search box.
		 *
		 * An empty query on Tree returns to the folder that was open
		 * when the search started. A query checks the files already
		 * on screen before asking the server. It stays in that folder
		 * when it contains a match, and walks up until one does. No
		 * match shows ''no results''. A search the server will not
		 * return still shows matches from the open folder. Another
		 * folder with none shows ''too many results''. Recent fills
		 * the list with viewed files.
		 */
		private void on_search_changed_tree()
		{
			if (!this.project.is_project) {
				return;
			}
			var query = this.selector.search.text.strip();
			if (this.filters.visible_child_name == "recent") {
				if (this.recent_scroll.child != this.list) {
					this.list.unparent();
					this.recent_scroll.child = this.list;
				}
				this.history_epoch++;
				this.load(query, this.files, this.list, this.history_epoch, Slot.HISTORY);
				return;
			}
			if (query == "") {
				this.search_epoch++;
				this.search_wide = false;
				this.browse.query = "";
				this.folder_tree.search_reset();
				this.folder_tree.filter.changed(Gtk.FilterChange.DIFFERENT);
				if (this.search_open) {
					this.search_open = false;
					this.refresh_folder(this.search_home);
					return;
				}
				this.refresh_folder(this.level);
				return;
			}
			if (!this.search_open) {
				this.search_home = this.level;
				this.search_open = true;
			}
			var shown = false;
			var count = this.file_list.files.get_n_items();
			for (var i = 0; i < count; i++) {
				var file = (OLLMfiles.File) this.file_list.files.get_item(i);
				if (file != null && file.path_basename.down().contains(query.down())) {
					shown = true;
					break;
				}
			}
			if (shown) {
				this.search_epoch++;
				this.search_wide = false;
				this.folder_tree.search_reset();
				this.folder_tree.filter.changed(Gtk.FilterChange.DIFFERENT);
				this.browse.query = query;
				this.browse.visible = true;
				if (this.recent_scroll.child != this.list) {
					this.list.unparent();
					this.recent_scroll.child = this.list;
				}
				return;
			}
			this.search_epoch++;
			var epoch = this.search_epoch;
			this.project.fetch_files.begin(50, query, {}, false, false, (obj, res) => {
				this.on_load_results(epoch, res);
				if (epoch != this.search_epoch) {
					return;
				}
				if (this.file_list.notice == "too many results") {
					this.search_wide = true;
					var local = false;
					var n = this.file_list.files.get_n_items();
					for (var i = 0; i < n; i++) {
						var file = (OLLMfiles.File) this.file_list.files.get_item(i);
						if (file != null && file.path_basename.down().contains(query.down())) {
							local = true;
							break;
						}
					}
					if (local) {
						this.browse.query = query;
						this.browse.visible = true;
						return;
					}
					this.browse.visible = false;
					this.files.remove_all();
					this.list_note.label = "too many results";
					if (this.list.get_parent() != this.tree_box) {
						this.list.unparent();
						this.tree_box.append(this.list);
					}
					return;
				}
				this.search_wide = false;
				if (this.file_list.notice != "") {
					this.browse.visible = false;
					this.files.remove_all();
					this.list_note.label = this.file_list.notice;
					if (this.list.get_parent() != this.tree_box) {
						this.list.unparent();
						this.tree_box.append(this.list);
					}
					return;
				}
				var here = this.search_home;
				if (this.folder_tree.folders.path_map.has_key(here.path)) {
					here = this.folder_tree.folders.path_map.get(here.path);
				}
				var found = here;
				var matched = false;
				while (true) {
					if (this.folder_tree.visible.has_key((int) here.id)) {
						found = here;
						matched = true;
						break;
					}
					if (here.is_project) {
						break;
					}
					var parent_id = (int) here.parent_id;
					if (!this.folder_tree.folders.id_map.has_key(parent_id)) {
						break;
					}
					here = this.folder_tree.folders.id_map.get(parent_id);
				}
				if (!matched) {
					this.browse.visible = false;
					this.files.remove_all();
					this.list_note.label = "no results";
					if (this.list.get_parent() != this.tree_box) {
						this.list.unparent();
						this.tree_box.append(this.list);
					}
					return;
				}
				this.browse.query = query;
				this.refresh_folder(found);
			});
		}
	}
}
