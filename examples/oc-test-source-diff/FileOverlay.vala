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
	 * Desktop file sheet. Covers the editor.
	 *
	 * Recent sits beside Tree. The header is three slots. Collapse
	 * and the ghost sit on the left, Tree and Recent in the middle,
	 * and a stop mark on the right. That mark closes the sheet. On
	 * Recent the left buttons are hidden and that slot keeps its
	 * width. A click turns the file button into the search entry.
	 * Tablet uses the same sheet. The left pane is {@link FolderBrowse}
	 * with file loading off. The right pane stays the file list.
	 * Tree and Recent sit above the folder location. Search stays
	 * at the bottom and does not take focus when the sheet opens.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var files = new FileOverlay(manager);
	 * editor_layer.add_overlay(files.list);
	 * }}}
	 */
	class FileOverlay : FileNav
	{
		/**
		 * Desktop file sheet. Covers the editor. The host closes it
		 * when projects open.
		 */
		public Gtk.Box list { get; private set; }

		private Gtk.Stack face_stack;
		private Gtk.SearchEntry entry;
		private Gtk.Stack pages;
		private Gtk.ListBox recent_list;
		private GLib.ListStore recent_files;
		private uint search_wait = 0;
		private FolderBrowse browse;
		private Gtk.Button up;
		private Gtk.Label heading;

		/**
		 * Folder shown in the tablet left pane.
		 */
		private OLLMfiles.Folder level { get; set; }

		/**
		 * Build the tabbed sheet that covers the editor.
		 *
		 * @param manager Connected manager. Rows come from the project.
		 * @param form Desktop or tablet. Phone uses {@link FilePullout}.
		 */
		public FileOverlay(OLLMfiles.ProjectManager manager, Form form = Form.DESKTOP)
		{
			base(manager, form);
			this.entry = new Gtk.SearchEntry() {
				placeholder_text = "Search files",
				hexpand = true,
			};
			this.face_stack = new Gtk.Stack() {
				hhomogeneous = false,
				vhomogeneous = false,
				hexpand = true,
				valign = Gtk.Align.START,
			};
			this.face_stack.add_named(this.button, "button");
			if (this.form == Form.TABLET) {
				this.entry.can_focus = false;
				this.entry.focus_on_click = false;
				this.entry.margin_start = 8;
				this.entry.margin_end = 8;
				this.entry.margin_top = 8;
				this.entry.margin_bottom = 8;
				var search_inner = this.entry.get_first_child();
				while (search_inner != null) {
					search_inner.can_focus = false;
					search_inner.focus_on_click = false;
					search_inner = search_inner.get_next_sibling();
				}
				var search_press = new Gtk.GestureClick() {
					propagation_phase = Gtk.PropagationPhase.CAPTURE,
				};
				search_press.pressed.connect(() => {
					this.entry.can_focus = true;
					this.entry.focus_on_click = true;
					var child = this.entry.get_first_child();
					while (child != null) {
						child.can_focus = true;
						child.focus_on_click = true;
						child = child.get_next_sibling();
					}
					this.entry.grab_focus();
				});
				this.entry.add_controller(search_press);
			}
			if (this.form != Form.TABLET) {
				this.face_stack.add_named(this.entry, "entry");
			}
			this.append(this.face_stack);
			this.recent_files = new GLib.ListStore(typeof(OLLMfiles.File));
			this.recent_list = new Gtk.ListBox() {
				hexpand = true,
				activate_on_single_click = true,
				selection_mode = Gtk.SelectionMode.NONE,
				can_focus = false,
			};
			this.recent_list.bind_model(this.recent_files, (item) => {
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
			this.recent_list.set_placeholder(new Gtk.Label("No recent files") {
				xalign = 0,
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_top = 8,
				margin_bottom = 8,
				css_classes = { "dim-label" },
			});
			var folders = (Gtk.Widget) this.folder_tree;
			if (this.form == Form.TABLET) {
				this.level = this.project;
				this.browse = new FolderBrowse(this.folder_tree, this.file_list, this.project, false);
				this.up = new Gtk.Button.from_icon_name("go-previous-symbolic") {
					tooltip_text = "Up",
					can_focus = false,
					valign = Gtk.Align.CENTER,
					visible = false,
					css_classes = { "flat" },
				};
				this.browse.selected.connect((folder) => {
					this.level = folder;
					this.browse.project = this.project;
					this.browse.refresh_folder(folder);
					this.file_list.load(folder);
					if (this.search_open) {
						this.file_list.query = this.entry.text.strip();
					}
					this.up.visible = !folder.is_project;
				});
				this.up.clicked.connect(() => {
					var parent = this.level.parent;
					if (this.level.is_project || parent == null) {
						return;
					}
					this.level = parent;
					this.browse.project = this.project;
					this.browse.refresh_folder(parent);
					this.file_list.load(parent);
					if (this.search_open) {
						this.file_list.query = this.entry.text.strip();
					}
					this.up.visible = !parent.is_project;
				});
				this.file_list.files.items_changed.connect(() => {
					if (!this.search_open || !this.search_wide) {
						return;
					}
					if (this.file_list.files.get_n_items() == 0 && !this.file_list.files.empty) {
						return;
					}
					var query = this.entry.text.strip();
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
						this.file_list.notice = "";
						this.file_list.query = query;
						return;
					}
					this.file_list.notice = "too many results";
				});
				this.file_list.files.notify["empty"].connect(() => {
					if (!this.search_open || !this.search_wide || !this.file_list.files.empty) {
						return;
					}
					this.file_list.notice = "too many results";
				});
				folders = this.browse;
			}
			this.pages = new Gtk.Stack() {
				hexpand = true,
				hhomogeneous = true,
				vhomogeneous = false,
			};
			this.pages.add_titled(new Gtk.Paned(Gtk.Orientation.HORIZONTAL) {
				hexpand = true,
				vexpand = true,
				position = 240,
				resize_start_child = true,
				resize_end_child = true,
				shrink_start_child = false,
				shrink_end_child = true,
				start_child = folders,
				end_child = this.file_list,
			}, "tree", "Tree");
			this.pages.add_titled(this.recent_list, "history", "Recent");
			this.pages.visible_child_name = "tree";
			var left = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				margin_start = 6,
				halign = Gtk.Align.START,
			};
			left.append(this.folder_tree.collapse);
			left.append(this.folder_tree.ghost);
			if (this.form == Form.TABLET) {
				this.folder_tree.collapse.visible = false;
			}
			var close_files = new Gtk.Button.from_icon_name("process-stop-symbolic") {
				tooltip_text = "Close",
				has_tooltip = true,
				can_focus = false,
				valign = Gtk.Align.CENTER,
				css_classes = { "flat" },
			};
			var pointer = new Gdk.Cursor.from_name("pointer", null);
			if (pointer != null) {
				close_files.set_cursor(pointer);
			}
			var right = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				margin_end = 6,
				halign = Gtk.Align.END,
			};
			right.append(close_files);
			var switcher = new Gtk.StackSwitcher() {
				stack = this.pages,
				hexpand = true,
			};
			var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				margin_bottom = 6,
				css_classes = { "horizontal", "file-bar" },
			};
			header.append(left);
			header.append(switcher);
			if (this.form != Form.TABLET) {
				header.append(right);
			}
			var place_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				margin_start = 6,
				margin_end = 6,
				margin_top = 6,
			};
			if (this.form == Form.TABLET) {
				this.heading = new Gtk.Label("") {
					hexpand = true,
					xalign = 0,
					ellipsize = Pango.EllipsizeMode.START,
				};
				this.heading.add_css_class("title-2");
				place_row.append(this.up);
				place_row.append(this.heading);
				place_row.append(close_files);
				this.notify["level"].connect(() => {
					var shown = this.level.path;
					var root = this.project.path;
					var slash = root.last_index_of_char('/');
					if (slash >= 0 && shown.has_prefix(root.substring(0, slash + 1))) {
						shown = shown.substring(slash + 1);
					}
					if (shown == "") {
						shown = this.project.path_basename;
					}
					this.heading.label = shown;
					this.up.visible = !this.level.is_project;
				});
				this.level = this.project;
				this.notify_property("level");
			}
			this.pages.notify["visible-child-name"].connect(() => {
				var on_tree = this.pages.visible_child_name == "tree";
				this.folder_tree.collapse.opacity = on_tree ? 1 : 0;
				this.folder_tree.ghost.opacity = on_tree ? 1 : 0;
				this.folder_tree.collapse.sensitive = on_tree;
				this.folder_tree.ghost.sensitive = on_tree;
				if (!this.project.is_project) {
					return;
				}
				var text = this.entry.text.strip();
				if (!on_tree) {
					this.history_epoch++;
					this.load(text, this.recent_files, this.recent_list,
						this.history_epoch, Slot.HISTORY);
					return;
				}
				if (text == "") {
					this.folder_tree.search_reset();
					this.folder_tree.filter.changed(Gtk.FilterChange.DIFFERENT);
					this.file_list.notice = "";
					this.file_list.query = "";
					this.label.label = this.path_text;
					return;
				}
				this.file_list.query = text;
				this.search_epoch++;
				var epoch = this.search_epoch;
				this.project.fetch_files.begin(50, text, {}, false, false, (obj, res) => {
					this.on_load_results(epoch, res);
				});
			});
			var scroll = new Gtk.ScrolledWindow() {
				child = this.pages,
				hexpand = true,
				vexpand = true,
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				can_focus = false,
			};
			this.list = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
				visible = false,
				can_focus = false,
				css_classes = { "vertical", "file-sheet" },
			};
			this.list.append(header);
			if (this.form == Form.TABLET) {
				this.list.append(place_row);
			}
			this.list.append(scroll);
			if (this.form == Form.TABLET) {
				this.list.append(this.entry);
			}
			close_files.clicked.connect(() => {
				GLib.Idle.add(() => {
					this.list.visible = false;
					return false;
				});
			});
			this.list.notify["visible"].connect(() => {
				if (this.list.visible) {
					return;
				}
				this.face_stack.visible_child_name = "button";
			});
			this.realize.connect(() => {
				var window = this.get_root() as Gtk.Window;
				if (window == null) {
					return;
				}
				window.notify["is-active"].connect(() => {
					if (window.is_active || !this.list.visible) {
						return;
					}
					this.list.visible = false;
				});
			});
			this.recent_list.row_activated.connect((line) => {
				var file = (OLLMfiles.File) this.recent_files.get_item((uint) line.get_index());
				if (file == null) {
					return;
				}
				this.choose(file);
			});
			var keys = new Gtk.EventControllerKey() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE,
			};
			keys.key_pressed.connect(this.key_press);
			var sheet_keys = new Gtk.EventControllerKey() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE,
			};
			sheet_keys.key_pressed.connect(this.key_press);
			this.list.add_controller(sheet_keys);
			this.entry.search_changed.connect(() => {
				if (this.search_wait != 0) {
					GLib.Source.remove(this.search_wait);
				}
				this.search_wait = GLib.Timeout.add(200, () => {
					this.search_wait = 0;
					if (this.pages.visible_child_name == "history") {
						this.on_search_changed_history();
						return false;
					}
					this.on_search_changed_tree();
					return false;
				});
			});
			this.entry.add_controller(keys);
			var focus = new Gtk.EventControllerFocus();
			focus.leave.connect(() => {
				if (!this.list.visible) {
					return;
				}
				var root = this.get_root();
				if (root == null) {
					this.list.visible = false;
					return;
				}
				var focused = root.get_focus() as Gtk.Widget;
				if (focused != null && (focused == this.list || focused.is_ancestor(this.list))) {
					return;
				}
				this.list.visible = false;
			});
			this.entry.add_controller(focus);
			this.button.clicked.connect(() => {
				if (this.list.visible) {
					this.list.visible = false;
					return;
				}
				this.opened();
				this.search_open = false;
				this.search_epoch++;
				this.pages.visible_child_name = "tree";
				if (this.form != Form.TABLET) {
					this.face_stack.visible_child_name = "entry";
					this.folder_tree.folders.load.begin(this.project);
					this.entry.text = "";
					this.history_epoch++;
					this.load("", this.recent_files, this.recent_list,
						this.history_epoch, Slot.HISTORY);
					this.list.visible = true;
					this.entry.grab_focus();
					this.entry.set_position(-1);
					this.entry.select_region(-1, -1);
					return;
				}
				if (this.folder_tree.folders.loaded.contains(this.project.path)) {
					this.level = this.project;
					this.browse.project = this.project;
					this.browse.refresh_folder(this.project);
					this.file_list.load(this.project);
					this.up.visible = false;
					this.entry.text = "";
					this.history_epoch++;
					this.load("", this.recent_files, this.recent_list,
						this.history_epoch, Slot.HISTORY);
					this.list.visible = true;
					return;
				}
				this.folder_tree.folders.load.begin(this.project, (obj, res) => {
					this.folder_tree.folders.load.end(res);
					this.level = this.project;
					this.browse.project = this.project;
					this.browse.refresh_folder(this.project);
					this.file_list.load(this.project);
					this.up.visible = false;
					this.entry.text = "";
					this.history_epoch++;
					this.load("", this.recent_files, this.recent_list,
						this.history_epoch, Slot.HISTORY);
					this.list.visible = true;
				});
			});
			this.notify["project"].connect(() => {
				if (!this.project.is_project) {
					return;
				}
				this.history_epoch++;
				this.recent_files.remove_all();
				this.pages.visible_child_name = "tree";
				this.opened();
				this.search_open = false;
				this.search_epoch++;
				this.pages.visible_child_name = "tree";
				if (this.form != Form.TABLET) {
					this.face_stack.visible_child_name = "entry";
					if (!this.folder_tree.folders.loaded.contains(this.project.path)) {
						this.folder_tree.folders.load.begin(this.project);
					}
					this.entry.text = "";
					this.history_epoch++;
					this.load("", this.recent_files, this.recent_list,
						this.history_epoch, Slot.HISTORY);
					this.list.visible = true;
					this.entry.grab_focus();
					this.entry.set_position(-1);
					this.entry.select_region(-1, -1);
					return;
				}
				if (this.folder_tree.folders.loaded.contains(this.project.path)) {
					this.level = this.project;
					this.browse.project = this.project;
					this.browse.refresh_folder(this.project);
					this.file_list.load(this.project);
					this.up.visible = false;
					this.entry.text = "";
					this.history_epoch++;
					this.load("", this.recent_files, this.recent_list,
						this.history_epoch, Slot.HISTORY);
					this.list.visible = true;
					return;
				}
				this.folder_tree.folders.load.begin(this.project, (obj, res) => {
					this.folder_tree.folders.load.end(res);
					this.level = this.project;
					this.browse.project = this.project;
					this.browse.refresh_folder(this.project);
					this.file_list.load(this.project);
					this.up.visible = false;
					this.entry.text = "";
					this.history_epoch++;
					this.load("", this.recent_files, this.recent_list,
						this.history_epoch, Slot.HISTORY);
					this.list.visible = true;
				});
			});
			this.chosen.connect(() => {
				GLib.Idle.add(() => {
					this.list.visible = false;
					return false;
				});
			});
		}

		/**
		 * Fill the recent-file list from the history search box.
		 * A later history fetch drops this reply.
		 */
		private void on_search_changed_history()
		{
			var query = this.entry.text.strip();
			if (!this.project.is_project) {
				return;
			}
			this.file_list.query = query;
			this.history_epoch++;
			this.load(query, this.recent_files, this.recent_list,
				this.history_epoch, Slot.HISTORY);
		}

		/**
		 * Update the open sheet from the search box.
		 *
		 * Desktop marks matching folders on the tree. Tablet checks the
		 * files already on screen before asking the server. It stays
		 * in the folder that was open when the search started when
		 * that folder contains a match, and walks up until one does.
		 * No match shows ''no results''. A search the server will not
		 * return still shows matches from the open folder. Another
		 * folder with none shows ''too many results''. Clearing the
		 * search returns to the folder that was open when it started.
		 */
		private void on_search_changed_tree()
		{
			var query = this.entry.text.strip();
			if (!this.project.is_project) {
				return;
			}
			if (this.form != Form.TABLET) {
				if (query == "") {
					this.folder_tree.search_reset();
					this.folder_tree.filter.changed(Gtk.FilterChange.DIFFERENT);
					this.file_list.notice = "";
					this.file_list.query = "";
					this.label.label = this.path_text;
					return;
				}
				this.file_list.query = query;
				this.search_epoch++;
				var epoch = this.search_epoch;
				this.project.fetch_files.begin(50, query, {}, false, false, (obj, res) => {
					this.on_load_results(epoch, res);
				});
				return;
			}
			if (query == "") {
				this.search_epoch++;
				this.search_wide = false;
				this.folder_tree.search_reset();
				this.folder_tree.filter.changed(Gtk.FilterChange.DIFFERENT);
				this.file_list.notice = "";
				this.file_list.query = "";
				this.label.label = this.path_text;
				if (!this.search_open) {
					return;
				}
				this.search_open = false;
				this.level = this.search_home;
				this.browse.refresh_folder(this.search_home);
				this.file_list.load(this.search_home);
				this.up.visible = !this.search_home.is_project;
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
				this.file_list.query = query;
				this.file_list.notice = "";
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
						this.file_list.query = query;
						this.file_list.notice = "";
					}
					return;
				}
				this.search_wide = false;
				if (this.file_list.notice != "") {
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
					this.file_list.notice = "no results";
					return;
				}
				this.level = found;
				this.browse.refresh_folder(found);
				this.file_list.query = query;
				this.file_list.load(found);
				this.up.visible = !found.is_project;
			});
		}

		/**
		 * Keyboard for the open sheet. Escape closes it. On the
		 * tree tab, Up and Down step the selected folder. A
		 * selected file takes those keys and steps the file list.
		 * Right on an expandable folder opens it and selects the
		 * first child. On Recent, Enter and Tab activate the
		 * marked row. Up and Down move that mark.
		 *
		 * @param keyval Key that was pressed
		 * @param keycode Hardware key code, unused
		 * @param state Modifier mask, unused
		 * @return Whether the key was handled
		 */
		private bool key_press(uint keyval, uint keycode, Gdk.ModifierType state)
		{
			if (!this.list.visible) {
				return false;
			}
			if (this.form == Form.TABLET && keyval == Gdk.Key.Back) {
				if (this.up.visible) {
					this.up.activate();
				}
				return true;
			}
			if (keyval == Gdk.Key.Escape) {
				this.list.visible = false;
				return true;
			}
			if (this.pages.visible_child_name != "history") {
				if (keyval == Gdk.Key.Right) {
					if (this.form == Form.TABLET) {
						return true;
					}
					if (this.folder_tree.tree_selection.n_items < 1 ||
							this.folder_tree.tree_selection.selected == Gtk.INVALID_LIST_POSITION) {
						return true;
					}
					var row = (Gtk.TreeListRow) this.folder_tree.tree_selection.selected_item;
					if (!row.expandable) {
						return true;
					}
					row.expanded = true;
					var child = row.get_child_row(0);
					if (child == null) {
						return true;
					}
					this.folder_tree.tree_selection.selected = child.get_position();
					return true;
				}
				if (keyval != Gdk.Key.Down && keyval != Gdk.Key.Up) {
					return false;
				}
				var step = 1;
				if (keyval == Gdk.Key.Up) {
					step = -1;
				}
				var files = this.file_list.file_selection;
				if (this.file_list.notice == "" && files.n_items > 0 &&
						files.selected != Gtk.INVALID_LIST_POSITION) {
					var next = (int) files.selected + step;
					if (next < 0 || next >= (int) files.n_items) {
						return true;
					}
					files.selected = (uint) next;
					return true;
				}
				var folders = this.folder_tree.tree_selection;
				if (this.form == Form.TABLET ||
					folders.n_items < 1 ||
					folders.selected == Gtk.INVALID_LIST_POSITION) {
					return true;
				}
				var next_folder = (int) folders.selected + step;
				if (next_folder < 0 || next_folder >= (int) folders.n_items) {
					return true;
				}
				folders.selected = (uint) next_folder;
				return true;
			}
			switch (keyval) {
				case Gdk.Key.Return:
				case Gdk.Key.KP_Enter:
				case Gdk.Key.ISO_Enter:
				case Gdk.Key.Tab:
				case Gdk.Key.KP_Tab:
				case Gdk.Key.ISO_Left_Tab:
					var chosen = this.recent_list.get_first_child();
					while (chosen != null) {
						if (!chosen.has_css_class("selector-mark")) {
							chosen = chosen.get_next_sibling();
							continue;
						}
						((Gtk.ListBoxRow) chosen).activate();
						return true;
					}
					return keyval != Gdk.Key.Tab && keyval != Gdk.Key.KP_Tab && keyval != Gdk.Key.ISO_Left_Tab;
				case Gdk.Key.Down:
				case Gdk.Key.Up:
					var count = 0;
					var marked_index = -1;
					var child = this.recent_list.get_first_child();
					while (child != null) {
						if (child.has_css_class("selector-mark")) {
							marked_index = count;
						}
						count++;
						child = child.get_next_sibling();
					}
					if (count < 1) {
						return true;
					}
					var next_index = 0;
					if (marked_index >= 0 && keyval == Gdk.Key.Down) {
						next_index = marked_index + 1;
					}
					if (marked_index >= 0 && keyval == Gdk.Key.Up) {
						next_index = marked_index - 1;
					}
					next_index = next_index.clamp(0, count - 1);
					var target = this.recent_list.get_row_at_index(next_index);
					if (target == null || !target.activatable) {
						return true;
					}
					child = this.recent_list.get_first_child();
					while (child != null) {
						child.remove_css_class("selector-mark");
						child = child.get_next_sibling();
					}
					target.add_css_class("selector-mark");
					return true;
				default:
					return false;
			}
		}
	}
}
