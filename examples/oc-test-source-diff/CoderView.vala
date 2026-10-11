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
 * Coder screen: header, editor, and the search bar along the bottom.
 *
 * The header is {@link ProjectSelector}, {@link FileSelector}, and
 * the editor save button.
 * The editor is {@link SourceView}. Project selection and search
 * stay here. A chosen file is opened on the editor.
 * {@link SourceView.file_changed} updates the file button.
 * {@link SourceView.find} and {@link SourceView.find_again} drive
 * this search bar.
 *
 * == Example ==
 *
 * {{{
 * var coder = new CoderView(manager, "desktop");
 * window.child = coder;
 * }}}
 */
class CoderView : Gtk.Box
{
	/**
	 * Phone and tablet pull-over. Desktop still builds one; the
	 * host overlays it only when the form is not desktop.
	 */
	public SelectorPull pull { get; private set; }

	/**
	 * Header project button and pop-down.
	 */
	public ProjectSelector projects { get; private set; }

	/**
	 * Header file button and folder tree.
	 */
	public FileSelector files { get; private set; }

	private SourceView editor;
	private Gtk.SearchEntry search_entry;
	private Gtk.Label search_results_label;
	private Gtk.Button search_next_button;
	private Gtk.Button search_back_button;
	private GtkSource.SearchContext? search_context = null;
	private int last_search_end = 0;
	private Gtk.CheckButton case_sensitive_checkbox;
	private Gtk.CheckButton regex_checkbox;
	private Gtk.CheckButton multiline_checkbox;

	/**
	 * Build the header, the editor, and the search bar.
	 *
	 * @param manager Connected manager whose projects are already loaded
	 * @param form ''desktop'', ''phone'', or ''tablet''
	 */
	public CoderView(OLLMfiles.ProjectManager manager, string form)
	{
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
		manager.buffer_provider = new OLLMcoder.BufferProvider();
		this.pull = new SelectorPull(form);
		this.projects = new ProjectSelector(manager, form, this.pull);
		this.files = new FileSelector(manager, form, this.pull);
		this.editor = new SourceView(manager) {
			hexpand = true,
			vexpand = true,
		};
		var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
			valign = Gtk.Align.START,
			margin_start = 6,
			margin_end = 6,
			margin_top = 4,
			margin_bottom = 4,
		};
		var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
			hexpand = true,
		};
		header.append(this.projects);
		header.append(spacer);
		header.append(this.files);
		this.editor.save_button.add_css_class("flat");
		this.editor.save_button.valign = Gtk.Align.CENTER;
		header.append(this.editor.save_button);
		this.files.notify["visible"].connect(() => {
			spacer.visible = !this.files.visible;
		});
		var history = new Gtk.Button.from_icon_name("task-due") {
			tooltip_text = "History",
			hexpand = false,
			valign = Gtk.Align.CENTER,
			sensitive = false,
		};
		history.add_css_class("flat");
		header.append(history);
		this.projects.opened.connect(() => {
			this.files.popover.popdown();
		});
		this.files.opened.connect(() => {
			this.projects.popover.popdown();
		});
		this.projects.chosen.connect((folder) => {
			this.files.project = folder;
		});
		var search_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5) {
			margin_start = 5,
			margin_end = 5,
			margin_top = 5,
			margin_bottom = 5,
			vexpand = false,
			visible = false,
		};
		this.search_entry = new Gtk.SearchEntry() {
			hexpand = true,
			placeholder_text = "Search...",
			search_delay = 300,
		};
		this.search_entry.search_changed.connect(() => {
			this.perform_search(this.search_entry.text);
		});
		var search_keys = new Gtk.EventControllerKey();
		search_keys.key_pressed.connect((keyval, keycode, state) => {
			if (keyval == Gdk.Key.Return && this.search_entry.text.length > 0) {
				this.forward_search();
				return true;
			}
			if (keyval == Gdk.Key.g && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
				this.forward_search();
				return true;
			}
			return false;
		});
		this.search_entry.add_controller(search_keys);
		this.search_results_label = new Gtk.Label("No Results") {
			margin_start = 4,
			margin_end = 4,
		};
		this.search_next_button = new Gtk.Button.from_icon_name("go-down") {
			tooltip_text = "Next match",
			sensitive = false,
		};
		this.search_next_button.clicked.connect(() => {
			this.forward_search();
		});
		this.search_back_button = new Gtk.Button.from_icon_name("go-up") {
			tooltip_text = "Previous match",
			sensitive = false,
		};
		this.search_back_button.clicked.connect(() => {
			this.backward_search();
		});
		var settings_menu_button = new Gtk.MenuButton() {
			icon_name = "emblem-system",
			tooltip_text = "Search settings",
			always_show_arrow = true,
		};
		var settings_popover = new Gtk.Popover();
		var settings_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5) {
			margin_start = 10,
			margin_end = 10,
			margin_top = 10,
			margin_bottom = 10,
		};
		this.case_sensitive_checkbox = new Gtk.CheckButton.with_label("Case Sensitive");
		this.case_sensitive_checkbox.toggled.connect(() => {
			this.perform_search(this.search_entry.text);
		});
		this.regex_checkbox = new Gtk.CheckButton.with_label("Regex");
		this.regex_checkbox.toggled.connect(() => {
			this.perform_search(this.search_entry.text);
		});
		this.multiline_checkbox = new Gtk.CheckButton.with_label("Multi-line (add \\n)");
		this.multiline_checkbox.toggled.connect(() => {
			this.perform_search(this.search_entry.text);
		});
		settings_box.append(this.case_sensitive_checkbox);
		settings_box.append(this.regex_checkbox);
		settings_box.append(this.multiline_checkbox);
		settings_popover.set_child(settings_box);
		settings_menu_button.popover = settings_popover;
		search_bar.append(this.search_entry);
		search_bar.append(this.search_results_label);
		search_bar.append(this.search_next_button);
		search_bar.append(this.search_back_button);
		search_bar.append(settings_menu_button);
		this.append(header);
		this.append(this.editor);
		this.append(search_bar);
		this.files.chosen.connect((file) => {
			this.editor.open_file.begin(file);
		});
		this.editor.file_changed.connect((file) => {
			var shown = file.path_basename;
			if (this.files.form != "phone" && this.files.project.path.length > 0
				&& file.path.has_prefix(this.files.project.path + "/")) {
				shown = file.path.substring(this.files.project.path.length + 1);
			}
			this.files.label.label = shown;
			this.search_context = null;
			this.last_search_end = 0;
			this.search_entry.text = "";
			this.update_search_results();
			search_bar.visible = true;
		});
		this.editor.find.connect(() => {
			this.search_entry.grab_focus();
			this.search_entry.select_region(0, -1);
		});
		this.editor.find_again.connect((back) => {
			if (back) {
				this.backward_search();
				return;
			}
			this.forward_search();
		});
	}

	/**
	 * Highlight matches for the current query.
	 *
	 * @param search_text Text from the search entry
	 */
	private void perform_search(string search_text)
	{
		if (this.editor.current_buffer == null) {
			this.search_context = null;
			this.update_search_results();
			return;
		}
		var search_settings = new GtkSource.SearchSettings();
		search_settings.case_sensitive = this.case_sensitive_checkbox.active;
		search_settings.regex_enabled = this.regex_checkbox.active;
		search_settings.wrap_around = false;
		this.search_context = new GtkSource.SearchContext(this.editor.current_buffer, search_settings);
		this.search_context.set_highlight(true);
		var txt = search_text;
		if (this.multiline_checkbox.active) {
			txt = search_text.replace("\\n", "\n");
		}
		search_settings.set_search_text(txt);
		this.last_search_end = 0;
		this.update_search_results();
	}

	/**
	 * Show the match count and enable the next and previous buttons.
	 */
	private void update_search_results()
	{
		if (this.search_context == null) {
			this.search_results_label.label = "No Results";
			this.search_next_button.sensitive = false;
			this.search_back_button.sensitive = false;
			return;
		}
		var count = this.search_context.get_occurrences_count();
		if (count < 0) {
			this.search_results_label.label = "??? Matches";
			this.search_next_button.sensitive = false;
			this.search_back_button.sensitive = false;
			return;
		}
		if (count > 0) {
			this.search_results_label.label = "%d Matches".printf(count);
			this.search_next_button.sensitive = true;
			this.search_back_button.sensitive = true;
			return;
		}
		this.search_results_label.label = "No Matches";
		this.search_next_button.sensitive = false;
		this.search_back_button.sensitive = false;
	}

	/**
	 * Select the next match and scroll it into view.
	 */
	private void forward_search()
	{
		if (this.editor.current_buffer == null || this.search_context == null) {
			return;
		}
		Gtk.TextIter beg, st, en;
		var has_wrapped_around = false;
		this.editor.current_buffer.get_iter_at_offset(out beg, this.last_search_end);
		if (!this.search_context.forward(beg, out st, out en, out has_wrapped_around)) {
			this.last_search_end = 0;
			return;
		}
		if (has_wrapped_around) {
			return;
		}
		this.last_search_end = en.get_offset();
		this.editor.source_view.grab_focus();
		this.editor.current_buffer.place_cursor(st);
		this.editor.source_view.scroll_to_iter(st, 0.1, true, 0.0, 0.5);
	}

	/**
	 * Select the previous match and scroll it into view.
	 */
	private void backward_search()
	{
		if (this.editor.current_buffer == null || this.search_context == null) {
			return;
		}
		Gtk.TextIter beg, st, en;
		var has_wrapped_around = false;
		this.editor.current_buffer.get_iter_at_offset(out beg, this.last_search_end - 1);
		if (!this.search_context.backward(beg, out st, out en, out has_wrapped_around)) {
			Gtk.TextIter end_iter;
			this.editor.current_buffer.get_end_iter(out end_iter);
			this.last_search_end = end_iter.get_offset();
			return;
		}
		this.last_search_end = en.get_offset();
		this.editor.source_view.grab_focus();
		this.editor.current_buffer.place_cursor(st);
		this.editor.source_view.scroll_to_iter(st, 0.1, true, 0.0, 0.5);
	}
}
