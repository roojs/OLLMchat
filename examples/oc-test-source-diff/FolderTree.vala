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
 * Folder tree for the desktop file selector.
 *
 * Folders only. Files for the selected folder are a {@link FileList}
 * beside this one. The list is a {@link Gtk.TreeListModel} over
 * {@link FolderTreeStore}. One filter and one name sorter are shared
 * by the top list and every child segment. Names are alphabetical,
 * ignoring case. {@link FolderTreeStore.load} fills the list. While
 * that load is waiting on the file server, the folder names are
 * hidden and a spinner is shown across the top. The names are
 * already in order when they appear. A folder with one child folder
 * is a single row, unless that folder also holds a file. The label
 * joins the names with ''/'', so ''scalable'' holding only ''apps''
 * reads ''scalable/apps''. ''libochf'' stays its own row because it
 * has files beside ''Param''. A folder with no child folder has no
 * expander. The project is the top row and it is expanded. Selecting
 * it emits {@link selected} for that folder. An empty folder has no
 * icon. Its name binds the folder's ''css-classes'', so a folder
 * with no files is light grey. The tooltip binds the folder's
 * ''tooltip'', the full path. The ghost button starts hiding empty
 * and ignored folders. Its icon is a crossed eye while hiding and
 * an eye while showing. It does not stay pressed. A gitignored
 * folder that is shown has a conceal icon beside its name. Collapse
 * all uses ''document-send-symbolic''. It folds every open row under
 * the project and does not stay down. The project row stays open
 * and has no expander. {@link kind} is the type filter.
 * {@link FileKind.ANY} shows every folder the ghost allows.
 * {@link FileKind.DOCUMENT} hides a folder whose document
 * count is zero. {@link FileKind.CODE} hides a folder whose
 * code count is zero. An empty folder is hidden while either
 * type is set.
 * A second click on the selected row clears that selection.
 *
 * == Example ==
 *
 * {{{
 * var folders = new FolderTree();
 * folders.selected.connect((folder) => {
 *     files.load(folder);
 * });
 * }}}
 */

/**
 * Which rows the file selector keeps.
 *
 * {@link ANY} shows every row the ghost allows. {@link DOCUMENT}
 * keeps documents. {@link CODE} keeps code. An empty folder is
 * hidden while either type is set. A folder stays when a child
 * holds that type.
 */
public enum FileKind {
	ANY,
	DOCUMENT,
	CODE
}

class FolderTree : Gtk.Box
{
	/**
	 * Folder rows. The top store owns the path map and the flat list.
	 */
	public FolderTreeStore folders {
		get; private set; default = new FolderTreeStore();
	}

	/**
	 * A folder row was selected. A joined row reports the last
	 * folder in that chain.
	 *
	 * @param folder Folder whose files should be listed
	 */
	public signal void selected(OLLMfiles.Folder folder);

	/**
	 * The folder selection was cleared.
	 */
	public signal void cleared();

	/**
	 * Collapse the folder tree. A normal button, so it does not
	 * stay down.
	 */
	public Gtk.Button collapse { get; private set; }

	/**
	 * Hide empty folders and gitignored folders. Starts hiding.
	 * A crossed eye means hiding. An eye means showing. It does
	 * not stay pressed.
	 */
	public Gtk.Button ghost { get; private set; }

	/**
	 * While true, empty folders and gitignored folders are left
	 * out. Starts true. The ghost icon shows that state.
	 */
	private bool hiding = true;

	/**
	 * Folder list. The selection signal reads the row.
	 */
	private Gtk.SingleSelection tree_selection;

	/**
	 * Type filter. {@link FileKind.ANY} shows every folder the
	 * ghost allows. {@link FileKind.DOCUMENT} hides a folder
	 * whose document count is zero. {@link FileKind.CODE} hides
	 * a folder whose code count is zero. Those counts already
	 * include a child that has the type. The project row stays.
	 */
	public FileKind kind { get; set; default = FileKind.ANY; }

	/**
	 * Shared by the top folder list and every child segment.
	 * While hiding, an empty folder or a gitignored folder is
	 * left out. {@link kind} hides a folder whose count for
	 * that type is zero. The project row stays.
	 */
	public Gtk.CustomFilter filter { get; private set; }

	/**
	 * Build the folder list with an empty store.
	 */
	public FolderTree()
	{
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, hexpand: true, vexpand: true);
		this.ghost = new Gtk.Button() {
			icon_name = "view-conceal-symbolic",
			tooltip_text = "Hide empty and ignored folders",
			can_focus = false,
			valign = Gtk.Align.CENTER,
			margin_end = 3,
		};
		this.ghost.add_css_class("flat");
		this.filter = new Gtk.CustomFilter((item) => {
			var folder = (OLLMfiles.Folder) item;
			if (folder.is_project) {
				return true;
			}
			if (this.hiding && folder.is_ignored) {
				return false;
			}
			if (this.hiding && folder.file_count == 0 && folder.folder_count == 0) {
				return false;
			}
			if (this.kind == FileKind.DOCUMENT && folder.document_count == 0) {
				return false;
			}
			if (this.kind == FileKind.CODE && folder.code_count == 0) {
				return false;
			}
			return true;
		});
		this.notify["kind"].connect(() => {
			this.filter.changed(Gtk.FilterChange.DIFFERENT);
		});
		this.ghost.clicked.connect(() => {
			this.hiding = !this.hiding;
			this.ghost.icon_name = this.hiding
				? "view-conceal-symbolic"
				: "view-reveal-symbolic";
			this.filter.changed(Gtk.FilterChange.DIFFERENT);
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
			var line = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			line.append(new Gtk.Label("") {
				halign = Gtk.Align.START,
				hexpand = true,
				xalign = 0,
				ellipsize = Pango.EllipsizeMode.END,
			});
			line.append(new Gtk.Image.from_icon_name("view-conceal-symbolic") {
				pixel_size = 16,
				visible = false,
			});
			expander.child = line;
			row.child = expander;
		});
		tree_factory.bind.connect((obj) => {
			var row = (Gtk.ListItem) obj;
			var expander = (Gtk.TreeExpander) row.child;
			var tree_row = (Gtk.TreeListRow) row.item;
			expander.list_row = tree_row;
			var folder = (OLLMfiles.Folder) tree_row.item;
			expander.hide_expander = folder.is_project;
			if (folder.is_project && !tree_row.expanded) {
				tree_row.expanded = true;
			}
			if (folder.is_project && tree_row.get_data<bool>("keep-open") != true) {
				tree_row.set_data("keep-open", true);
				tree_row.notify["expanded"].connect(() => {
					if (tree_row.expanded) {
						return;
					}
					tree_row.expanded = true;
				});
			}
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
			var line = (Gtk.Box) expander.child;
			var name_label = (Gtk.Label) line.get_first_child();
			name_label.label = string.joinv("/", parts.to_array());
			((Gtk.Image) name_label.get_next_sibling()).visible = tip.is_ignored;
			tip.bind_property("css-classes", name_label,
				"css-classes", GLib.BindingFlags.SYNC_CREATE);
			tip.bind_property("tooltip", name_label,
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
		/* select_item keeps a selected row. A second click on
		 * the row body clears it. Capture runs before the list's
		 * own click. Press records the selected row. Release
		 * claims that click and clears the selection. The
		 * expander arrow is outside the row box, so it still
		 * opens and closes. */
		var armed = Gtk.INVALID_LIST_POSITION;
		var click = new Gtk.GestureClick() {
			button = 1,
			propagation_phase = Gtk.PropagationPhase.CAPTURE,
		};
		tree_view.add_controller(click);
		click.pressed.connect((n_press, x, y) => {
			armed = Gtk.INVALID_LIST_POSITION;
			if (n_press != 1 || this.tree_selection.selected == Gtk.INVALID_LIST_POSITION) {
				return;
			}
			var widget = tree_view.pick(x, y, Gtk.PickFlags.DEFAULT);
			var on_line = false;
			while (widget != null && !(widget is Gtk.TreeExpander)) {
				if (widget is Gtk.Box) {
					on_line = true;
				}
				widget = widget.get_parent();
			}
			if (widget == null || !on_line) {
				return;
			}
			var row = ((Gtk.TreeExpander) widget).list_row;
			if (row == null || row.get_position() != this.tree_selection.selected) {
				return;
			}
			armed = this.tree_selection.selected;
		});
		click.released.connect((n_press, x, y) => {
			if (n_press != 1 || armed == Gtk.INVALID_LIST_POSITION) {
				return;
			}
			var held = armed;
			armed = Gtk.INVALID_LIST_POSITION;
			if (this.tree_selection.selected != held) {
				return;
			}
			var widget = tree_view.pick(x, y, Gtk.PickFlags.DEFAULT);
			var on_line = false;
			while (widget != null && !(widget is Gtk.TreeExpander)) {
				if (widget is Gtk.Box) {
					on_line = true;
				}
				widget = widget.get_parent();
			}
			if (widget == null || !on_line) {
				return;
			}
			var row = ((Gtk.TreeExpander) widget).list_row;
			if (row == null || row.get_position() != held) {
				return;
			}
			click.set_state(Gtk.EventSequenceState.CLAIMED);
			this.tree_selection.selected = Gtk.INVALID_LIST_POSITION;
		});
		this.collapse = new Gtk.Button() {
			icon_name = "document-send-symbolic",
			tooltip_text = "Collapse all",
			can_focus = false,
			valign = Gtk.Align.CENTER,
			margin_end = 3,
		};
		this.collapse.add_css_class("flat");
		this.collapse.clicked.connect(() => {
			var model = (Gtk.TreeListModel) this.tree_selection.model;
			/* TreeListModel has no collapse-all. The project row stays
			 * open: collapsing it does not stick, the next expand
			 * shuts again. A collapsed parent leaves the flat list
			 * and takes its children with it, so later indexes move.
			 * Walk from the end: those children are already past the
			 * cursor and the parent index holds. */
			var index = model.n_items;
			while (index > 0) {
				index--;
				var row = model.get_row(index);
				if (!row.expanded) {
					continue;
				}
				if (((OLLMfiles.Folder) row.item).is_project) {
					continue;
				}
				row.expanded = false;
			}
		});
		this.tree_selection.selection_changed.connect(() => {
			if (this.tree_selection.selected == Gtk.INVALID_LIST_POSITION) {
				this.cleared();
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
			this.selected(folder);
		});
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
		this.append(status);
		this.append(new Gtk.ScrolledWindow() {
			child = tree_view,
			hexpand = true,
			vexpand = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
		});
	}
}
