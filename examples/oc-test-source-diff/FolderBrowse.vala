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
	 * One folder level. Not a tree.
	 *
	 * Child folders come from {@link FolderTree}. Empty and ignored
	 * folders stay hidden while that tree's ghost is on, which is how
	 * it starts. Pass true for ''load_files'' to list the files in
	 * that folder under the folders. Phone does. Tablet does not, and
	 * the desktop file list shows those files instead.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var browse = new FolderBrowse(tree, files, project, true);
	 * browse.refresh_folder(project);
	 * }}}
	 */
	class FolderBrowse : Gtk.Box
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

		private FolderTree tree;
		private FileList file_list;
		private Gtk.ListBox folders;
		private GLib.ListModel folder_model;
		private Gtk.CustomFilter file_query;

		/**
		 * Build one folder level.
		 *
		 * @param tree Folder store and the ghost filter
		 * @param file_list File store used when ''load_files'' is true
		 * @param project Project the relative path is measured from
		 * @param load_files When true, files of the open folder are listed
		 */
		public FolderBrowse(
			FolderTree tree,
			FileList file_list,
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
				selection_mode = Gtk.SelectionMode.NONE,
			};
			file_box.bind_model(file_sorted, (item) => {
				return this.list_box_factory((OLLMfiles.FileBase) item, "text-x-generic-symbolic");
			});
			file_box.set_placeholder(new Gtk.Label("No files") {
				xalign = 0,
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_top = 8,
				margin_bottom = 8,
				css_classes = { "dim-label" },
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
					this.file_list.files.load.begin(folder);
				}
				return;
			}
			var segment = this.tree.folders.segments.get(folder.path);
			var shown = new Gtk.FilterListModel(segment, this.tree.filter);
			this.folder_model = segment;
			this.folders.bind_model(segment, (item) => {
				return this.list_box_factory((OLLMfiles.FileBase) item, "folder-symbolic");
			});
			this.folders.visible = shown.get_n_items() > 0;
			shown.items_changed.connect(() => {
				this.folders.visible = shown.get_n_items() > 0;
			});
			if (!this.load_files) {
				return;
			}
			this.file_list.files.load.begin(folder);
		}

		/**
		 * List box factory for a folder or file. The caller picks the
		 * icon, so the folder list and the file list can diverge
		 * later. The second line is the path relative to the project,
		 * including the item name. That line is absent at the project
		 * root. A long path drops the item name first, then keeps the
		 * first folder.
		 *
		 * @param item Folder or file for this list box
		 * @param icon_name Icon chosen by that list
		 * @return The list box child
		 */
		public Gtk.Widget list_box_factory(OLLMfiles.FileBase item, string icon_name)
		{
			var line = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 8,
			};
			line.append(new Gtk.Image.from_icon_name(icon_name) {
				valign = Gtk.Align.CENTER,
			});
			var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				hexpand = true,
			};
			column.append(new Gtk.Label(item.path_basename) {
				xalign = 0,
				halign = Gtk.Align.START,
				hexpand = true,
				ellipsize = Pango.EllipsizeMode.END,
				css_classes = { "body", "list-chat-title" },
			});
			var rel = item.path;
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
