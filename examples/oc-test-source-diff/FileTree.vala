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
 * Desktop tree tab. Folders on the left, files on the right.
 *
 * The left list is a {@link Gtk.TreeListModel} over
 * {@link FolderTreeStore}. One filter and one name sorter are shared
 * by the top list and every child segment. Names are alphabetical,
 * ignoring case. The right list is a {@link GLib.ListStore} of
 * {@link OLLMfiles.File}. {@link FolderTreeStore.load} fills the
 * left list. While that load is waiting on the file server, the
 * folder names are hidden and a spinner is shown across the top.
 * The names are already in order when they appear. A folder with
 * one child folder is a single row, unless that folder also holds
 * a file. The label joins the names with ''/'', so ''scalable''
 * holding only ''apps'' reads ''scalable/apps''. ''libochf'' stays
 * its own row because it has files beside ''Param''. A folder with
 * no child folder has no expander. The project is the top row and
 * it is expanded. Selecting it shows the files in that folder.
 * An empty folder has no icon.
 * Its name binds the folder's ''css-classes'', so a folder with no
 * files is light grey. The tooltip binds the folder's ''tooltip'',
 * the full path.
 * Clicking a folder asks the file server for that folder's files.
 * The right side is a name, size, and modified grid. Each cell binds
 * a property on the file. The name column binds the type icon.
 *
 * == Example ==
 *
 * {{{
 * var tree = new FileTree();
 * pages.add_titled(tree, "tree", "Tree");
 * }}}
 */
class FileTree : Gtk.Box
{
	/**
	 * Folder tree. The top store owns the path map and the flat list.
	 */
	public FolderTreeStore folders { get; private set; }

	/**
	 * Files for the folder selected on the left.
	 */
	public GLib.ListStore files { get; private set; }

	/**
	 * A file row was activated. The file selector opens it.
	 *
	 * @param file File the user activated
	 */
	public signal void file_activated(OLLMfiles.File file);

	/**
	 * Generation of the folder-file request. A newer click drops
	 * the reply from the previous one.
	 */
	private int file_epoch = 0;

	/**
	 * Left folder list. {@link on_selection_changed} reads the row.
	 */
	private Gtk.SingleSelection tree_selection;

	/**
	 * Centered on the file grid when the selected folder has no files.
	 */
	private Gtk.Label file_empty;

	/**
	 * File grid. A new folder resets the header sort to the name.
	 */
	private Gtk.ColumnView file_view;

	/**
	 * Name column. A fresh folder load sorts by this, ascending.
	 */
	private Gtk.ColumnViewColumn name_column;

	/**
	 * Shared by the top folder list and every child segment.
	 * Matches every row until search is wired.
	 */
	public Gtk.CustomFilter filter { get; private set; }

	/**
	 * Build the two panes with empty stores.
	 */
	public FileTree()
	{
		Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0, hexpand: true, vexpand: true);
		this.folders = new FolderTreeStore();
		this.files = new GLib.ListStore(typeof(OLLMfiles.File));
		this.filter = new Gtk.CustomFilter((item) => {
			return true;
		});
		var name_sorter = new Gtk.StringSorter(
			new Gtk.PropertyExpression(typeof(OLLMfiles.Folder), null, "path_basename")
		) {
			ignore_case = true,
		};
		Gtk.TreeListModelCreateModelFunc child_model = (item) => {
			var folder = item as OLLMfiles.Folder;
			if (folder == null) {
				return null;
			}
			if (!this.folders.segments.has_key(folder.path)) {
				return null;
			}
			var tip = folder;
			while (!tip.is_project &&
				this.folders.segments.has_key(tip.path) &&
				this.folders.segments.get(tip.path).get_n_items() == 1 &&
				tip.folder_count == 1 &&
				tip.file_count == 0) {
				tip = (OLLMfiles.Folder) this.folders.segments.get(tip.path).get_item(0);
			}
			if (this.folders.segments.get(tip.path).get_n_items() == 0) {
				return null;
			}
			return new Gtk.SortListModel(
				new Gtk.FilterListModel(this.folders.segments.get(tip.path), this.filter),
				name_sorter
			);
		};
		var tree_model = new Gtk.TreeListModel(
			new Gtk.SortListModel(new Gtk.FilterListModel(this.folders, this.filter), name_sorter),
			false,
			true,
			child_model
		);
		var tree_factory = new Gtk.SignalListItemFactory();
		tree_factory.setup.connect((obj) => {
			var row = (Gtk.ListItem) obj;
			var expander = new Gtk.TreeExpander();
			var label = new Gtk.Label("") {
				halign = Gtk.Align.START,
				hexpand = true,
				xalign = 0,
				ellipsize = Pango.EllipsizeMode.END,
			};
			expander.child = label;
			row.child = expander;
		});
		tree_factory.bind.connect((obj) => {
			var row = (Gtk.ListItem) obj;
			var expander = (Gtk.TreeExpander) row.child;
			var tree_row = (Gtk.TreeListRow) row.item;
			expander.list_row = tree_row;
			var folder = (OLLMfiles.Folder) tree_row.item;
			var parts = new Gee.ArrayList<string>();
			parts.add(folder.path_basename);
			var tip = folder;
			while (!tip.is_project &&
					this.folders.segments.has_key(tip.path) &&
					this.folders.segments.get(tip.path).get_n_items() == 1 &&
					tip.folder_count == 1 &&
					tip.file_count == 0) {
				tip = (OLLMfiles.Folder) this.folders.segments.get(tip.path).get_item(0);
				parts.add(tip.path_basename);
			}
			((Gtk.Label) expander.child).label = string.joinv("/", parts.to_array());
			tip.bind_property("css-classes", (Gtk.Label) expander.child,
				"css-classes", GLib.BindingFlags.SYNC_CREATE);
			tip.bind_property("tooltip", (Gtk.Label) expander.child,
				"tooltip-text", GLib.BindingFlags.SYNC_CREATE);
		});
		tree_factory.unbind.connect((obj) => {
			var row = (Gtk.ListItem) obj;
			((Gtk.TreeExpander) row.child).list_row = null;
		});
		this.tree_selection = new Gtk.SingleSelection(tree_model) {
			autoselect = false,
			can_unselect = true,
			selected = Gtk.INVALID_LIST_POSITION,
		};
		var tree_view = new Gtk.ListView(this.tree_selection, tree_factory) {
			hexpand = true,
			vexpand = true,
		};
		var name_factory = new Gtk.SignalListItemFactory();
		name_factory.setup.connect((obj) => {
			var row = (Gtk.ListItem) obj;
			var line = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			line.append(new Gtk.Image() {
				pixel_size = 16,
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
			file.bind_property("icon_name", (Gtk.Image) line.get_first_child(),
				"icon-name", GLib.BindingFlags.SYNC_CREATE);
			file.bind_property("path_basename", name_label,
				"label", GLib.BindingFlags.SYNC_CREATE);
			file.bind_property("tooltip", name_label,
				"tooltip-text", GLib.BindingFlags.SYNC_CREATE);
		});
		var size_factory = new Gtk.SignalListItemFactory();
		size_factory.setup.connect((obj) => {
			var row = (Gtk.ListItem) obj;
			row.child = new Gtk.Label("") {
				halign = Gtk.Align.END,
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
		this.name_column = new Gtk.ColumnViewColumn("Name", name_factory);
		this.name_column.expand = true;
		this.name_column.resizable = true;
		this.name_column.sorter = new Gtk.StringSorter(
			new Gtk.PropertyExpression(typeof(OLLMfiles.File), null, "path_basename")
		) {
			ignore_case = true,
		};
		var size_column = new Gtk.ColumnViewColumn("Size", size_factory);
		size_column.resizable = false;
		size_column.fixed_width = 44;
		size_column.sorter = new Gtk.NumericSorter(
			new Gtk.PropertyExpression(typeof(OLLMfiles.File), null, "size")
		);
		var modified_column = new Gtk.ColumnViewColumn("Modified", modified_factory);
		modified_column.resizable = false;
		modified_column.fixed_width = 64;
		modified_column.sorter = new Gtk.NumericSorter(
			new Gtk.PropertyExpression(typeof(OLLMfiles.File), null, "last_modified")
		);
		var file_selection = new Gtk.SingleSelection(null) {
			autoselect = false,
			can_unselect = true,
		};
		this.file_view = new Gtk.ColumnView(file_selection) {
			hexpand = true,
			vexpand = true,
			single_click_activate = false,
		};
		this.file_view.append_column(this.name_column);
		this.file_view.append_column(size_column);
		this.file_view.append_column(modified_column);
		file_selection.model = new Gtk.SortListModel(this.files, this.file_view.sorter);
		this.file_view.sort_by_column(this.name_column, Gtk.SortType.ASCENDING);
		this.file_view.activate.connect((position) => {
			var file = (OLLMfiles.File) file_selection.get_item(position);
			this.file_activated(file);
		});
		this.file_empty = new Gtk.Label("No files") {
			halign = Gtk.Align.CENTER,
			valign = Gtk.Align.CENTER,
			can_target = false,
			visible = false,
			css_classes = { "dim-label", "title-4" },
		};
		var file_overlay = new Gtk.Overlay() {
			hexpand = true,
			vexpand = true,
			child = new Gtk.ScrolledWindow() {
				child = this.file_view,
				hexpand = true,
				vexpand = true,
				propagate_natural_width = false,
				hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
			},
		};
		file_overlay.add_overlay(this.file_empty);
		this.tree_selection.selection_changed.connect(this.on_selection_changed);
		var status = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
			visible = false,
			margin_start = 8,
			margin_top = 6,
			margin_bottom = 2,
		};
		var spinner = new Gtk.Spinner() {
			width_request = 16,
			height_request = 16,
			valign = Gtk.Align.CENTER,
		};
		status.append(spinner);
		status.append(new Gtk.Label("Loading folders") {
			halign = Gtk.Align.START,
			valign = Gtk.Align.CENTER,
		});
		this.folders.notify["loading"].connect(() => {
			spinner.spinning = this.folders.loading;
			status.visible = this.folders.loading;
			if (this.folders.loading) {
				this.tree_selection.selected = Gtk.INVALID_LIST_POSITION;
				tree_view.opacity = 0;
				return;
			}
			this.tree_selection.model = new Gtk.TreeListModel(
				new Gtk.SortListModel(new Gtk.FilterListModel(this.folders, this.filter), 
						name_sorter),
				false, true, child_model
			);
			this.tree_selection.selected = Gtk.INVALID_LIST_POSITION;
			tree_view.opacity = 1;
			if (this.tree_selection.n_items > 0) {
				tree_view.scroll_to(0, Gtk.ListScrollFlags.NONE, null);
			}
		});
		var tree_column = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			hexpand = true,
			vexpand = true,
		};
		tree_column.append(new Gtk.ScrolledWindow() {
			child = tree_view,
			hexpand = true,
			vexpand = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
		});
		var pane = new Gtk.Paned(Gtk.Orientation.HORIZONTAL) {
			hexpand = true,
			vexpand = true,
			position = 240,
			resize_start_child = true,
			resize_end_child = true,
			shrink_start_child = false,
			shrink_end_child = true,
			start_child = tree_column,
			end_child = file_overlay,
		};
		var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			hexpand = true,
			vexpand = true,
		};
		column.append(status);
		column.append(pane);
		this.append(column);
	}

	/**
	 * Folder row selected. A joined row asks for the last folder's
	 * files and fills the grid. A newer selection drops the reply.
	 * The header sort goes back to the file name.
	 */
	private void on_selection_changed()
	{
		this.file_epoch++;
		this.files.remove_all();
		this.file_view.sort_by_column(this.name_column, Gtk.SortType.ASCENDING);
		this.file_empty.visible = false;
		if (this.tree_selection.selected == Gtk.INVALID_LIST_POSITION) {
			return;
		}
		var folder = (OLLMfiles.Folder) ((Gtk.TreeListRow) this.tree_selection.selected_item).item;
		while (!folder.is_project &&
				this.folders.segments.has_key(folder.path) &&
				this.folders.segments.get(folder.path).get_n_items() == 1 &&
				folder.folder_count == 1 &&
				folder.file_count == 0) {
			folder = (OLLMfiles.Folder) this.folders.segments.get(folder.path).get_item(0);
		}
		var epoch = this.file_epoch;
		folder.manager.rpc.call.begin(new OLLMrpc.Request() {
			method = "Folder.fetch_dir",
			args = OLLMrpc.args("s", folder.path)
		}, (obj, res) => {
			if (epoch != this.file_epoch) {
				return;
			}
			OLLMrpc.Response response;
			try {
				response = folder.manager.rpc.call.end(res);
			} catch (GLib.Error e) {
				GLib.warning("file list failed: %s", e.message);
				return;
			}
			if (response.retval.type() == GLib.Type.INVALID) {
				this.file_empty.visible = true;
				return;
			}
			var rows = (Gee.ArrayList<OLLMfiles.File>) response.retval.get_object();
			if (rows.size == 0) {
				this.file_empty.visible = true;
				return;
			}
			foreach (var file in rows) {
				file.manager = folder.manager;
				this.files.append(file);
			}
		});
	}
}
