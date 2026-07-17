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
	 * Android settings dialog — Connections, Models, and Tools tabs.
	 *
	 * Same class name as desktop {@link MainDialog}; Android builds this file
	 * instead of {@code SettingsDialog/MainDialog.vala}.
	 *
	 * {@link Adw.ViewSwitcherPolicy.NARROW} shows tab icons only; icons must
	 * ship in {@code android/icons/manifest}.
	 *
	 * @since 1.0
	 */
	public class MainDialog : Adw.Dialog
	{
		public OLLMchat.ApplicationInterface app { get; construct; }

		public OllmchatWindow parent;

		private ConnectionsPage connections_page;
		private ModelsPage models_page;
		private ToolsPage tools_page;
		private Adw.ViewStack view_stack;
		public Gtk.Box action_bar_area { get; private set; }
		private SettingsPage previous_visible_child {
			get;
			set;
			default = new SettingsPage();
		}
		public PullManager pull_manager { get; private set; }
		private PullManagerBanner progress_banner;

		public MainDialog(OllmchatWindow parent)
		{
			Object(app: parent.app);
			this.parent = parent;
			this.title = "Settings";
			this.set_content_width(400);
			this.set_content_height(576);

			var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.view_stack = new Adw.ViewStack();
			var header_bar = new Adw.HeaderBar();
			header_bar.set_title_widget(new Adw.ViewSwitcher() {
				stack = this.view_stack,
				policy = Adw.ViewSwitcherPolicy.NARROW
			});
			main_box.append(header_bar);

			this.view_stack.vexpand = true;
			this.view_stack.hexpand = true;
			main_box.append(this.view_stack);

			this.pull_manager = new PullManager(this.app);
			this.progress_banner = new PullManagerBanner(this.pull_manager);

			this.action_bar_area = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				visible = false,
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 12
			};
			this.action_bar_area.prepend(this.progress_banner);
			this.progress_banner.visible = false;
			main_box.append(this.action_bar_area);

			this.set_child(main_box);

			this.connections_page = new ConnectionsPage(this);
			this.view_stack.add_titled(
				this.connections_page,
				this.connections_page.page_name,
				this.connections_page.page_title
			);
			this.view_stack.get_page(this.connections_page).icon_name = this.connections_page.page_icon;
			this.action_bar_area.append(this.connections_page.action_widget);
			this.connections_page.action_widget.visible = false;

			this.models_page = new ModelsPage(this);
			this.view_stack.add_titled(
				this.models_page,
				this.models_page.page_name,
				this.models_page.page_title
			);
			this.view_stack.get_page(this.models_page).icon_name = this.models_page.page_icon;
			this.action_bar_area.append(this.models_page.action_widget);
			this.models_page.action_widget.visible = false;

			this.tools_page = new ToolsPage(this);
			this.view_stack.add_titled(
				this.tools_page,
				this.tools_page.page_name,
				this.tools_page.page_title
			);
			this.view_stack.get_page(this.tools_page).icon_name = this.tools_page.page_icon;
			this.action_bar_area.append(this.tools_page.action_widget);
			this.tools_page.action_widget.visible = false;

			this.view_stack.notify["visible-child"].connect(this.on_page_changed);
			this.on_page_changed();
			this.closed.connect(this.on_closed);
		}

		private void on_page_changed()
		{
			this.previous_visible_child.action_widget.visible = false;
			var current_page = this.view_stack.get_visible_child() as SettingsPage;
			if (current_page == null) {
				return;
			}
			this.previous_visible_child = current_page;
			current_page.action_widget.visible = true;
			this.action_bar_area.visible = true;
		}

		/**
		 * Shows the settings dialog and initializes pages.
		 *
		 * @param page_name Page to open (e.g. "connections", "models"); empty for default tab
		 */
		public async void show_dialog(string page_name = "")
		{
			AndroidConnectionConfigTls.apply_to_config(this.app.config);

			var busy_dialog = new OLLMapp.BusyDialog(this.parent);
			busy_dialog.status_label.label = "Checking connection…";
			busy_dialog.present(this.parent);
			yield this.check_all_connections();
			busy_dialog.close();

			this.progress_banner.initialize_existing_pulls();

			if (page_name != "") {
				this.view_stack.set_visible_child_name(page_name);
			}

			this.connections_page.render_connections();

			this.tools_page.load_tools();
			this.tools_page.load_configs();

			this.present(this.parent);

			if (this.parent.history_manager != null) {
				this.models_page.connection_models =
					this.parent.history_manager.connection_models;
				this.models_page.render_models.begin();
			}
		}

		private void on_closed()
		{
			this.models_page.save_all_options();
			this.connections_page.apply_config();
			if (this.parent.history_manager != null) {
				var usage = this.parent.history_manager.default_model_usage;
				var default_model = this.app.config.usage.get (
					"default_model") as OLLMchat.Settings.ModelUsage;
				if (usage != null && default_model != null) {
					default_model.connection = usage.connection;
					default_model.model = usage.model;
					default_model.options = usage.options.clone ();
				}
			}
			this.check_all_connections.begin();
			(this.app as AndroidApplication).persist_config ();
			this.app.config.changed();
		}

		private async void check_all_connections()
		{
			AndroidConnectionConfigTls.apply_to_config(this.app.config);

			foreach (var entry in this.app.config.connections.entries) {
				var connection = entry.value;
				try {
					var original_timeout = connection.timeout;
					connection.timeout = 5;
					try {
						var models_call = new OLLMchat.Call.Models(connection);
						yield models_call.exec_models();
						connection.is_working = true;
					} finally {
						connection.timeout = original_timeout;
					}
				} catch (GLib.Error e) {
					connection.is_working = false;
					GLib.debug(
						"Connection %s is not working: %s",
						connection.url, e.message
					);
				}
			}
		}
	}
}

