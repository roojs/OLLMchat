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
	 * File grid for one folder.
	 *
	 * Sits beside {@link Folder.Tree}. Three columns: name with a type
	 * icon, size, and modified time. The icon name comes from the
	 * daemon MIME type. The theme draws that name at 48 pixels. A
	 * name it does not have uses the generic icon for that type,
	 * then ''text-x-generic''. The name column
	 * starts in alphabetical order, ignoring case. The model is a
	 * {@link ListStore}. No folder selected shows
	 * ''Select a folder''. An empty reply shows ''No files''.
	 * {@link kind} narrows that grid to documents or to code.
	 * {@link query} is the desktop search text. Empty shows every
	 * file that type allows. A non-empty value keeps a file whose
	 * path, under the project, contains that text, ignoring case.
	 * A folder named like the search shows every file in it.
	 * {@link notice} replaces the grid. Activating a row emits
	 * {@link file_activated}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var list = new List();
	 * list.load(folder);
	 * list.file_activated.connect((file) => {
	 *     selector.choose(file);
	 * });
	 * }}}
	 */
	public class List : Gtk.Box
	{
		/**
		 * Files for the folder currently shown.
		 */
		public ListStore files { get; private set; default = new ListStore(); }

		/**
		 * A file row was activated. The file selector opens it.
		 *
		 * @param file File the user activated
		 */
		public signal void file_activated(OLLMfiles.File file);

		/**
		 * Centered on the grid. ''Select a folder'' when none is
		 * selected. ''No files'' when the selected folder has none.
		 * {@link notice} uses this same label.
		 */
		private Gtk.Label file_empty;

		/**
		 * File grid. A new folder resets the header sort to the name.
		 */
		private Gtk.ColumnView file_view;

		/**
		 * File rows. Up and Down step this when a file is selected.
		 */
		public Gtk.SingleSelection file_selection { get; private set; }

		/**
		 * Scroll around the file grid. A new folder sets it to the top.
		 */
		private Gtk.ScrolledWindow file_scroll;

		/**
		 * Name column. A fresh folder load sorts by this, ascending.
		 */
		private Gtk.ColumnViewColumn name_column;

		/**
		 * Type filter. {@link Folder.FileKind.ANY} shows every file in the
		 * folder. {@link Folder.FileKind.DOCUMENT} shows markdown and plain
		 * text. {@link Folder.FileKind.CODE} shows other text. A file that
		 * is not text stays hidden while either type is set.
		 */
		public Folder.FileKind kind { get; set; default = Folder.FileKind.ANY; }

		/**
		 * Path filter from the desktop search entry. Empty shows
		 * every file {@link kind} allows. A non-empty value keeps a
		 * file whose path, under the project, contains that text,
		 * ignoring case.
		 */
		public string query { get; set; default = ""; }

		/**
		 * Message in place of the grid. Empty leaves the folder
		 * text. Search uses ''too many results'' and ''no results''.
		 */
		public string notice { get; set; default = ""; }

		private OLLMfiles.Folder showing_folder;
		private bool showing_kept = false;

		/**
		 * Build the grid over an empty {@link ListStore}.
		 *
		 * @param single_click A tap activates a row. Tablet passes true.
		 */
		public List(bool single_click = false)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, hexpand: true, vexpand: true);
			var name_factory = new Gtk.SignalListItemFactory();
			name_factory.setup.connect((obj) => {
				var row = (Gtk.ListItem) obj;
				var line = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
				line.append(new Gtk.Image() {
					pixel_size = 48,
				});
				line.append(new Gtk.Label("") {
					halign = Gtk.Align.START,
					hexpand = true,
					xalign = 0,
					ellipsize = Pango.EllipsizeMode.END,
				});
				row.child = line;
			});
			name_factory.bind.connect((obj) => {
				var row = (Gtk.ListItem) obj;
				var line = (Gtk.Box) row.child;
				var file = (OLLMfiles.File) row.item;
				var name_label = (Gtk.Label) line.get_first_child().get_next_sibling();
				var icon = file.icon_name;
				if (!Gtk.IconTheme.get_for_display(this.get_display()).has_icon(icon)) {
					var generic = GLib.ContentType.get_generic_icon_name(file.mime_type);
					icon = generic != null ? generic : "text-x-generic";
				}
				if (!Gtk.IconTheme.get_for_display(this.get_display()).has_icon(icon)) {
					icon = "text-x-generic";
				}
				((Gtk.Image) line.get_first_child()).icon_name = icon;
				var title = file.path_basename;
				if (file.points_to_id == -1) {
					title = title + " [broken link]";
					name_label.add_css_class("error");
				}
				if (file.points_to_id != -1) {
					name_label.remove_css_class("error");
				}
				name_label.label = title;
				file.bind_property("tooltip", name_label,
					"tooltip-text", GLib.BindingFlags.SYNC_CREATE);
				var host = (!) line.get_parent();
				while (host.css_name != "row") {
					host = (!) host.get_parent();
				}
				host.remove_css_class("selector-mark");
				if (file.is_active) {
					host.add_css_class("selector-mark");
				}
				host.set_data("active-watch", file.notify["is-active"].connect(() => {
					if (file.is_active) {
						host.add_css_class("selector-mark");
						return;
					}
					host.remove_css_class("selector-mark");
				}));
			});
			name_factory.unbind.connect((obj) => {
				var row = (Gtk.ListItem) obj;
				var host = (!) ((!) row.child).get_parent();
				while (host.css_name != "row") {
					host = (!) host.get_parent();
				}
				((OLLMfiles.File) row.item).disconnect(host.get_data<ulong>("active-watch"));
				host.remove_css_class("selector-mark");
			});
			var size_factory = new Gtk.SignalListItemFactory();
			size_factory.setup.connect((obj) => {
				var row = (Gtk.ListItem) obj;
				row.child = new Gtk.Label("") {
					halign = Gtk.Align.END,
					hexpand = true,
					xalign = 1,
					css_classes = { "caption", "dim-label" },
				};
			});
			size_factory.bind.connect((obj) => {
				var row = (Gtk.ListItem) obj;
				((OLLMfiles.File) row.item).bind_property("display_size", (Gtk.Label) row.child,
					"label", GLib.BindingFlags.SYNC_CREATE);
			});
			var modified_factory = new Gtk.SignalListItemFactory();
			modified_factory.setup.connect((obj) => {
				var row = (Gtk.ListItem) obj;
				row.child = new Gtk.Label("") {
					halign = Gtk.Align.END,
					xalign = 1,
					css_classes = { "caption", "dim-label" },
				};
			});
			modified_factory.bind.connect((obj) => {
				var row = (Gtk.ListItem) obj;
				((OLLMfiles.File) row.item).bind_property("display_modified", (Gtk.Label) row.child,
					"label", GLib.BindingFlags.SYNC_CREATE);
			});
			this.name_column = new Gtk.ColumnViewColumn("Name", name_factory) {
				expand = true,
				resizable = true,
				sorter = new Gtk.StringSorter(
					new Gtk.PropertyExpression(typeof(OLLMfiles.File), null, "path_basename")
				) {
					ignore_case = true,
				},
			};
			var size_column = new Gtk.ColumnViewColumn("Size", size_factory) {
				resizable = false,
				fixed_width = 53,
				sorter = new Gtk.NumericSorter(
					new Gtk.PropertyExpression(typeof(OLLMfiles.File), null, "size")
				),
			};
			var modified_column = new Gtk.ColumnViewColumn("Modified", modified_factory) {
				resizable = false,
				fixed_width = 74,
				sorter = new Gtk.NumericSorter(
					new Gtk.PropertyExpression(typeof(OLLMfiles.File), null, "last_modified")
				),
			};
			var file_filter = new Gtk.CustomFilter((item) => {
				var file = (OLLMfiles.File) item;
				if (this.query != "") {
					var shown = file.path;
					var project = file.manager.active_project;
					if (project != null && shown.has_prefix(project.path + "/")) {
						shown = shown.substring(project.path.length + 1);
					}
					if (!shown.down().contains(this.query.down())) {
						return false;
					}
				}
				if (this.kind == Folder.FileKind.ANY) {
					return true;
				}
				var document = false;
				if (file.is_text && file.language == "") {
					document = true;
				}
				if (file.is_text && file.language != "") {
					switch (file.language.down()) {
						case "markdown":
						case "txt":
						case "text":
						case "plaintext":
							document = true;
							break;
						default:
							break;
					}
				}
				switch (this.kind) {
					case Folder.FileKind.DOCUMENT:
						return document;
					case Folder.FileKind.CODE:
						return file.is_text && !document;
					default:
						return true;
				}
			});
			this.file_selection = new Gtk.SingleSelection(null) {
				autoselect = false,
				can_unselect = true,
			};
			var row_factory = new Gtk.SignalListItemFactory();
			row_factory.bind.connect((obj) => {
				var view_row = (Gtk.ColumnViewRow) obj;
				var openable = ((OLLMfiles.File) view_row.item).points_to_id != -1;
				view_row.selectable = openable;
				view_row.activatable = openable;
			});
			this.file_view = new Gtk.ColumnView(this.file_selection) {
				hexpand = true,
				vexpand = true,
				single_click_activate = single_click,
				row_factory = row_factory,
			};
			this.file_view.append_column(this.name_column);
			this.file_view.append_column(size_column);
			this.file_view.append_column(modified_column);
			this.file_selection.model = new Gtk.SortListModel(
				new Gtk.FilterListModel(this.files, file_filter),
				this.file_view.sorter
			);
			this.file_view.sort_by_column(this.name_column, Gtk.SortType.ASCENDING);
			this.file_view.activate.connect((position) => {
				var file = (OLLMfiles.File) this.file_selection.get_item(position);
				if (file.points_to_id == -1) {
					return;
				}
				this.file_activated(file);
			});
			this.file_selection.selection_changed.connect(() => {
				if (this.file_selection.selected == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				var chosen = (OLLMfiles.File) this.file_selection.selected_item;
				if (chosen.points_to_id == -1) {
					this.file_selection.selected = Gtk.INVALID_LIST_POSITION;
					return;
				}
				this.file_view.scroll_to(this.file_selection.selected, null,
					Gtk.ListScrollFlags.FOCUS, null);
			});
			this.file_empty = new Gtk.Label("Select a folder") {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				can_target = false,
				visible = true,
				css_classes = { "dim-label", "title-4" },
			};
			this.file_scroll = new Gtk.ScrolledWindow() {
				child = this.file_view,
				hexpand = true,
				vexpand = true,
				propagate_natural_width = false,
				hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
			};
			var file_overlay = new Gtk.Overlay() {
				hexpand = true,
				vexpand = true,
				child = this.file_scroll,
			};
			file_overlay.add_overlay(this.file_empty);
			this.append(file_overlay);
			this.notify["notice"].connect(() => {
				if (this.notice != "") {
					this.file_empty.label = this.notice;
					this.file_empty.visible = true;
					this.file_view.visible = false;
					return;
				}
				this.file_view.visible = true;
				if (this.files.empty) {
					this.file_empty.label = "No files";
					this.file_empty.visible = true;
					return;
				}
				if (this.files.get_n_items() == 0) {
					this.file_empty.label = "Select a folder";
					this.file_empty.visible = true;
					return;
				}
				this.file_empty.visible = false;
			});
			this.files.notify["empty"].connect(() => {
				if (this.notice != "") {
					return;
				}
				if (!this.files.empty && this.files.get_n_items() == 0) {
					return;
				}
				if (this.files.empty || this.file_selection.n_items == 0) {
					this.file_empty.label = "No files";
					this.file_empty.visible = true;
					return;
				}
				this.file_empty.visible = false;
			});
			this.notify["kind"].connect(() => {
				file_filter.changed(Gtk.FilterChange.DIFFERENT);
				if (this.notice != "") {
					return;
				}
				if (!this.files.empty && this.files.get_n_items() == 0) {
					return;
				}
				if (this.files.empty || this.file_selection.n_items == 0) {
					this.file_empty.label = "No files";
					this.file_empty.visible = true;
					return;
				}
				this.file_empty.visible = false;
			});
			this.notify["query"].connect(() => {
				file_filter.changed(Gtk.FilterChange.DIFFERENT);
				if (this.notice != "") {
					return;
				}
				if (!this.files.empty && this.files.get_n_items() == 0) {
					return;
				}
				if (this.files.empty || this.file_selection.n_items == 0) {
					this.file_empty.label = "No files";
					this.file_empty.visible = true;
					return;
				}
				this.file_empty.visible = false;
			});
			this.file_selection.items_changed.connect(() => {
				if (this.notice != "") {
					return;
				}
				if (!this.files.empty && this.files.get_n_items() == 0) {
					return;
				}
				if (this.files.empty || this.file_selection.n_items == 0) {
					this.file_empty.label = "No files";
					this.file_empty.visible = true;
					return;
				}
				this.file_empty.visible = false;
			});
			this.files.items_changed.connect(() => {
				this.file_scroll.vadjustment.value = this.file_scroll.vadjustment.lower;
			});
		}

		/**
		 * Show ''folder''. The header sort goes back to the file name
		 * and the list opens at the top. {@link ListStore.load}
		 * fills the grid. The grid says Loading files until
		 * that reply.
		 *
		 * @param folder Folder whose files should be shown
		 */
		public void load(OLLMfiles.Folder folder)
		{
			if (this.showing_kept && this.showing_folder.id == folder.id) {
				return;
			}
			this.showing_kept = true;
			this.showing_folder = folder;
			this.file_scroll.vadjustment.value = this.file_scroll.vadjustment.lower;
			this.file_view.sort_by_column(this.name_column, Gtk.SortType.ASCENDING);
			this.notice = "";
			this.file_selection.selected = Gtk.INVALID_LIST_POSITION;
			this.files.load.begin(folder);
			this.file_empty.label = "Loading files";
			this.file_empty.visible = true;
			this.file_view.visible = true;
		}

		/**
		 * Drop the rows. A cleared folder selection uses this. The
		 * header sort goes back to the file name and the list opens
		 * at the top.
		 */
		public void clear()
		{
			this.showing_kept = false;
			this.file_scroll.vadjustment.value = this.file_scroll.vadjustment.lower;
			this.file_view.sort_by_column(this.name_column, Gtk.SortType.ASCENDING);
			this.notice = "";
			this.file_selection.selected = Gtk.INVALID_LIST_POSITION;
			this.file_view.visible = true;
			this.files.clear();
			this.file_empty.label = "Select a folder";
			this.file_empty.visible = true;
		}
	}
}
