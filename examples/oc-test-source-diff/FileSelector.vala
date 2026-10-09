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
 * File selector. Replaces {@link OLLMcoder.FileDropdown}.
 *
 * Hidden until a project is chosen. Desktop opens a wide pop-down
 * with Tree, History, and Search. Search appears once the entry has
 * text. Phone and tablet use {@link SelectorPull} and do not copy
 * the desktop tabs.
 *
 * == Example ==
 *
 * {{{
 * var files = new FileSelector(manager, "desktop", pull);
 * projects.chosen.connect((folder) => {
 *     files.project = folder;
 * });
 * }}}
 */
class FileSelector : Gtk.Box
{
	/**
	 * Emitted when the desktop pop-down is about to open.
	 *
	 * The host closes the project pop-down from this.
	 */
	public signal void opened();

	/**
	 * Emitted after a file row is chosen.
	 *
	 * @param file File that was chosen
	 */
	public signal void chosen(OLLMfiles.File file);

	/**
	 * Desktop file pop-down. The host closes it when projects open.
	 */
	public Gtk.Popover popover { get; private set; }

	/**
	 * Active project. Setting a real project shows this control.
	 * Desktop then opens the pop-down. An empty folder stays hidden.
	 */
	public OLLMfiles.Folder project { get; set; }

	/**
	 * Connected manager. File rows come from its active project.
	 */
	public OLLMfiles.ProjectManager manager { get; set; }

	/**
	 * Layout: ''desktop'', ''phone'', or ''tablet''.
	 */
	public string form { get; set; default = "desktop"; }

	/**
	 * Shared phone and tablet surface. Desktop leaves it hidden.
	 */
	public SelectorPull pull { get; set; }
	private Gtk.Label label;
	private Gtk.Button button;
	private Gtk.Stack face_stack;
	private Gtk.SearchEntry entry;
	private Gtk.ScrolledWindow scroll;
	private Gtk.Stack pages;
	private Gtk.ListBox history_rows;
	private Gtk.ListBox search_rows;
	private Gtk.ListBox pull_rows;
	private uint file_wait = 0;
	private int search_epoch = 0;
	private int history_epoch = 0;
	private int pull_epoch = 0;

	/**
	 * Build the file button, tabbed pop-down, and pull-over page.
	 *
	 * @param manager Connected manager. File rows come from the project.
	 * @param form ''desktop'', ''phone'', or ''tablet''
	 * @param pull Shared phone and tablet surface
	 */
	public FileSelector(OLLMfiles.ProjectManager manager, string form, SelectorPull pull)
	{
		Object(
			orientation: Gtk.Orientation.HORIZONTAL,
			spacing: 0,
			hexpand: true,
			valign: Gtk.Align.START,
			visible: false,
			manager: manager,
			form: form,
			pull: pull,
			project: new OLLMfiles.Folder(manager)
		);
		this.label = new Gtk.Label("Select file") {
			xalign = 0,
			halign = Gtk.Align.START,
			hexpand = true,
		};
		switch (this.form) {
		case "phone":
			this.label.ellipsize = Pango.EllipsizeMode.END;
			break;

		default:
			this.label.ellipsize = Pango.EllipsizeMode.START;
			break;
		}
		var face = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		face.append(new Gtk.Image.from_icon_name("system-search-symbolic"));
		face.append(this.label);
		this.button = new Gtk.Button() {
			child = face,
			hexpand = true,
			valign = Gtk.Align.CENTER,
		};
		this.button.add_css_class("flat");
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

		var tree_note = new Gtk.Label(
			"Folder tree is not loaded on the client. The tree model stays in CODER-4.2.1."
		) {
			xalign = 0,
			halign = Gtk.Align.START,
			wrap = true,
			margin_start = 12,
			margin_end = 12,
			margin_top = 12,
			margin_bottom = 12,
		};
		tree_note.add_css_class("caption");
		tree_note.add_css_class("dim-label");
		this.history_rows = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.NONE,
			activate_on_single_click = true,
			hexpand = true,
			can_focus = false,
		};
		this.search_rows = new Gtk.ListBox() {
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
		this.pages.add_titled(tree_note, "tree", "Tree");
		this.pages.add_titled(this.history_rows, "history", "History");
		this.pages.add_titled(this.search_rows, "search", "Search");
		this.pages.get_page(this.search_rows).visible = false;
		this.pages.visible_child_name = "history";
		var switcher = new Gtk.StackSwitcher() {
			stack = this.pages,
			hexpand = true,
		};
		this.scroll = new Gtk.ScrolledWindow() {
			child = this.pages,
			min_content_width = 560,
			max_content_width = 560,
			propagate_natural_height = true,
			propagate_natural_width = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
			can_focus = false,
		};
		var frame = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			width_request = 560,
		};
		frame.append(switcher);
		frame.append(this.scroll);
		this.popover = new Gtk.Popover() {
			has_arrow = false,
			position = Gtk.PositionType.BOTTOM,
			halign = Gtk.Align.START,
			autohide = false,
			can_focus = false,
			child = frame,
		};
		this.popover.set_parent(this);
		this.popover.closed.connect(() => {
			this.face_stack.visible_child_name = "button";
		});
		this.popover.map.connect(() => {
			GLib.Idle.add(() => {
				this.place();
				return false;
			});
		});

		this.pull_rows = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.SINGLE,
			activate_on_single_click = true,
			hexpand = true,
			vexpand = true,
		};
		var pull_scroll = new Gtk.ScrolledWindow() {
			child = this.pull_rows,
			hexpand = true,
			vexpand = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
		};
		this.pull.pages.add_named(pull_scroll, "file");

		this.history_rows.row_activated.connect((line) => {
			this.choose(line);
		});
		this.search_rows.row_activated.connect((line) => {
			this.choose(line);
		});
		this.pull_rows.row_activated.connect((line) => {
			this.choose(line);
		});
		this.entry.search_changed.connect(() => {
			var query = this.entry.text.strip();
			var search_page = this.pages.get_page(this.search_rows);
			if (query == "") {
				search_page.visible = false;
				if (this.pages.visible_child_name == "search") {
					this.pages.visible_child_name = "history";
				}
				return;
			}
			search_page.visible = true;
			this.pages.visible_child_name = "search";
			this.schedule(query, this.search_rows, false, "search");
		});
		this.pages.notify["visible-child-name"].connect(() => {
			if (this.pages.visible_child_name != "search") {
				return;
			}
			this.schedule(this.entry.text.strip(), this.search_rows, false, "search");
		});
		this.pull.search.search_changed.connect(() => {
			if (this.pull.kind != "file") {
				return;
			}
			this.schedule(this.pull.search.text.strip(), this.pull_rows, false, "pull");
		});
		var keys = new Gtk.EventControllerKey();
		keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
		keys.key_pressed.connect(this.key_press);
		this.entry.add_controller(keys);
		var focus = new Gtk.EventControllerFocus();
		focus.leave.connect(() => {
			if (!this.popover.visible) {
				return;
			}
			var root = this.get_root();
			if (root == null) {
				this.popover.popdown();
				return;
			}
			var focused = root.get_focus() as Gtk.Widget;
			if (focused != null && (focused == this.popover || focused.is_ancestor(this.popover))) {
				return;
			}
			this.popover.popdown();
		});
		this.entry.add_controller(focus);
		this.button.clicked.connect(() => {
			switch (this.form) {
			case "phone":
			case "tablet":
				this.pull.kind = "file";
				this.pull.heading.label = "Files";
				this.pull.current.label = this.label.label;
				if (this.form != "phone" && this.button.tooltip_text != "") {
					this.pull.current.label = this.button.tooltip_text;
				}
				this.pull.pages.visible_child_name = "file";
				this.pull.search.placeholder_text = "Search files";
				this.pull.visible = true;
				this.pull.search.text = " ";
				this.pull.search.text = "";
				return;
			default:
				break;
			}
			this.open_desktop();
		});
		this.notify["project"].connect(() => {
			if (!this.project.is_project) {
				return;
			}
			this.search_epoch++;
			this.history_epoch++;
			this.pull_epoch++;
			this.clear(this.history_rows);
			this.clear(this.search_rows);
			this.clear(this.pull_rows);
			this.pages.get_page(this.search_rows).visible = false;
			this.pages.visible_child_name = "history";
			this.label.label = "Select file";
			this.button.tooltip_text = "";
			this.visible = true;
			if (this.form != "desktop") {
				return;
			}
			this.open_desktop();
		});
	}

	/**
	 * Remove every row from a file list.
	 *
	 * @param target List to empty
	 */
	private void clear(Gtk.ListBox target)
	{
		var child = target.get_first_child();
		while (child != null) {
			target.remove(child);
			child = target.get_first_child();
		}
	}

	/**
	 * Replace a file list with one fetch page.
	 *
	 * History keeps rows whose last view is set. Search and the
	 * pull-over keep every row in the page.
	 *
	 * @param response Daemon page from ''Folder.fetch_files''
	 * @param target List that receives the rows
	 * @param recent Keep only files that have been viewed
	 */
	private void paint(OLLMrpc.Response response, Gtk.ListBox target, bool recent)
	{
		this.clear(target);
		var showed = false;
		if (response.retval.type() != GLib.Type.INVALID) {
			var files = (Gee.ArrayList<OLLMfiles.File>) response.retval.get_object();
			foreach (var file in files) {
				if (recent && file.last_viewed < 1) {
					continue;
				}
				showed = true;
				var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
					margin_start = 12,
					margin_end = 12,
					margin_top = 8,
					margin_bottom = 8,
				};
				var title = new Gtk.Label(file.path_basename) {
					xalign = 0,
					halign = Gtk.Align.START,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.END,
					css_classes = { "body", "list-chat-title" },
				};
				var caption = new Gtk.Label(file.path) {
					xalign = 0,
					halign = Gtk.Align.START,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.START,
					css_classes = { "caption", "dim-label" },
				};
				column.append(title);
				column.append(caption);
				var line = new Gtk.ListBoxRow() {
					child = column,
				};
				line.set_data<OLLMfiles.File>("file", file);
				target.append(line);
			}
		}
		if (showed) {
			var first = target.get_row_at_index(0);
			if (first != null && first.activatable) {
				first.add_css_class("selector-mark");
			}
			return;
		}
		var empty_text = "No files";
		if (recent) {
			empty_text = "No recent files";
		}
		var note = new Gtk.Label(empty_text) {
			xalign = 0,
			halign = Gtk.Align.START,
			margin_start = 12,
			margin_top = 8,
			margin_bottom = 8,
		};
		note.add_css_class("dim-label");
		target.append(new Gtk.ListBoxRow() {
			activatable = false,
			selectable = false,
			child = note,
		});
	}

	/**
	 * Fetch one file page into a list. A newer fetch for the same
	 * slot drops this reply.
	 *
	 * @param query Daemon filter. Empty browses the project.
	 * @param target List that receives the page
	 * @param recent History filter
	 * @param epoch Generation captured when the fetch started
	 * @param slot ''search'', ''history'', or ''pull''
	 */
	private void load(
		string query,
		Gtk.ListBox target,
		bool recent,
		int epoch,
		string slot
	) {
		this.project.fetch_files.begin(0, 50, query, {}, false, (obj, res) => {
			switch (slot) {
			case "search":
				if (epoch != this.search_epoch) {
					return;
				}
				break;

			case "history":
				if (epoch != this.history_epoch) {
					return;
				}
				break;

			default:
				if (epoch != this.pull_epoch) {
					return;
				}
				break;
			}
			OLLMrpc.Response response;
			try {
				response = this.project.fetch_files.end(res);
			} catch (GLib.Error e) {
				GLib.warning("file list failed: %s", e.message);
				return;
			}
			this.paint(response, target, recent);
		});
	}

	/**
	 * Debounce a file fetch. A newer request cancels the pending one.
	 *
	 * @param query Daemon filter
	 * @param target List that receives the page
	 * @param recent History filter
	 * @param slot ''search'', ''history'', or ''pull''
	 */
	private void schedule(string query, Gtk.ListBox target, bool recent, string slot)
	{
		if (this.file_wait != 0) {
			GLib.Source.remove(this.file_wait);
		}
		this.file_wait = GLib.Timeout.add(200, () => {
			this.file_wait = 0;
			if (!this.project.is_project) {
				return false;
			}
			switch (slot) {
			case "search":
				this.search_epoch++;
				this.load(query, target, recent, this.search_epoch, slot);
				break;

			case "history":
				this.history_epoch++;
				this.load(query, target, recent, this.history_epoch, slot);
				break;

			default:
				this.pull_epoch++;
				this.load(query, target, recent, this.pull_epoch, slot);
				break;
			}
			return false;
		});
	}

	/**
	 * Keyboard for the open pop-down. Escape closes it. Enter
	 * and Tab activate the marked row on the visible list and
	 * move on. Up and Down move that mark. The tree tab has
	 * no rows.
	 *
	 * @param keyval Key that was pressed
	 * @param keycode Hardware key code, unused
	 * @param state Modifier mask, unused
	 * @return Whether the key was handled
	 */
	private bool key_press(uint keyval, uint keycode, Gdk.ModifierType state)
	{
		if (!this.popover.visible) {
			return false;
		}
		if (keyval == Gdk.Key.Escape) {
			this.popover.popdown();
			return true;
		}
		var lines = this.history_rows;
		switch (this.pages.visible_child_name) {
			case "search":
				lines = this.search_rows;
				break;

			case "history":
				break;

			default:
				return false;
		}
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

	/**
	 * Apply a chosen file row and close whichever surface is open.
	 *
	 * @param line Row that holds the file, or an empty-state row
	 */
	private void choose(Gtk.ListBoxRow line)
	{
		var file = line.get_data<OLLMfiles.File>("file");
		if (file == null) {
			return;
		}
		var shown = file.path_basename;
		if (this.form != "phone" && this.project.path.length > 0
			&& file.path.has_prefix(this.project.path + "/")) {
			shown = file.path.substring(this.project.path.length + 1);
		}
		this.label.label = shown;
		if (this.form != "phone") {
			this.button.tooltip_text = file.path;
		}
		this.manager.activate_file(file);
		this.popover.popdown();
		this.pull.visible = false;
		this.chosen(file);
		var row = this.get_parent();
		if (row == null) {
			return;
		}
		var next = row.get_next_sibling();
		if (next == null) {
			return;
		}
		next.child_focus(Gtk.DirectionType.TAB_FORWARD);
	}

	/**
	 * Size the file pop-down to the window. Left and right sit inset
	 * from the window edges. Height fills from under this control to
	 * the bottom of the window, so the source view underneath is
	 * covered. The minimum lives on the popover contents, which the
	 * header row does not measure.
	 */
	private void place()
	{
		var root = this.get_root();
		if (root == null) {
			return;
		}
		Graphene.Rect bounds;
		if (!this.compute_bounds(root, out bounds)) {
			return;
		}
		var pad = 12;
		var width = root.get_width() - pad * 2;
		var nudge = 0;
		if (this.popover.get_mapped()) {
			Graphene.Rect pop_bounds;
			if (this.popover.compute_bounds(root, out pop_bounds)) {
				var left_over = pad - (int) pop_bounds.origin.x;
				var right_edge = (int) (pop_bounds.origin.x + pop_bounds.size.width);
				var right_over = right_edge - (root.get_width() - pad);
				if (left_over > 0) {
					nudge = left_over;
					width = width - left_over;
				}
				if (right_over > 0) {
					width = width - right_over;
				}
			}
		}
		if (width < 1) {
			width = 1;
		}
		var point = Gdk.Rectangle();
		point.x = pad - (int) bounds.origin.x + nudge;
		point.y = this.get_height();
		point.width = width;
		point.height = 1;
		this.popover.set_pointing_to(point);
		var anchor = (int) bounds.origin.y + (int) bounds.size.height;
		var room = root.get_height() - anchor - pad;
		if (this.popover.get_mapped() && this.scroll.get_height() > 0) {
			Graphene.Rect pop_bounds;
			if (this.popover.compute_bounds(root, out pop_bounds)) {
				var chrome = (int) pop_bounds.size.height - this.scroll.get_height();
				var gap = (int) pop_bounds.origin.y - anchor;
				if (chrome > 0) {
					room = room - chrome;
				}
				if (gap > 0) {
					room = room - gap;
				}
			}
		}
		if (room < 1) {
			room = 1;
		}
		this.scroll.min_content_width = width;
		this.scroll.max_content_width = width;
		this.scroll.get_parent().width_request = width;
		this.scroll.min_content_height = room;
		this.scroll.max_content_height = room;
	}

	/**
	 * Turn the file button into the search entry and open the pop-down.
	 * History loads immediately. Search waits until the entry has text.
	 */
	private void open_desktop()
	{
		this.opened();
		this.face_stack.visible_child_name = "entry";
		/* After the click, so autohide does not treat it as outside. */
		GLib.Idle.add(() => {
			this.place();
			this.pages.visible_child_name = "history";
			this.entry.text = "";
			this.history_epoch++;
			this.load("", this.history_rows, true, this.history_epoch, "history");
			this.popover.popup();
			this.entry.grab_focus();
			this.entry.set_position(-1);
			this.entry.select_region(-1, -1);
			return false;
		});
	}
}
