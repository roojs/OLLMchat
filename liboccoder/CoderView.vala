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

namespace OLLMcoder
{
	/**
	 * Coder screen: header, editor, and the search bar along the bottom.
	 *
	 * The header is {@link ProjectSelector}, {@link File.Nav},
	 * the editor save button, and the document toggle.
	 * The editor is {@link SourceView}. A rendered file shows
	 * the active {@link DocView} in that column instead. The project
	 * list is an overlay on that column. Project selection and
	 * search stay here. A chosen file is opened on the editor.
	 * {@link SourceView.file_changed} updates the file button.
	 * {@link SourceView.find} and {@link SourceView.find_again} drive
	 * this search bar. The phone leaves that bar hidden. Search
	 * there comes back when the screen has room for it.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var coder = new CoderView(manager, Form.DESKTOP);
	 * window.child = coder;
	 * }}}
	 */
	public class CoderView : Gtk.Box
	{
		/**
		 * Phone and tablet pull-over. Desktop still builds one; the
		 * host overlays it only when the form is not desktop.
		 */
		public SelectorPull selector { get; private set; }

		/**
		 * Header project button and the list on the editor.
		 */
		public ProjectSelector projects { get; private set; }

		/**
		 * Header file button and folder tree.
		 */
		public File.Nav files { get; private set; }

		public SourceView editor { get; private set; }
		private DocView doc;
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
		 * @param form Desktop, phone, or tablet
		 */
		public CoderView(OLLMfiles.ProjectManager manager, Form form)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			manager.buffer_provider = new OLLMcoder.BufferProvider();
			this.selector = new SelectorPull(form);
			this.projects = new ProjectSelector(manager, form, this.selector);
			this.files = new File.Overlay(manager, form);
			if (form == Form.PHONE) {
				this.files = new File.Pullout(manager, form, this.selector);
			}
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
			var showing_doc = false;
			var md_button = new Gtk.Button() {
				icon_name = "document-print-symbolic",
				tooltip_text = "Change to markdown",
				hexpand = false,
				valign = Gtk.Align.CENTER,
				visible = false,
			};
			md_button.add_css_class("flat");
			md_button.clicked.connect(() => {
				if (showing_doc) {
					showing_doc = false;
					md_button.icon_name = "document-print-symbolic";
					md_button.tooltip_text = "Change to markdown";
					this.doc.visible = false;
					this.editor.visible = true;
					return;
				}
				var file = this.editor.current_file;
				if (file == null) {
					md_button.visible = false;
					return;
				}
				showing_doc = true;
				md_button.icon_name = "format-justify-left-symbolic";
				md_button.tooltip_text = "Change to source view";
				this.doc.show_file(file, false);
				this.editor.visible = false;
				this.doc.visible = true;
			});
			header.append(md_button);
			this.files.notify["visible"].connect(() => {
				spacer.visible = !this.files.visible;
			});
			this.projects.opened.connect(() => {
				if (form == Form.PHONE) {
					return;
				}
				((File.Overlay) this.files).list.visible = false;
			});
			this.files.opened.connect(() => {
				this.projects.list.visible = false;
			});
			this.projects.chosen.connect((folder) => {
				if (this.files.project.is_project &&
					this.files.project.path == folder.path) {
					this.files.notify_property("project");
					return;
				}
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
			var editor_column = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
			};
			var markdown = new MarkdownView() {
				visible = false,
			};
			this.doc = markdown;
			editor_column.append(markdown);
			editor_column.append(this.editor);
			editor_column.append(search_bar);
			var editor_layer = new Gtk.Overlay() {
				hexpand = true,
				vexpand = true,
				child = editor_column,
			};
			editor_layer.add_overlay(this.projects.shade);
			editor_layer.add_overlay(this.projects.list);
			if (form == Form.DESKTOP) {
				editor_layer.add_overlay(((File.Overlay) this.files).list);
			}
			if (form == Form.TABLET) {
				var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
					hexpand = true,
					vexpand = true,
				};
				column.append(header);
				column.append(editor_layer);
				var cover = new Gtk.Overlay() {
					hexpand = true,
					vexpand = true,
					child = column,
				};
				var sheet = ((File.Overlay) this.files).list;
				sheet.halign = Gtk.Align.FILL;
				sheet.valign = Gtk.Align.FILL;
				cover.add_overlay(sheet);
				cover.add_overlay(this.selector);
				this.append(cover);
			}
			if (form == Form.PHONE) {
				var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
					hexpand = true,
					vexpand = true,
				};
				column.append(header);
				column.append(editor_layer);
				var cover = new Gtk.Overlay() {
					hexpand = true,
					vexpand = true,
					child = column,
				};
				cover.add_overlay(this.selector);
				this.append(cover);
			}
			if (form == Form.DESKTOP) {
				this.append(header);
				this.append(editor_layer);
			}
			this.files.chosen.connect((file) => {
				this.editor.open_file.begin(file);
			});
			this.editor.file_changed.connect((file) => {
				var shown = file.path_basename;
				if (this.files.form != Form.PHONE && this.files.project.path.length > 0
					&& file.path.has_prefix(this.files.project.path + "/")) {
					shown = file.path.substring(this.files.project.path.length + 1);
				}
				this.files.label.label = shown;
				this.search_context = null;
				this.last_search_end = 0;
				this.search_entry.text = "";
				this.update_search_results();
				search_bar.visible = form != Form.PHONE;
				var is_markdown = file.language.down() == "markdown" ||
					file.path_basename.down().has_suffix(".md") ||
					file.path_basename.down().has_suffix(".markdown");
				md_button.visible = is_markdown;
				if (!is_markdown) {
					showing_doc = false;
					md_button.icon_name = "document-print-symbolic";
					md_button.tooltip_text = "Change to markdown";
					this.doc.visible = false;
					this.editor.visible = true;
					return;
				}
				showing_doc = true;
				md_button.icon_name = "format-justify-left-symbolic";
				md_button.tooltip_text = "Change to source view";
				this.doc.show_file(file, true);
				this.editor.visible = false;
				this.doc.visible = true;
			});
			this.editor.find.connect(() => {
				if (form == Form.PHONE) {
					return;
				}
				this.search_entry.grab_focus();
				this.search_entry.select_region(0, -1);
			});
			this.editor.find_again.connect((back) => {
				if (form == Form.PHONE) {
					return;
				}
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
			var search_buffer = this.editor.current_buffer;
			if (this.doc.visible && this.editor.current_file != null) {
				search_buffer = this.editor.current_file.buffer as GtkSource.Buffer;
			}
			if (search_buffer == null) {
				this.search_context = null;
				this.update_search_results();
				return;
			}
			var search_settings = new GtkSource.SearchSettings();
			search_settings.case_sensitive = this.case_sensitive_checkbox.active;
			search_settings.regex_enabled = this.regex_checkbox.active;
			search_settings.wrap_around = false;
			this.search_context = new GtkSource.SearchContext(search_buffer, search_settings);
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
			if (this.doc.visible) {
				var txt = this.search_entry.text;
				if (this.multiline_checkbox.active) {
					txt = txt.replace("\\n", "\n");
				}
				this.doc.show_match(txt, true,
					this.case_sensitive_checkbox.active, this.regex_checkbox.active);
				return;
			}
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
			if (this.doc.visible) {
				var txt = this.search_entry.text;
				if (this.multiline_checkbox.active) {
					txt = txt.replace("\\n", "\n");
				}
				this.doc.show_match(txt, false,
					this.case_sensitive_checkbox.active, this.regex_checkbox.active);
				return;
			}
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
}
