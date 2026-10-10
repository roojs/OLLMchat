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
 * Project selector. Replaces {@link OLLMcoder.ProjectDropdown}.
 *
 * Resting state is a flat button. A desktop click turns it into a
 * search entry and opens a left-aligned pop-down. Recent is the
 * default. A project is recent when a file under it has been viewed.
 * That time is the newest file ''last_viewed'', not the project row.
 * All lists every name. Phone and tablet open {@link SelectorPull}.
 *
 * == Example ==
 *
 * {{{
 * var projects = new ProjectSelector(manager, "desktop", pull);
 * row.append(projects);
 * }}}
 */
class ProjectSelector : Gtk.Box
{
	/**
	 * Emitted when the desktop pop-down is about to open.
	 *
	 * The host closes the file pop-down from this.
	 */
	public signal void opened();

	/**
	 * Emitted after a project row is chosen.
	 *
	 * Desktop uses this to focus the file selector. Phone and tablet
	 * leave the file pull-over closed.
	 *
	 * @param folder Project that was chosen
	 */
	public signal void chosen(OLLMfiles.Folder folder);

	/**
	 * Desktop project pop-down. The host closes it when files open.
	 */
	public Gtk.Popover popover { get; private set; }

	private OLLMfiles.ProjectManager manager;
	private string form = "desktop";
	private SelectorPull pull;
	private Gtk.Label label;
	private Gtk.Button button;
	private Gtk.Stack stack;
	private Gtk.SearchEntry entry;
	private Gtk.ScrolledWindow scroll;
	private Gtk.ListBox rows;
	private Gtk.ListBox pull_rows;
	private bool project_recent { get; set; default = true; }

	/**
	 * Build the project button, pop-down, and pull-over page.
	 *
	 * @param manager Connected manager whose projects are already loaded
	 * @param form ''desktop'', ''phone'', or ''tablet''
	 * @param pull Shared phone and tablet surface. Desktop still builds
	 *        its page so the same lists exist.
	 */
	public ProjectSelector(OLLMfiles.ProjectManager manager, string form, SelectorPull pull)
	{
		Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
		this.manager = manager;
		this.form = form;
		this.pull = pull;
		this.hexpand = false;
		this.valign = Gtk.Align.START;
		this.label = new Gtk.Label("Select project") {
			xalign = 0,
			halign = Gtk.Align.START,
		};
		switch (this.form) {
		case "phone":
			this.label.max_width_chars = 18;
			this.label.ellipsize = Pango.EllipsizeMode.END;
			break;

		default:
			break;
		}
		var face = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		face.append(new Gtk.Image.from_icon_name("system-search-symbolic"));
		face.append(this.label);
		this.button = new Gtk.Button() {
			child = face,
			hexpand = false,
			valign = Gtk.Align.CENTER,
		};
		this.button.add_css_class("flat");
		this.entry = new Gtk.SearchEntry() {
			placeholder_text = "Search projects",
			hexpand = true,
		};
		this.stack = new Gtk.Stack() {
			hhomogeneous = false,
			vhomogeneous = true,
		};
		this.stack.add_named(this.button, "button");
		this.stack.add_named(this.entry, "entry");
		this.append(this.stack);

		this.rows = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.NONE,
			activate_on_single_click = true,
			can_focus = false,
		};
		this.scroll = new Gtk.ScrolledWindow() {
			child = this.rows,
			min_content_width = 280,
			max_content_width = 280,
			min_content_height = 200,
			propagate_natural_height = true,
			propagate_natural_width = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
			can_focus = false,
		};
		var project_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
			homogeneous = true,
			can_focus = false,
			margin_start = 6,
			margin_end = 6,
			margin_top = 6,
			margin_bottom = 6,
		};
		project_bar.add_css_class("linked");
		var project_recent_toggle = new Gtk.ToggleButton.with_label("Recent");
		var project_all_toggle = new Gtk.ToggleButton.with_label("All");
		project_all_toggle.set_group(project_recent_toggle);
		project_recent_toggle.active = true;
		project_bar.append(project_recent_toggle);
		project_bar.append(project_all_toggle);
		var project_popup = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			can_focus = false,
		};
		project_popup.append(project_bar);
		project_popup.append(this.scroll);
		this.popover = new Gtk.Popover() {
			has_arrow = false,
			position = Gtk.PositionType.BOTTOM,
			halign = Gtk.Align.START,
			autohide = false,
			can_focus = false,
			child = project_popup,
		};
		this.popover.set_parent(this);
		this.realize.connect(() => {
			var window = this.get_root() as Gtk.Window;
			if (window == null) {
				return;
			}
			window.notify["is-active"].connect(() => {
				if (window.is_active || !this.popover.visible) {
					return;
				}
				this.popover.popdown();
			});
		});
		this.popover.closed.connect(() => {
			this.stack.visible_child_name = "button";
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
		var pull_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
			homogeneous = true,
			can_focus = false,
			margin_start = 6,
			margin_end = 6,
			margin_bottom = 6,
		};
		pull_bar.add_css_class("linked");
		var pull_recent_toggle = new Gtk.ToggleButton.with_label("Recent");
		var pull_all_toggle = new Gtk.ToggleButton.with_label("All");
		pull_all_toggle.set_group(pull_recent_toggle);
		pull_recent_toggle.active = true;
		pull_bar.append(pull_recent_toggle);
		pull_bar.append(pull_all_toggle);
		var pull_page = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			hexpand = true,
			vexpand = true,
		};
		pull_page.append(pull_bar);
		pull_page.append(pull_scroll);
		this.pull.pages.add_named(pull_page, "project");

		var desktop_filter = new Gtk.CustomFilter((item) => {
			var folder = item as OLLMfiles.Folder;
			if (folder == null) {
				return false;
			}
			if (this.project_recent && folder.last_viewed == 0) {
				return false;
			}
			var needle = this.entry.text.down().strip();
			if (needle == "") {
				return true;
			}
			if (folder.path_basename.down().contains(needle)) {
				return true;
			}
			return folder.path.down().contains(needle);
		});
		var pull_filter = new Gtk.CustomFilter((item) => {
			var folder = item as OLLMfiles.Folder;
			if (folder == null) {
				return false;
			}
			if (this.project_recent && folder.last_viewed == 0) {
				return false;
			}
			var needle = this.pull.search.text.down().strip();
			if (needle == "") {
				return true;
			}
			if (folder.path_basename.down().contains(needle)) {
				return true;
			}
			return folder.path.down().contains(needle);
		});
		var name_sorter = new Gtk.StringSorter(
			new Gtk.PropertyExpression(typeof(OLLMfiles.Folder), null, "path_basename")
		) {
			ignore_case = true,
		};
		var project_sorter = new Gtk.CustomSorter((a, b) => {
			var folder_a = a as OLLMfiles.Folder;
			var folder_b = b as OLLMfiles.Folder;
			if (folder_a == null || folder_b == null) {
				return Gtk.Ordering.EQUAL;
			}
			if (this.project_recent && folder_a.last_viewed != folder_b.last_viewed) {
				return folder_a.last_viewed > folder_b.last_viewed ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
			}
			var order = GLib.strcmp(folder_a.path_basename.down(), folder_b.path_basename.down());
			if (order == 0) {
				return Gtk.Ordering.EQUAL;
			}
			return order < 0 ? Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
		});
		var desktop_sorted = new Gtk.SortListModel(
			new Gtk.FilterListModel(this.manager.projects, desktop_filter),
			project_sorter
		);
		var pull_sorted = new Gtk.SortListModel(
			new Gtk.FilterListModel(this.manager.projects, pull_filter),
			project_sorter
		);
		this.rows.bind_model(desktop_sorted, (item) => {
			var folder = item as OLLMfiles.Folder;
			var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 8,
			};
			var title = new Gtk.Label(folder.path_basename) {
				xalign = 0,
				halign = Gtk.Align.START,
				hexpand = true,
				ellipsize = Pango.EllipsizeMode.END,
				css_classes = { "body", "list-chat-title" },
			};
			var caption = new Gtk.Label(folder.path) {
				xalign = 0,
				halign = Gtk.Align.START,
				hexpand = true,
				ellipsize = Pango.EllipsizeMode.START,
				css_classes = { "caption", "dim-label" },
			};
			column.append(title);
			column.append(caption);
			column.set_data<OLLMfiles.Folder>("folder", folder);
			return column;
		});
		this.pull_rows.bind_model(pull_sorted, (item) => {
			var folder = item as OLLMfiles.Folder;
			var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 8,
			};
			var title = new Gtk.Label(folder.path_basename) {
				xalign = 0,
				halign = Gtk.Align.START,
				hexpand = true,
				ellipsize = Pango.EllipsizeMode.END,
				css_classes = { "body", "list-chat-title" },
			};
			var caption = new Gtk.Label(folder.path) {
				xalign = 0,
				halign = Gtk.Align.START,
				hexpand = true,
				ellipsize = Pango.EllipsizeMode.START,
				css_classes = { "caption", "dim-label" },
			};
			column.append(title);
			column.append(caption);
			column.set_data<OLLMfiles.Folder>("folder", folder);
			return column;
		});
		var desktop_empty = new Gtk.Label("No recent projects") {
			xalign = 0,
			halign = Gtk.Align.START,
			margin_start = 12,
			margin_top = 8,
			margin_bottom = 8,
		};
		desktop_empty.add_css_class("dim-label");
		this.rows.set_placeholder(desktop_empty);
		var pull_empty = new Gtk.Label("No recent projects") {
			xalign = 0,
			halign = Gtk.Align.START,
			margin_start = 12,
			margin_top = 8,
			margin_bottom = 8,
		};
		pull_empty.add_css_class("dim-label");
		this.pull_rows.set_placeholder(pull_empty);

		var filter_sync = false;
		project_recent_toggle.clicked.connect(() => {
			GLib.debug("recent clicked active=%s", project_recent_toggle.active.to_string());
		});
		project_all_toggle.clicked.connect(() => {
			GLib.debug("all clicked active=%s", project_all_toggle.active.to_string());
		});
		project_recent_toggle.notify["active"].connect(() => {
			GLib.debug("recent notify active=%s sync=%s", project_recent_toggle.active.to_string(), filter_sync.to_string());
			if (filter_sync) {
				return;
			}
			filter_sync = true;
			this.project_recent = project_recent_toggle.active;
			pull_recent_toggle.active = this.project_recent;
			pull_all_toggle.active = !this.project_recent;
			filter_sync = false;
			this.entry.grab_focus();
		});
		project_all_toggle.toggled.connect(() => {
			GLib.debug("all toggled active=%s sync=%s", project_all_toggle.active.to_string(), filter_sync.to_string());
			if (filter_sync || !project_all_toggle.active) {
				return;
			}
			filter_sync = true;
			project_recent_toggle.active = false;
			pull_recent_toggle.active = false;
			pull_all_toggle.active = true;
			filter_sync = false;
			this.project_recent = false;
			this.entry.grab_focus();
		});
		pull_recent_toggle.clicked.connect(() => {
			GLib.debug("pull recent clicked active=%s", pull_recent_toggle.active.to_string());
		});
		pull_all_toggle.clicked.connect(() => {
			GLib.debug("pull all clicked active=%s", pull_all_toggle.active.to_string());
		});
		pull_recent_toggle.notify["active"].connect(() => {
			GLib.debug("pull recent notify active=%s sync=%s", pull_recent_toggle.active.to_string(), filter_sync.to_string());
			if (filter_sync) {
				return;
			}
			filter_sync = true;
			this.project_recent = pull_recent_toggle.active;
			project_recent_toggle.active = this.project_recent;
			project_all_toggle.active = !this.project_recent;
			filter_sync = false;
		});
		pull_all_toggle.toggled.connect(() => {
			GLib.debug("pull all toggled active=%s sync=%s", pull_all_toggle.active.to_string(), filter_sync.to_string());
			if (filter_sync || !pull_all_toggle.active) {
				return;
			}
			filter_sync = true;
			pull_recent_toggle.active = false;
			project_recent_toggle.active = false;
			project_all_toggle.active = true;
			filter_sync = false;
			this.project_recent = false;
		});
		this.notify["project-recent"].connect(() => {
			if (!this.project_recent) {
				desktop_sorted.sorter = name_sorter;
				pull_sorted.sorter = name_sorter;
			}
			if (this.project_recent) {
				desktop_sorted.sorter = project_sorter;
				pull_sorted.sorter = project_sorter;
			}
			desktop_filter.changed(Gtk.FilterChange.DIFFERENT);
			pull_filter.changed(Gtk.FilterChange.DIFFERENT);
			var viewed = 0;
			var total = this.manager.projects.get_n_items();
			var index = (uint) 0;
			while (index < total) {
				var folder = this.manager.projects.get_item(index) as OLLMfiles.Folder;
				if (folder != null && folder.last_viewed > 0) {
					viewed++;
				}
				index++;
			}
			GLib.debug("recent=%s viewed=%d total=%u shown=%u",
				this.project_recent.to_string(), viewed, total, desktop_sorted.get_n_items());
			desktop_empty.label = "No projects";
			if (this.project_recent && this.entry.text.strip() == "") {
				desktop_empty.label = "No recent projects";
			}
			pull_empty.label = "No projects";
			if (this.project_recent && this.pull.search.text.strip() == "") {
				pull_empty.label = "No recent projects";
			}
			GLib.Idle.add(() => {
				var child = this.rows.get_first_child();
				while (child != null) {
					child.remove_css_class("selector-mark");
					child = child.get_next_sibling();
				}
				var first = this.rows.get_row_at_index(0);
				if (first != null && first.activatable) {
					first.add_css_class("selector-mark");
				}
				return false;
			});
		});
		this.rows.row_activated.connect((line) => {
			this.choose(line);
		});
		this.pull_rows.row_activated.connect((line) => {
			this.choose(line);
		});
		this.entry.search_changed.connect(() => {
			desktop_filter.changed(Gtk.FilterChange.DIFFERENT);
			desktop_empty.label = "No projects";
			if (this.project_recent && this.entry.text.strip() == "") {
				desktop_empty.label = "No recent projects";
			}
			GLib.Idle.add(() => {
				var child = this.rows.get_first_child();
				while (child != null) {
					child.remove_css_class("selector-mark");
					child = child.get_next_sibling();
				}
				var first = this.rows.get_row_at_index(0);
				if (first != null && first.activatable) {
					first.add_css_class("selector-mark");
				}
				return false;
			});
		});
		this.pull.search.search_changed.connect(() => {
			if (this.pull.kind != "project") {
				return;
			}
			pull_filter.changed(Gtk.FilterChange.DIFFERENT);
			pull_empty.label = "No projects";
			if (this.project_recent && this.pull.search.text.strip() == "") {
				pull_empty.label = "No recent projects";
			}
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
			/* Focus is cleared before this runs. All's click then
			   puts it on the entry's text child, not the entry. */
			GLib.Idle.add(() => {
				if (!this.popover.visible) {
					return false;
				}
				var root = this.get_root();
				if (root == null) {
					this.popover.popdown();
					return false;
				}
				var focused = root.get_focus() as Gtk.Widget;
				var focus_name = "none";
				if (focused != null) {
					focus_name = focused.get_type().name();
				}
				var stay = focused == this.entry || (focused != null && focused.is_ancestor(this.entry));
				if (focused != null && (focused == this.popover || focused.is_ancestor(this.popover))) {
					stay = true;
				}
				GLib.debug("focus leave widget=%s stay=%s", focus_name, stay.to_string());
				if (stay) {
					return false;
				}
				this.popover.popdown();
				return false;
			});
		});
		this.entry.add_controller(focus);
		this.button.clicked.connect(() => {
			switch (this.form) {
			case "phone":
			case "tablet":
				this.pull.kind = "project";
				this.pull.heading.label = "Projects";
				this.pull.current.label = this.label.label;
				if (this.form != "phone" && this.button.tooltip_text != "") {
					this.pull.current.label = this.button.tooltip_text;
				}
				this.pull.pages.visible_child_name = "project";
				this.pull.search.placeholder_text = "Search projects";
				this.pull.visible = true;
				this.pull.search.text = "";
				return;
			default:
				break;
			}
			this.opened();
			this.stack.visible_child_name = "entry";
			/* After the click, so autohide does not treat it as outside. */
			GLib.Idle.add(() => {
				this.place();
				this.entry.text = "";
				this.popover.popup();
				this.entry.grab_focus();
				this.entry.set_position(-1);
				this.entry.select_region(-1, -1);
				var child = this.rows.get_first_child();
				while (child != null) {
					child.remove_css_class("selector-mark");
					child = child.get_next_sibling();
				}
				var first = this.rows.get_row_at_index(0);
				if (first != null && first.activatable) {
					first.add_css_class("selector-mark");
				}
				return false;
			});
		});
	}

	/**
	 * Keyboard for the open pop-down. Escape closes it. Enter
	 * and Tab activate the marked row, and choosing a project
	 * moves to the file control. Up and Down move that mark.
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
		switch (keyval) {
			case Gdk.Key.Escape:
				this.popover.popdown();
				return true;
			case Gdk.Key.Return:
			case Gdk.Key.KP_Enter:
			case Gdk.Key.ISO_Enter:
			case Gdk.Key.Tab:
			case Gdk.Key.KP_Tab:
			case Gdk.Key.ISO_Left_Tab:
				var chosen = this.rows.get_first_child();
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
				var child = this.rows.get_first_child();
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
				var target = this.rows.get_row_at_index(next_index);
				if (target == null || !target.activatable) {
					return true;
				}
				child = this.rows.get_first_child();
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
	 * Apply a chosen project row and close whichever surface is open.
	 *
	 * @param line Row that holds the folder, or an empty-state row
	 */
	private void choose(Gtk.ListBoxRow line)
	{
		var folder = line.get_child().get_data<OLLMfiles.Folder>("folder");
		if (folder == null) {
			return;
		}
		this.label.label = folder.path_basename;
		if (this.form != "phone") {
			this.button.tooltip_text = folder.path;
		}
		this.manager.activate_project(folder);
		this.popover.popdown();
		this.pull.visible = false;
		this.chosen(folder);
	}

	/**
	 * Left-align the pop-down under the button and stretch it to the
	 * space the window still has below the row. Popover padding and
	 * the gap under the button are taken off that space, so the
	 * pop-down stays inside the window.
	 */
	private void place()
	{
		var point = Gdk.Rectangle();
		point.x = 0;
		point.y = this.get_height();
		point.width = 280;
		point.height = 1;
		this.popover.set_pointing_to(point);
		var root = this.get_root();
		if (root == null) {
			return;
		}
		Graphene.Rect bounds;
		if (!this.compute_bounds(root, out bounds)) {
			return;
		}
		var anchor = (int) bounds.origin.y + (int) bounds.size.height;
		var room = root.get_height() - anchor - 8;
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
		this.scroll.min_content_height = room;
		this.scroll.max_content_height = room;
	}
}
