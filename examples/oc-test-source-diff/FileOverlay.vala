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
 * Desktop file sheet. Covers the editor.
 *
 * Recent sits beside Tree. The header is three slots. Collapse
 * and the ghost sit on the left, Tree and Recent in the middle,
 * and a stop mark on the right. That mark closes the sheet. On
 * Recent the left buttons are hidden and that slot keeps its
 * width. A click turns the file button into the search entry.
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
	private Gtk.ListBox history_rows;
	private uint search_wait = 0;

	/**
	 * Build the tabbed sheet that covers the editor.
	 *
	 * @param manager Connected manager. Rows come from the project.
	 */
	public FileOverlay(OLLMfiles.ProjectManager manager)
	{
		base(manager, "desktop");
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
		this.face_stack.add_named(this.entry, "entry");
		this.append(this.face_stack);
		this.history_rows = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.NONE,
			activate_on_single_click = true,
			hexpand = true,
			can_focus = false,
		};
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
			start_child = this.folder_tree,
			end_child = this.file_list,
		}, "tree", "Tree");
		this.pages.add_titled(this.history_rows, "history", "Recent");
		this.pages.visible_child_name = "tree";
		var left = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
			margin_start = 6,
			halign = Gtk.Align.START,
		};
		left.append(this.folder_tree.collapse);
		left.append(this.folder_tree.ghost);
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
		header.append(right);
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
				this.load(text, this.history_rows, true, this.history_epoch, "history");
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
		this.list.append(scroll);
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
		this.history_rows.row_activated.connect((line) => {
			var file = line.get_data<OLLMfiles.File>("file");
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
			this.face_stack.visible_child_name = "entry";
			this.pages.visible_child_name = "tree";
			if (this.project.is_project) {
				this.folder_tree.folders.load.begin(this.project);
			}
			this.entry.text = "";
			this.history_epoch++;
			this.load("", this.history_rows, true, this.history_epoch, "history");
			this.list.visible = true;
			this.entry.grab_focus();
			this.entry.set_position(-1);
			this.entry.select_region(-1, -1);
		});
		this.notify["project"].connect(() => {
			if (!this.project.is_project) {
				return;
			}
			this.history_epoch++;
			this.clear(this.history_rows);
			this.pages.visible_child_name = "tree";
			this.opened();
			this.face_stack.visible_child_name = "entry";
			this.pages.visible_child_name = "tree";
			if (!this.folder_tree.folders.loaded.contains(this.project.path)) {
				this.folder_tree.folders.load.begin(this.project);
			}
			this.entry.text = "";
			this.history_epoch++;
			this.load("", this.history_rows, true, this.history_epoch, "history");
			this.list.visible = true;
			this.entry.grab_focus();
			this.entry.set_position(-1);
			this.entry.select_region(-1, -1);
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
		this.load(query, this.history_rows, true, this.history_epoch, "history");
	}

	/**
	 * Update the folder tree from the search box.
	 *
	 * An empty query clears the tree filter. A name query marks
	 * matching folders.
	 */
	private void on_search_changed_tree()
	{
		var query = this.entry.text.strip();
		if (!this.project.is_project) {
			return;
		}
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
		if (keyval == Gdk.Key.Escape) {
			this.list.visible = false;
			return true;
		}
		if (this.pages.visible_child_name != "history") {
			if (keyval == Gdk.Key.Right) {
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
			if (folders.n_items < 1 || folders.selected == Gtk.INVALID_LIST_POSITION) {
				return true;
			}
			var next_folder = (int) folders.selected + step;
			if (next_folder < 0 || next_folder >= (int) folders.n_items) {
				return true;
			}
			folders.selected = (uint) next_folder;
			return true;
		}
		var lines = this.history_rows;
		switch (keyval) {
			case Gdk.Key.Return:
			case Gdk.Key.KP_Enter:
			case Gdk.Key.ISO_Enter:
			case Gdk.Key.Tab:
			case Gdk.Key.KP_Tab:
			case Gdk.Key.ISO_Left_Tab:
				var chosen = lines.get_first_child();
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
				var child = lines.get_first_child();
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
				var target = lines.get_row_at_index(next_index);
				if (target == null || !target.activatable) {
					return true;
				}
				child = lines.get_first_child();
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
