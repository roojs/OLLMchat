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

namespace OLLMapp.SettingsDialog
{
	/**
	 * Projects tab content for settings dialog.
	 * Lists projects from ProjectManager, search/filter, Add and Remove.
	 * List view is built in the constructor with a dummy empty model; the real
	 * store is bound when the dialog is shown via ensure_loaded() (called once).
	 */
	public class ProjectsPage : SettingsPage
	{
		public MainDialog dialog { get; construct; }

		private Gtk.ListView list_view;
		private Gtk.FilterListModel filtered_projects;
		private Gtk.SortListModel sorted_projects;
		private Gtk.SingleSelection selection_model;
		private Gtk.SearchBar search_bar;
		private Gtk.SearchEntry search_entry;
		private ProjectSearchFilter project_filter;
		private Gtk.Button add_btn;
		private Gtk.Button remove_btn;
		private bool is_loaded = false;
		private OLLMfiles.ProjectManager project_manager; // loaded in load_projects (which is when this is shown)

		public ProjectsPage(MainDialog dialog)
		{
			Object(
				dialog: dialog,
				page_name: "projects",
				page_title: "Projects",
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0
			);

			this.project_filter = new ProjectSearchFilter();
			this.filtered_projects = new Gtk.FilterListModel(
				new GLib.ListStore(typeof(OLLMfiles.Folder)),
				this.project_filter
			);
			this.sorted_projects = new Gtk.SortListModel(
				this.filtered_projects,
				new Gtk.CustomSorter((a, b) => {
					var na = GLib.Path.get_basename((a as OLLMfiles.Folder).path).down();
					var nb = GLib.Path.get_basename((b as OLLMfiles.Folder).path).down();
					var c = GLib.strcmp(na, nb);
					return (c < 0) ? Gtk.Ordering.SMALLER : (c > 0) ? Gtk.Ordering.LARGER : Gtk.Ordering.EQUAL;
				})
			);
			this.selection_model = new Gtk.SingleSelection(this.sorted_projects) {
				autoselect = false,
				can_unselect = true,
				selected = Gtk.INVALID_LIST_POSITION
			};

			this.list_view = new Gtk.ListView(this.selection_model, null);
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				var row_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
					margin_start = 12,
					margin_end = 12,
					margin_top = 6,
					margin_bottom = 6
				};
				var name_label = new Gtk.Label("") {
					halign = Gtk.Align.START,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.END,
					css_classes = {"body"}
				};
				var path_label = new Gtk.Label("") {
					halign = Gtk.Align.END,
					hexpand = false,
					ellipsize = Pango.EllipsizeMode.MIDDLE,
					css_classes = {"caption", "dim-label"}
				};
				row_box.append(name_label);
				row_box.append(path_label);
				list_item.set_data<Gtk.Label>("name_label", name_label);
				list_item.set_data<Gtk.Label>("path_label", path_label);
				list_item.child = row_box;
			});
			factory.bind.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				list_item.get_data<Gtk.Label>("name_label").label =
					GLib.Path.get_basename((list_item.item as OLLMfiles.Folder).path);
				list_item.get_data<Gtk.Label>("path_label").label =
					(list_item.item as OLLMfiles.Folder).path;
			});
			this.list_view.factory = factory;

			this.selection_model.selection_changed.connect(this.on_selection_changed);

			// Page has its own ScrolledWindow (no shared outer scroll)
			var scrolled = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = true
			};
			scrolled.set_child(this.list_view);
			scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			this.append(scrolled);

			this.action_widget = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) { hexpand = true };
			this.search_bar = new Gtk.SearchBar();
			this.search_entry = new Gtk.SearchEntry() {
				placeholder_text = "Search Projects",
				hexpand = true
			};
			this.search_entry.bind_property(
				"text", this.project_filter, "query", GLib.BindingFlags.SYNC_CREATE);
			this.search_bar.connect_entry(this.search_entry);
			this.search_bar.set_child(this.search_entry);
			this.search_bar.set_key_capture_widget(this);
			this.search_bar.set_search_mode(true);
			this.action_widget.append(this.search_bar);
			this.add_btn = new Gtk.Button.with_label("Add");
			this.add_btn.clicked.connect(() => this.add_project());
			this.action_widget.append(this.add_btn);

			this.remove_btn = new Gtk.Button.with_label("Remove") {
				css_classes = { "destructive-action" },
				visible = false
			};
			this.remove_btn.clicked.connect(() => { this.on_remove_clicked.begin(); });
			this.action_widget.append(this.remove_btn);

			this.on_selection_changed();
		}

		/**
		 * Load projects from DB (if needed) and bind the list view to the real project store.
		 * Called when the Projects tab is shown (via map signal). ProjectManager is not available
		 * at dialog creation; projects are only loaded from DB when the code assistant is first
		 * used, so we trigger load_projects_from_db here when the user opens the Projects tab.
		 */
		public async void load_projects()
		{
			if (this.is_loaded) {
				return;
			}
			var win = this.dialog.parent as OllmchatWindow;
			if (win == null || win.project_manager == null) {
				return;
			}
			yield win.project_manager.load_projects_from_db();
			this.project_manager = win.project_manager;
			this.filtered_projects.model = win.project_manager.projects;
			this.is_loaded = true;
		}

		private void on_selection_changed()
		{
			var pos = this.selection_model.selected;
			this.remove_btn.visible = (pos != Gtk.INVALID_LIST_POSITION);
		}

		private async void on_remove_clicked()
		{
			var pos = this.selection_model.selected;
			if (pos == Gtk.INVALID_LIST_POSITION) {
				return;
			}
			var project = this.selection_model.get_item(pos) as OLLMfiles.Folder;
			var dialog = new Adw.AlertDialog(
				"Remove Project?",
				"This will remove the project from your list. The folder will no longer appear as a project.\n\n" +
				"No file or history data will be deleted.\n\n" +
				"Are you sure you want to remove this project?"
			);
			dialog.add_response("cancel", "Cancel");
			dialog.add_response("remove", "Remove");
			dialog.set_response_appearance("remove", Adw.ResponseAppearance.DESTRUCTIVE);
			var response = yield dialog.choose(this.dialog, null);
			if (response != "remove") {
				return;
			}
			this.project_manager.remove_project(project);
			
		}

		private void add_project()
		{
			var chooser = new Gtk.FileDialog() {
				title = "Add project folder",
				modal = true
			};
			// Use dialog's parent window (main app window that opened settings), same as ModelsPage/ModelRow
			var parent_window = (Gtk.Window) this.dialog.parent;
			chooser.select_folder.begin(parent_window, null, (obj, res) => {
				try {
					var file = chooser.select_folder.end(res);
					if (file == null) {
						return;
					}
					var path = file.get_path();
					var normalized = GLib.File.new_for_path(path).get_path();
					if (this.project_manager.projects.path_map.has_key(normalized)) {
						GLib.warning("Project already in list: %s", normalized);
						return;
					}
					this.project_manager.create_project(normalized);
				} catch (GLib.Error e) {
					// User cancelled or I/O error
				}
			});
		}
	}
}
