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
	 * File navigation shared by the desktop sheet and the pull-over.
	 *
	 * The resting control is a flat button with a file icon. It stays
	 * hidden until a project is chosen. {@link Overlay} covers the
	 * editor. {@link Pullout} fills {@link SelectorPull}. Documents
	 * and code stay here and stay hidden. The one that is down hides
	 * folders with none of that type, and turns the other off.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var files = new Overlay(manager);
	 * projects.chosen.connect((folder) => {
	 *     files.project = folder;
	 * });
	 * }}}
	 */
	public class Nav : Gtk.Box
	{
		/**
		 * Emitted when the desktop sheet is about to open.
		 *
		 * The host closes the project list from this.
		 */
		public signal void opened();

		/**
		 * Emitted after a file row is chosen.
		 *
		 * @param file File that was chosen
		 */
		public signal void chosen(OLLMfiles.File file);

		/**
		 * Active project. Setting a real project shows this control.
		 * An empty folder stays hidden. Desktop then opens the sheet.
		 */
		public OLLMfiles.Folder project { get; set; }

		/**
		 * Connected manager. File rows come from its active project.
		 */
		public OLLMfiles.ProjectManager manager { get; set; }

		/**
		 * Layout. Desktop, phone, or tablet.
		 */
		public Form form { get; set; default = Form.DESKTOP; }

		/**
		 * Caption on the file button. The coder screen sets this when
		 * the editor reports a different open file.
		 */
		public Gtk.Label label { get; private set; }

		/**
		 * Folder tree on the Tree tab. Rows arrive in
		 * {@link Folder.Tree.folders}.
		 */
		public Folder.Tree folder_tree { get; private set; default = new Folder.Tree(); }

		/**
		 * Files for the folder selected in {@link folder_tree}.
		 */
		public List file_list { get; private set; }

		/**
		 * Documents type button. Hidden. Down shows document folders
		 * and turns the code button off. A second click clears the
		 * type.
		 */
		public Gtk.ToggleButton documents { get; private set; }

		/**
		 * Code type button. Hidden. The icon is
		 * ''completion-snippet-symbolic''. Down shows code folders
		 * and turns the documents button off. A second click clears
		 * the type.
		 */
		public Gtk.ToggleButton code { get; private set; }

		/**
		 * Header button. Desktop puts it in the search stack.
		 * Phone and tablet show it on its own.
		 */
		protected Gtk.Button button;

		protected int history_epoch = 0;
		protected int pullout_epoch = 0;
		protected int search_epoch = 0;

		/**
		 * Folder open when a name search started. Clearing the
		 * search returns here. Phone and tablet use this.
		 */
		protected OLLMfiles.Folder search_home;

		/**
		 * True from the first character of a name search until the
		 * query is cleared.
		 */
		protected bool search_open = false;

		/**
		 * The name search was wider than the server will return.
		 * A folder with matching files still shows those files.
		 * A folder with none shows ''too many results''.
		 */
		protected bool search_wide = false;

		/**
		 * File path shown on the button. A search that is too wide
		 * replaces the label until the text is narrowed or cleared.
		 */
		protected string path_text = "Select file";

		/**
		 * Folder-name buttons for the open path on phone and tablet.
		 */
		protected Gtk.Box path_box;

		/**
		 * Width of the path row last used to shorten crumb labels.
		 */
		protected int fitted_width = -1;

		/**
		 * True while crumb labels change, so width notify does not
		 * fit the same row again.
		 */
		protected bool fitting_crumbs = false;

		/**
		 * True when {@link render_crumbs} shortened at least one
		 * folder button to ''...'' to fit the path row.
		 */
		protected bool crumbs_shortened = false;

		/**
		 * Counts phone and tablet folder changes. Width notify on
		 * the path row skips fitting while this is still zero.
		 */
		protected int place_gen = 0;

		/**
		 * Folder shown in the phone or tablet folder list.
		 */
		protected OLLMfiles.Folder level;

		/**
		 * Build the file button and the shared folder tree.
		 *
		 * @param manager Connected manager. Rows come from the project.
		 * @param form Desktop, phone, or tablet
		 */
		public Nav(OLLMfiles.ProjectManager manager, Form form)
		{
			Object(
				orientation: Gtk.Orientation.HORIZONTAL,
				spacing: 0,
				hexpand: true,
				valign: Gtk.Align.START,
				visible: false,
				manager: manager,
				form: form,
				project: new OLLMfiles.Folder(manager)
			);
			this.file_list = new List(this.form == Form.TABLET);
			this.search_home = this.project;
			this.level = this.project;
			if (this.form != Form.DESKTOP) {
				this.path_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
					hexpand = true,
					valign = Gtk.Align.CENTER,
					css_classes = { "horizontal", "path-box" },
				};
			}
			this.label = new Gtk.Label("Select file") {
				xalign = 0,
				halign = Gtk.Align.START,
				hexpand = true,
			};
			switch (this.form) {
				case Form.PHONE:
					this.label.ellipsize = Pango.EllipsizeMode.END;
					break;

				default:
					this.label.ellipsize = Pango.EllipsizeMode.START;
					break;
			}
			var face = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			face.append(new Gtk.Image.from_icon_name("text-x-generic"));
			face.append(this.label);
			this.button = new Gtk.Button() {
				child = face,
				hexpand = true,
				valign = Gtk.Align.CENTER,
			};
			this.button.add_css_class("flat");
			this.folder_tree.selected.connect((folder) => {
				this.file_list.load(folder);
			});
			this.folder_tree.cleared.connect(() => {
				this.file_list.clear();
			});
			this.file_list.file_activated.connect((file) => {
				this.choose(file);
			});
			this.manager.rpc.notification.connect((notif) => {
				if (notif.method != "event.filesystem.scan_end") {
					return;
				}
				if (!this.project.is_project) {
					return;
				}
				if (notif.args.get(0).get_string() != this.project.path) {
					return;
				}
				this.folder_tree.folders.loaded.remove(this.project.path);
				this.folder_tree.folders.load.begin(this.project);
			});
			this.documents = new Gtk.ToggleButton() {
				icon_name = "x-office-document-symbolic",
				tooltip_text = "Documents",
				can_focus = false,
				valign = Gtk.Align.CENTER,
				margin_start = 6,
				margin_end = 6,
				visible = false,
				css_classes = { "flat" },
			};
			this.code = new Gtk.ToggleButton() {
				icon_name = "completion-snippet-symbolic",
				tooltip_text = "Code",
				can_focus = false,
				valign = Gtk.Align.CENTER,
				visible = false,
				css_classes = { "flat" },
			};
			var type_sync = false;
			this.documents.toggled.connect(() => {
				if (type_sync) {
					return;
				}
				type_sync = true;
				if (this.documents.active) {
					this.code.active = false;
				}
				type_sync = false;
				this.folder_tree.kind = this.documents.active ? Folder.FileKind.DOCUMENT : Folder.FileKind.ANY;
				this.file_list.kind = this.folder_tree.kind;
			});
			this.code.toggled.connect(() => {
				if (type_sync) {
					return;
				}
				type_sync = true;
				if (this.code.active) {
					this.documents.active = false;
				}
				type_sync = false;
				this.folder_tree.kind = this.code.active ? Folder.FileKind.CODE : Folder.FileKind.ANY;
				this.file_list.kind = this.folder_tree.kind;
			});
			this.notify["project"].connect(() => {
				if (!this.project.is_project) {
					return;
				}
				this.path_text = "Select file";
				this.label.label = this.path_text;
				this.button.tooltip_text = "";
				this.visible = true;
			});
		}

		/**
		 * Show the phone or tablet location as folder-name buttons
		 * with a slash between them. Each button stores its folder.
		 * A click opens that folder. The walk follows parent and
		 * stops at the open project. Buttons that already match
		 * stay. A step down adds one. A step up removes one.
		 * Once the row has a width, folders after the project show
		 * as ''...'' from the second folder until the buttons and
		 * slashes fit. The project name stays. A tap on ''...''
		 * still opens that folder.
		 */
		protected void render_crumbs()
		{
			if (this.fitting_crumbs) {
				return;
			}
			this.fitting_crumbs = true;
			this.crumbs_shortened = false;
			var above = new Gee.ArrayList<OLLMfiles.Folder>();
			var walk = this.level;
			while (true) {
				above.add(walk);
				if (walk.parent == null || walk.id == this.project.id) {
					break;
				}
				walk = walk.parent;
			}
			var want = above.size - 1;
			var child = this.path_box.get_first_child();
			while (child != null && want >= 0) {
				if (!(child is Gtk.Button)) {
					child = child.get_next_sibling();
					continue;
				}
				var stored = ((Gtk.Button) child).get_data<OLLMfiles.Folder>("folder");
				if (stored != above.get(want)) {
					break;
				}
				want--;
				child = child.get_next_sibling();
			}
			var drop = child;
			if (drop != null) {
				var prev = drop.get_prev_sibling();
				if (prev != null && !(prev is Gtk.Button)) {
					drop = prev;
				}
			}
			while (drop != null) {
				var next = drop.get_next_sibling();
				this.path_box.remove(drop);
				drop = next;
			}
			while (want >= 0) {
				if (this.path_box.get_first_child() != null) {
					this.path_box.append(new Gtk.Label("/") {
						valign = Gtk.Align.CENTER,
						css_classes = { "body", "list-chat-title" },
					});
				}
				var target = above.get(want);
				var crumb = new Gtk.Button.with_label(target.path_basename) {
					can_focus = false,
					valign = Gtk.Align.CENTER,
					css_classes = { "flat", "body", "list-chat-title" },
				};
				crumb.set_data<OLLMfiles.Folder>("folder", target);
				this.path_box.append(crumb);
				want--;
			}
			var avail = this.path_box.get_width();
			if (avail <= 1) {
				this.fitting_crumbs = false;
				return;
			}
			this.fitted_width = avail;
			child = this.path_box.get_first_child();
			while (child != null) {
				if (!(child is Gtk.Button)) {
					child = child.get_next_sibling();
					continue;
				}
				var named = (Gtk.Button) child;
				var folder = named.get_data<OLLMfiles.Folder>("folder");
				if (named.label != folder.path_basename) {
					named.label = folder.path_basename;
				}
				child = child.get_next_sibling();
			}
			var total = 0;
			var n = 0;
			var min_w = 0;
			var nat_w = 0;
			child = this.path_box.get_first_child();
			while (child != null) {
				child.measure(Gtk.Orientation.HORIZONTAL, -1,
					out min_w, out nat_w, null, null);
				total += nat_w;
				n++;
				child = child.get_next_sibling();
			}
			if (n > 1) {
				total += (n - 1) * this.path_box.spacing;
			}
			var index = 0;
			child = this.path_box.get_first_child();
			while (child != null && total > avail) {
				if (!(child is Gtk.Button)) {
					child = child.get_next_sibling();
					continue;
				}
				index++;
				if (index == 1) {
					child = child.get_next_sibling();
					continue;
				}
				var narrow = (Gtk.Button) child;
				narrow.measure(Gtk.Orientation.HORIZONTAL, -1,
					out min_w, out nat_w, null, null);
				var wide = nat_w;
				narrow.label = "...";
				this.crumbs_shortened = true;
				narrow.measure(Gtk.Orientation.HORIZONTAL, -1,
					out min_w, out nat_w, null, null);
				total -= wide - nat_w;
				child = child.get_next_sibling();
			}
			this.fitting_crumbs = false;
		}

		/**
		 * Fetch one file page into a list. A newer fetch for the
		 * same slot drops this reply. Directories are left out.
		 * Recent drops a file with no last view. The first row is
		 * marked for the keyboard.
		 *
		 * @param query Daemon filter. Empty browses the project.
		 * @param files Store the list box is bound to
		 * @param list List box that shows the store
		 * @param epoch Generation captured when the fetch started
		 * @param slot Recent list or the pullout page
		 */
		protected void load(string query, GLib.ListStore files, Gtk.ListBox list, int epoch, Slot slot)
		{
			this.project.fetch_files.begin(50, query, {}, false,
				slot == Slot.HISTORY, (obj, res) => {
				//FIXME - wrong way to do this..
				if (epoch != (slot == Slot.HISTORY ? this.history_epoch : this.pullout_epoch)) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.project.fetch_files.end(res);
				} catch (GLib.Error e) {
					GLib.warning("file list failed: %s", e.message);
					return;
				}
				files.remove_all();
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					var rows = (Gee.ArrayList<GLib.Object>) response.retval.get_object();
					foreach (var row in rows) {
						var file = (OLLMfiles.FileBase) row;
						if (file.base_type == "d" || file.base_type == "da") {
							continue;
						}
						if (slot == Slot.HISTORY && file.last_viewed < 1) {
							continue;
						}
						if (row is OLLMfiles.File) {
							files.append((OLLMfiles.File) row);
							continue;
						}
						var made = new OLLMfiles.File(file.manager);
						made.copy_from(file, { "manager" });
						files.append(made);
					}
				}
				if (files.get_n_items() < 1) {
					return;
				}
				var first = list.get_row_at_index(0);
				if (first == null || !first.activatable) {
					return;
				}
				first.add_css_class("selector-mark");
			});
		}

		/**
		 * Apply one search reply to the folder tree.
		 *
		 * A stale reply is dropped.
		 * {@link OLLMrpc.RpcErrorCode.TOO_MANY_RESULTS} leaves the tree
		 * unfiltered and shows ''too many results'' on the file list.
		 * An empty return is ''no results'' on that same list, and
		 * the tree is reset. The current file button stays.
		 * The reply is native-endian int32 folder ids. A match is
		 * ''true''. The walk stops at a parent already on the map.
		 * Any other parent is ''false'',
		 * and that folder's ''is-show-empty'' is set.
		 *
		 * @param epoch Search generation captured when the fetch started
		 * @param res Async result from {@link OLLMfiles.Folder.fetch_files}
		 */
		protected void on_load_results(int epoch, GLib.AsyncResult res)
		{
			if (epoch != this.search_epoch) {
				return;
			}
			OLLMrpc.Response response;
			try {
				response = this.project.fetch_files.end(res);
			} catch (GLib.Error e) {
				if (!(e is OLLMrpc.RpcErrorCode.TOO_MANY_RESULTS)) {
					GLib.warning("file search failed: %s", e.message);
					return;
				}
				this.folder_tree.search_reset();
				this.folder_tree.filter.changed(Gtk.FilterChange.DIFFERENT);
				this.label.label = this.path_text;
				this.file_list.notice = "too many results";
				return;
			}
			if (response.retval.type() == GLib.Type.INVALID) {
				this.folder_tree.search_reset();
				this.folder_tree.filter.changed(Gtk.FilterChange.DIFFERENT);
				this.label.label = this.path_text;
				this.file_list.notice = "no results";
				return;
			}
			var blob = (GLib.Bytes) response.retval.get_boxed();
			var ids = new int[(int) (blob.get_size() / sizeof(int))];
			if (ids.length > 0) {
				GLib.Memory.copy(ids, blob.get_data(), blob.get_size());
			}
			this.folder_tree.search_reset();
			this.folder_tree.searching = true;
			this.label.label = this.path_text;
			this.file_list.notice = "";
			for (var i = 0; i < ids.length; i++) {
				var id = ids[i];
				if (!this.folder_tree.folders.id_map.has_key(id)) {
					continue;
				}
				var match = this.folder_tree.folders.id_map.get(id);
				this.folder_tree.visible.set(id, true);
				if (match.is_show_empty) {
					match.is_show_empty = false;
					match.notify_property("css-classes");
				}
				id = (int) match.parent_id;
				while (id > 0 && this.folder_tree.folders.id_map.has_key(id)) {
					// check the visible map next
					if (this.folder_tree.visible.has_key(id)) {
						break;
					}
					var parent = this.folder_tree.folders.id_map.get(id);
					this.folder_tree.visible.set(id, false);
					parent.is_show_empty = true;
					parent.notify_property("css-classes");
					id = (int) parent.parent_id;
				}
			}
			this.folder_tree.filter.changed(Gtk.FilterChange.DIFFERENT);
		}

		/**
		 * Open a chosen file.
		 *
		 * Phone shows the file name. Desktop and tablet show the path
		 * under the project, and the button tooltip is that full path.
		 * The sheet and the pull-over close themselves.
		 *
		 * @param file File the user activated
		 */
		protected void choose(OLLMfiles.File file)
		{
			var shown = file.path_basename;
			if (this.form != Form.PHONE && this.project.path.length > 0
				&& file.path.has_prefix(this.project.path + "/")) {
				shown = file.path.substring(this.project.path.length + 1);
			}
			this.path_text = shown;
			this.label.label = this.path_text;
			if (this.form != Form.PHONE) {
				this.button.tooltip_text = file.path;
			}
			this.manager.activate_file(file);
			this.chosen(file);
			if (this.form != Form.DESKTOP) {
				return;
			}
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
	}
}
