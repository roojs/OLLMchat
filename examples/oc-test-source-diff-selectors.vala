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
 * Project and file selector row for the ``oc-test-source-diff --selectors``
 * subtest.
 *
 * Resting controls are flat buttons. Desktop turns a click into a search
 * entry and a pop-down. Phone and tablet open {@link pull} instead.
 * Lists come from a connected {@link OLLMfiles.ProjectManager}.
 *
 * The pull-over is parented by the test window. Phone uses the full width.
 * Tablet uses a start-edge panel. That edge is only so the subtest can be
 * seen; the product has not chosen a side.
 */
class TestSelectorRow : Gtk.Box
{
	public Gtk.Box pull { get; private set; default = new Gtk.Box(Gtk.Orientation.VERTICAL, 0); }
	private OLLMfiles.ProjectManager manager;
	private string form = "desktop";
	private bool has_project = false;
	private OLLMfiles.Folder selected_project;
	private string pull_kind = "project";
	private bool file_from_pull = false;
	private uint file_wait = 0;
	private int file_epoch = 0;
	private Gtk.Button project_button;
	private Gtk.Label project_label;
	private Gtk.Stack project_stack;
	private Gtk.SearchEntry project_entry;
	private Gtk.Popover project_popover;
	private Gtk.Box project_rows;
	private Gtk.Button file_button;
	private Gtk.Label file_label;
	private Gtk.Stack file_stack;
	private Gtk.SearchEntry file_entry;
	private Gtk.Popover file_popover;
	private Gtk.Box file_rows;
	private Gtk.Label pull_title;
	private Gtk.Label pull_current;
	private Gtk.SearchEntry pull_search;
	private Gtk.Box pull_rows;

	/**
	 * Build the selector row.
	 *
	 * @param manager Connected manager whose projects are already loaded
	 * @param form ``desktop``, ``phone``, or ``tablet``
	 */
	public TestSelectorRow(OLLMfiles.ProjectManager manager, string form)
	{
		Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 6);
		this.manager = manager;
		this.form = form;
		this.selected_project = new OLLMfiles.Folder(manager);
		this.margin_start = 6;
		this.margin_end = 6;
		this.margin_top = 4;
		this.margin_bottom = 4;

		this.project_label = new Gtk.Label("Select project") {
			xalign = 0,
		};
		var project_face = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		project_face.append(new Gtk.Image.from_icon_name("system-search-symbolic"));
		project_face.append(this.project_label);
		this.project_button = new Gtk.Button() {
			child = project_face,
			hexpand = false,
		};
		this.project_button.add_css_class("flat");
		this.project_entry = new Gtk.SearchEntry() {
			placeholder_text = "Search projects",
			hexpand = true,
		};
		this.project_stack = new Gtk.Stack() {
			hhomogeneous = false,
			vhomogeneous = true,
		};
		this.project_stack.add_named(this.project_button, "button");
		this.project_stack.add_named(this.project_entry, "entry");
		this.append(this.project_stack);

		this.file_label = new Gtk.Label("Select file") {
			xalign = 0,
			hexpand = true,
		};
		var file_face = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		file_face.append(new Gtk.Image.from_icon_name("system-search-symbolic"));
		file_face.append(this.file_label);
		this.file_button = new Gtk.Button() {
			child = file_face,
			hexpand = true,
		};
		this.file_button.add_css_class("flat");
		this.file_entry = new Gtk.SearchEntry() {
			placeholder_text = "Search files",
			hexpand = true,
		};
		this.file_stack = new Gtk.Stack() {
			hhomogeneous = false,
			vhomogeneous = true,
			hexpand = true,
			visible = false,
		};
		this.file_stack.add_named(this.file_button, "button");
		this.file_stack.add_named(this.file_entry, "entry");
		this.append(this.file_stack);

		var history = new Gtk.Button.from_icon_name("task-due") {
			tooltip_text = "History",
			hexpand = false,
		};
		history.add_css_class("flat");
		this.append(history);

		if (this.form == "phone") {
			this.project_label.max_width_chars = 18;
			this.project_label.ellipsize = Pango.EllipsizeMode.END;
			this.file_label.ellipsize = Pango.EllipsizeMode.END;
		}
		if (this.form != "phone") {
			this.file_label.ellipsize = Pango.EllipsizeMode.START;
		}

		this.project_rows = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		var project_scroll = new Gtk.ScrolledWindow() {
			child = this.project_rows,
			min_content_width = 280,
			min_content_height = 200,
			max_content_height = 360,
			propagate_natural_height = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
		};
		this.project_popover = new Gtk.Popover() {
			has_arrow = false,
			position = Gtk.PositionType.BOTTOM,
			child = project_scroll,
		};
		this.project_popover.set_parent(this.project_stack);
		this.project_popover.closed.connect(() => {
			this.project_stack.visible_child_name = "button";
		});

		this.file_rows = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		var file_scroll = new Gtk.ScrolledWindow() {
			child = this.file_rows,
			min_content_width = 520,
			min_content_height = 240,
			max_content_height = 420,
			propagate_natural_height = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
		};
		this.file_popover = new Gtk.Popover() {
			has_arrow = false,
			position = Gtk.PositionType.BOTTOM,
			child = file_scroll,
		};
		this.file_popover.set_parent(this.file_stack);
		this.file_popover.closed.connect(() => {
			this.file_stack.visible_child_name = "button";
		});

		this.pull.add_css_class("test-selector-pull");
		this.pull.vexpand = true;
		var pull_css = new Gtk.CssProvider();
		pull_css.load_from_string(".test-selector-pull { background-color: @window_bg_color; }");
		Gtk.StyleContext.add_provider_for_display(
			Gdk.Display.get_default(), pull_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
		if (this.form == "phone") {
			this.pull.hexpand = true;
		}
		if (this.form == "tablet") {
			this.pull.halign = Gtk.Align.START;
			this.pull.width_request = 420;
		}
		var pull_top = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
			margin_start = 6,
			margin_end = 6,
			margin_top = 6,
		};
		var back = new Gtk.Button.from_icon_name("go-previous-symbolic");
		back.add_css_class("flat");
		this.pull_title = new Gtk.Label("") {
			hexpand = true,
			xalign = 0,
		};
		pull_top.append(back);
		pull_top.append(this.pull_title);
		this.pull_current = new Gtk.Label("Select project") {
			xalign = 0,
			ellipsize = Pango.EllipsizeMode.START,
			margin_start = 12,
			margin_end = 12,
			margin_top = 6,
			margin_bottom = 6,
		};
		this.pull_rows = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		var pull_scroll = new Gtk.ScrolledWindow() {
			child = this.pull_rows,
			vexpand = true,
			hexpand = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
		};
		this.pull_search = new Gtk.SearchEntry() {
			placeholder_text = "Search",
			hexpand = true,
			margin_start = 8,
			margin_end = 8,
			margin_bottom = 8,
		};
		this.pull.append(pull_top);
		this.pull.append(this.pull_current);
		this.pull.append(pull_scroll);
		this.pull.append(this.pull_search);
		this.pull.visible = false;
		back.clicked.connect(() => {
			this.pull.visible = false;
		});

		this.project_entry.search_changed.connect(() => {
			this.fill_projects(this.project_rows, this.project_entry.text, false);
		});
		this.pull_search.search_changed.connect(() => {
			if (this.pull_kind != "file") {
				this.fill_projects(this.pull_rows, this.pull_search.text, true);
				return;
			}
			this.queue_files(true);
		});
		this.file_entry.search_changed.connect(() => {
			this.queue_files(false);
		});

		this.project_button.clicked.connect(() => {
			if (this.form != "desktop") {
				this.pull_kind = "project";
				this.pull_title.label = "Projects";
				this.pull_current.label = "Select project";
				if (this.has_project) {
					this.pull_current.label = this.selected_project.path;
				}
				this.pull.visible = true;
				this.pull_search.placeholder_text = "Search projects";
				this.pull_search.text = " ";
				this.pull_search.text = "";
				return;
			}
			this.file_popover.popdown();
			this.project_stack.visible_child_name = "entry";
			this.project_entry.grab_focus();
			this.project_popover.popup();
			this.project_entry.text = " ";
			this.project_entry.text = "";
		});
		this.file_button.clicked.connect(() => {
			if (this.form != "desktop") {
				this.pull_kind = "file";
				this.pull_title.label = "Files";
				this.pull_current.label = this.file_label.label;
				if (this.form != "phone" && this.file_button.tooltip_text != "") {
					this.pull_current.label = this.file_button.tooltip_text;
				}
				this.pull.visible = true;
				this.pull_search.placeholder_text = "Search files";
				this.pull_search.text = " ";
				this.pull_search.text = "";
				return;
			}
			this.project_popover.popdown();
			this.file_stack.visible_child_name = "entry";
			this.file_entry.grab_focus();
			this.file_popover.popup();
			this.file_entry.text = " ";
			this.file_entry.text = "";
		});
	}

	/**
	 * Rebuild a project list from the manager.
	 *
	 * @param rows Box that receives one button per match
	 * @param query Case-insensitive substring, or empty for every project
	 * @param from_pull Choosing a row closes the pull-over instead of the pop-down
	 */
	private void fill_projects(Gtk.Box rows, string query, bool from_pull)
	{
		while (rows.get_first_child() != null) {
			rows.remove(rows.get_first_child());
		}
		var needle = query.down().strip();
		var found = false;
		for (var i = 0; i < this.manager.projects.get_n_items(); i++) {
			var folder = this.manager.projects.get_item(i) as OLLMfiles.Folder;
			if (folder == null) {
				continue;
			}
			if (needle != "" && !folder.path_basename.down().contains(needle)
				&& !folder.path.down().contains(needle)) {
				continue;
			}
			found = true;
			var pick = new Gtk.Button.with_label(folder.path_basename) {
				hexpand = true,
				has_frame = false,
			};
			pick.clicked.connect(() => {
				this.selected_project = folder;
				this.has_project = true;
				this.project_label.label = folder.path_basename;
				if (this.form != "phone") {
					this.project_button.tooltip_text = folder.path;
				}
				this.file_stack.visible = true;
				this.file_label.label = "Select file";
				this.file_button.tooltip_text = "";
				this.manager.activate_project(folder);
				if (from_pull) {
					this.pull.visible = false;
					return;
				}
				this.project_popover.popdown();
				this.file_stack.visible_child_name = "entry";
				this.file_entry.grab_focus();
				this.file_popover.popup();
				this.file_entry.text = " ";
				this.file_entry.text = "";
			});
			rows.append(pick);
		}
		if (found) {
			return;
		}
		rows.append(new Gtk.Label("No projects") {
			xalign = 0,
			margin_start = 8,
			margin_top = 8,
			margin_bottom = 8,
		});
	}

	/**
	 * Debounce a file-page fetch into the pop-down or the pull-over.
	 *
	 * @param from_pull Fill {@link pull_rows} instead of the file pop-down
	 */
	private void queue_files(bool from_pull)
	{
		this.file_from_pull = from_pull;
		if (this.file_wait != 0) {
			GLib.Source.remove(this.file_wait);
		}
		this.file_wait = GLib.Timeout.add(200, () => {
			this.file_wait = 0;
			if (!this.has_project) {
				return false;
			}
			this.file_epoch++;
			var epoch = this.file_epoch;
			var query = this.file_entry.text.strip();
			if (this.file_from_pull) {
				query = this.pull_search.text.strip();
			}
			var from_pull_now = this.file_from_pull;
			this.selected_project.fetch_files.begin(0, 50, query, {}, false, (obj, res) => {
				if (epoch != this.file_epoch) {
					return;
				}
				try {
					var response = this.selected_project.fetch_files.end(res);
					var rows = this.file_rows;
					if (from_pull_now) {
						rows = this.pull_rows;
					}
					while (rows.get_first_child() != null) {
						rows.remove(rows.get_first_child());
					}
					if (response.retval.type() == GLib.Type.INVALID) {
						rows.append(new Gtk.Label("No files") {
							xalign = 0,
							margin_start = 8,
							margin_top = 8,
							margin_bottom = 8,
						});
						return;
					}
					var files = (Gee.ArrayList<OLLMfiles.File>) response.retval.get_object();
					if (files.size == 0) {
						rows.append(new Gtk.Label("No files") {
							xalign = 0,
							margin_start = 8,
							margin_top = 8,
							margin_bottom = 8,
						});
						return;
					}
					foreach (var file in files) {
						var shown = file.path_basename;
						if (this.form != "phone" && this.selected_project.path.length > 0
							&& file.path.has_prefix(this.selected_project.path + "/")) {
							shown = file.path.substring(this.selected_project.path.length + 1);
						}
						var pick_label = new Gtk.Label(shown) {
							xalign = 0,
							hexpand = true,
						};
						if (this.form == "phone") {
							pick_label.ellipsize = Pango.EllipsizeMode.END;
						}
						if (this.form != "phone") {
							pick_label.ellipsize = Pango.EllipsizeMode.START;
						}
						var pick = new Gtk.Button() {
							child = pick_label,
							hexpand = true,
							has_frame = false,
						};
						pick.clicked.connect(() => {
							var label = file.path_basename;
							if (this.form != "phone" && this.selected_project.path.length > 0
								&& file.path.has_prefix(this.selected_project.path + "/")) {
								label = file.path.substring(this.selected_project.path.length + 1);
							}
							this.file_label.label = label;
							if (this.form != "phone") {
								this.file_button.tooltip_text = file.path;
							}
							this.manager.activate_file(file);
							if (from_pull_now) {
								this.pull.visible = false;
								return;
							}
							this.file_popover.popdown();
						});
						rows.append(pick);
					}
				} catch (GLib.Error e) {
					GLib.warning("file list failed: %s", e.message);
				}
			});
			return false;
		});
	}
}
