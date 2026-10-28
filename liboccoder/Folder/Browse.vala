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

namespace OLLMcoder.Folder
{
	/**
	 * One folder level. Not a tree.
	 *
	 * Child folders come from {@link Tree}. Empty and ignored
	 * folders stay hidden while that tree's ghost is on, which is how
	 * it starts. Pass true for ''load_files'' to list the files in
	 * that folder under the folders. Phone does. Tablet does not, and
	 * the desktop file list shows those files instead.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var browse = new Browse(tree, files, project, true);
	 * browse.refresh_folder(project);
	 * }}}
	 */
	class Browse : Gtk.Box
	{
		/**
		 * A folder row was opened. The caller shows that level.
		 *
		 * @param folder Folder that was opened
		 */
		public signal void selected(OLLMfiles.Folder folder);

		/**
		 * A file row was chosen. Emitted only when {@link load_files}
		 * is true.
		 *
		 * @param file File that was chosen
		 */
		public signal void file_activated(OLLMfiles.File file);

		/**
		 * Project the relative path is measured from.
		 */
		public OLLMfiles.Folder project { get; set; }

		/**
		 * When true, the files in the open folder are listed under
		 * the folders. Phone sets this. Tablet leaves it off.
		 */
		public bool load_files { get; private set; }

		/**
		 * Name filter for the files under the folders. Empty shows
		 * every file. The phone sets this while a search is showing.
		 */
		public string query { get; set; default = ""; }

		private Tree tree;
		private File.List file_list;
		private Gtk.ListBox folders;
		private GLib.ListModel folder_model;
		private Gtk.CustomFilter file_query;

		/**
		 * Placeholder under the folders. ''Loading files'' while that
		 * folder's files are on the way. ''No files'' after an empty
		 * reply. Phone only. The tablet file grid has its own label.
		 */
		private Gtk.Label file_note;

		/**
		 * Build one folder level.
		 *
		 * @param tree Folder store and the ghost filter
		 * @param file_list File store used when ''load_files'' is true
		 * @param project Project the relative path is measured from
		 * @param load_files When true, files of the open folder are listed
		 */
		public Browse(
			Tree tree,
			File.List file_list,
			OLLMfiles.Folder project,
			bool load_files
		) {
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, hexpand: true);
			this.tree = tree;
			this.file_list = file_list;
			this.project = project;
			this.load_files = load_files;
			this.folder_model = this.tree.folders;
			this.folders = new Gtk.ListBox() {
				hexpand = true,
				activate_on_single_click = true,
				can_focus = false,
				selection_mode = Gtk.SelectionMode.NONE,
			};
			if (!load_files) {
				this.folders.selection_mode = Gtk.SelectionMode.SINGLE;
			}
			this.folders.set_filter_func((row) => {
				var item = (OLLMfiles.Folder) this.folder_model.get_item((uint) row.get_index());
				if (item == null) {
					return false;
				}
				return this.tree.filter.match(item);
			});
			this.tree.filter.changed.connect(() => {
				this.folders.invalidate_filter();
			});
			this.folders.row_activated.connect((line) => {
				var folder = (OLLMfiles.Folder) this.folder_model.get_item((uint) line.get_index());
				if (folder == null) {
					return;
				}
				this.selected(folder);
			});
			this.append(this.folders);
			this.file_query = new Gtk.CustomFilter((item) => {
				if (this.query == "") {
					return true;
				}
				var file = (OLLMfiles.File) item;
				return file.path_basename.down().contains(this.query.down());
			});
			this.notify["query"].connect(() => {
				this.file_query.changed(Gtk.FilterChange.DIFFERENT);
			});
			if (!this.load_files) {
				return;
			}
			var file_sorted = new Gtk.SortListModel(
				new Gtk.FilterListModel(this.file_list.files, this.file_query),
				new Gtk.StringSorter(
					new Gtk.PropertyExpression(typeof(OLLMfiles.File), null, "path_basename")
				) {
					ignore_case = true,
				}
			);
			var file_box = new Gtk.ListBox() {
				hexpand = true,
				activate_on_single_click = true,
				can_focus = false,
				selection_mode = Gtk.SelectionMode.NONE,
			};
			file_box.bind_model(file_sorted, (item) => {
				return this.list_box_factory((OLLMfiles.FileBase) item);
			});
			this.file_note = new Gtk.Label("No files") {
				xalign = 0,
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_top = 8,
				margin_bottom = 8,
				css_classes = { "dim-label" },
			};
			file_box.set_placeholder(this.file_note);
			this.file_list.files.notify["empty"].connect(() => {
				if (!this.file_list.files.empty) {
					return;
				}
				this.file_note.label = "No files";
			});
			file_box.row_activated.connect((line) => {
				var file = (OLLMfiles.File) file_sorted.get_item((uint) line.get_index());
				if (file == null) {
					return;
				}
				this.file_activated(file);
			});
			this.append(file_box);
		}

		/**
		 * Show one folder. Child folders come from the store kept in
		 * memory. Files are loaded only when {@link load_files} is
		 * true. A folder with no child folders stays in the list
		 * that contains it, and that row is selected.
		 *
		 * @param folder Folder now shown
		 */
		public void refresh_folder(OLLMfiles.Folder folder)
		{
			var leaf = !this.load_files && !folder.is_project;
			if (leaf && this.tree.folders.segments.has_key(folder.path)) {
				var child_model = new Gtk.FilterListModel(
					this.tree.folders.segments.get(folder.path),
					this.tree.filter
				);
				leaf = child_model.get_n_items() == 0;
			}
			if (leaf) {
				var parent_id = (int) folder.parent_id;
				if (!this.tree.folders.id_map.has_key(parent_id)) {
					return;
				}
				var parent = this.tree.folders.id_map.get(parent_id);
				if (!this.tree.folders.segments.has_key(parent.path)) {
					return;
				}
				var segment = this.tree.folders.segments.get(parent.path);
				if (this.folder_model != segment) {
					this.refresh_folder(parent);
				}
				if (!this.tree.folders.item_at.has_key(folder.path)) {
					return;
				}
				var row = this.folders.get_row_at_index(
					this.tree.folders.item_at.get(folder.path)
				);
				if (row == null) {
					return;
				}
				this.folders.select_row(row);
				return;
			}
			this.folders.visible = false;
			this.folders.bind_model(null, null);
			if (!this.tree.folders.segments.has_key(folder.path)) {
				if (this.load_files) {
					this.file_note.label = "Loading files";
					this.file_list.files.load.begin(folder);
				}
				return;
			}
			var segment = this.tree.folders.segments.get(folder.path);
			var shown = new Gtk.FilterListModel(segment, this.tree.filter);
			this.folder_model = segment;
			this.folders.bind_model(segment, (item) => {
				return this.list_box_factory((OLLMfiles.FileBase) item);
			});
			this.folders.visible = shown.get_n_items() > 0;
			shown.items_changed.connect(() => {
				this.folders.visible = shown.get_n_items() > 0;
			});
			if (!this.load_files) {
				return;
			}
			this.file_note.label = "Loading files";
			this.file_list.files.load.begin(folder);
		}

		/**
		 * List box row for a folder or a file.
		 *
		 * A folder draws the coloured ''folder'' icon. A file draws
		 * the icon for its MIME type, then the generic icon for that
		 * type, then ''text-x-generic''. Both are 32 pixels. A link
		 * keeps that icon. Its name has a link mark before it. The
		 * second line is the path relative to the project, including
		 * the item name. A link uses the target path, so the line
		 * shows where it points. That line is absent at the project
		 * root. A long path drops the item name first, then keeps
		 * the first folder.
		 *
		 * @param item Folder or file for this list box
		 * @return The list box child
		 */
		public Gtk.Widget list_box_factory(OLLMfiles.FileBase item)
		{
			var line = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 8,
			};
			var icon = "folder";
			if (item is OLLMfiles.File) {
				var file = (OLLMfiles.File) item;
				icon = file.icon_name;
				if (!Gtk.IconTheme.get_for_display(this.get_display()).has_icon(icon)) {
					var generic = GLib.ContentType.get_generic_icon_name(file.mime_type);
					icon = generic != null ? generic : "text-x-generic";
				}
				if (!Gtk.IconTheme.get_for_display(this.get_display()).has_icon(icon)) {
					icon = "text-x-generic";
				}
			}
			line.append(new Gtk.Image.from_icon_name(icon) {
				valign = Gtk.Align.CENTER,
				pixel_size = 32,
			});
			var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				hexpand = true,
			};
			var title = item.path_basename;
			if (item is OLLMfiles.Folder && item.points_to_id != 0) {
				title = "🔗 " + title;
			}
			column.append(new Gtk.Label(title) {
				xalign = 0,
				halign = Gtk.Align.START,
				hexpand = true,
				ellipsize = Pango.EllipsizeMode.END,
				css_classes = { "body", "list-chat-title" },
			});
			var rel = item.path;
			if (item.points_to != null && item.points_to.path != "") {
				rel = item.points_to.path;
			}
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
	}
}
