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

// Normally no using. FilesdClient.State.* without this is
// OLLMchat.Settings.FilesdClient.State.* at every site.
using OLLMchat.Settings;

namespace OLLMapp.SettingsDialog
{
	/**
	 * Connections tab content for settings dialog.
	 * 
	 * Manages server connections (add, remove, edit connection details).
	 * Uses Adw.PreferencesGroup with Gtk.ListBox for connection list.
	 * Editing is inline - no separate edit/update methods needed.
	 * 
	 * @since 1.0
	 */
	public class ConnectionsPage : SettingsPage
	{
		/**
		 * Reference to parent SettingsDialog (which has the app object)
		 */
		public MainDialog dialog { get; construct; }

		private Gtk.Button add_btn;
		private Gtk.ScrolledWindow scrolled_window;
		/**
		 * Overlay for toasts on this tab.
		 *
		 * Pairing and the connection dialogs add toasts here.
		 */
		public Adw.ToastOverlay toast_overlay { get; private set; }
		private Adw.PreferencesGroup group;
		private Gtk.Box boxed_list;
		private Gee.HashMap<string, ConnectionRow> rows {
			get; set; default = new Gee.HashMap<string, ConnectionRow>();
		}
		private Gee.ArrayList<Adw.ExpanderRow> approved_rows {
			get; set; default = new Gee.ArrayList<Adw.ExpanderRow>();
		}
		private ConnectionAdd add_dialog;
		private Gtk.Button add_file_btn;
		private FileConnectionAdd add_file_dialog;
		private FileConnectionRow? file_connection_row;
		private PairingDialog pairing_dialog;
		private bool pair_wired = false;
		private Gtk.Button allow_btn;
#if !ANDROID && !G_OS_WIN32
		private FileServerRow file_server_row;
#endif
		private bool updating_defaults = false;

		/**
		 * Creates a new ConnectionsPage.
		 * 
		 * @param dialog Parent SettingsDialog (which has the app object)
		 */
		public ConnectionsPage(MainDialog dialog)
		{
			Object(
				dialog: dialog,
				page_name: "connections",
				page_title: "Connections",
				page_icon: "network-server-symbolic",
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0
			);
			
			// Create horizontal action bar (set as action_widget for SettingsDialog to manage)
			this.action_widget = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				hexpand = true
			};

			var llm_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			llm_box.append(new Gtk.Image.from_icon_name("list-add-symbolic"));
			var llm_label = new Gtk.Label("LLM Connection") {
				ellipsize = Pango.EllipsizeMode.END,
				hexpand = true
			};
			llm_box.append(llm_label);
			this.add_btn = new Gtk.Button() {
				child = llm_box,
				hexpand = true,
				css_classes = {"suggested-action"}
			};
			this.add_btn.clicked.connect(() => {
				this.add_dialog.show_add();
				this.add_dialog.present(this.dialog);
			});
			this.action_widget.append(this.add_btn);

			var desktop_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			desktop_box.append(new Gtk.Image.from_icon_name("list-add-symbolic"));
			var desktop_label = new Gtk.Label("Remote Desktop Connection") {
				ellipsize = Pango.EllipsizeMode.END,
				hexpand = true
			};
			desktop_box.append(desktop_label);
			this.add_file_btn = new Gtk.Button() {
				child = desktop_box,
				hexpand = true
			};
			this.add_file_btn.clicked.connect(() => {
				this.add_file_dialog.show_add();
				this.add_file_dialog.present(this.dialog);
			});
			this.action_widget.append(this.add_file_btn);

			// Create preferences group (no title; tab already shows "Connections")
			this.group = new Adw.PreferencesGroup();

			// Create boxed list for connections (using Box instead of ListBox to avoid hover styles)
			this.boxed_list = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.group.add(this.boxed_list);

			// Page has its own ScrolledWindow (no shared outer scroll)
			this.scrolled_window = new Gtk.ScrolledWindow() {
				vexpand = true,
				hexpand = true
			};
			this.scrolled_window.set_child(this.group);
			this.scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			this.toast_overlay = new Adw.ToastOverlay();
			this.toast_overlay.set_child(this.scrolled_window);
			this.append(this.toast_overlay);
			this.pairing_dialog = new PairingDialog(this);
			var allow_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			allow_box.append(new Gtk.Image.from_icon_name("list-add-symbolic"));
			var allow_label = new Gtk.Label("Allow New Device") {
				ellipsize = Pango.EllipsizeMode.END,
				hexpand = true
			};
			allow_box.append(allow_label);
			this.allow_btn = new Gtk.Button() {
				child = allow_box,
				hexpand = true,
				visible = false
			};
			this.allow_btn.clicked.connect(() => {
				this.pairing_dialog.open();
			});
			this.action_widget.append(this.allow_btn);

			// Create ConnectionAdd dialog
			this.add_dialog = new ConnectionAdd();
			this.add_dialog.dialog_closed.connect(() => {
				if (this.add_dialog.verified_connection == null) {
					return;
				}
				this.dialog.app.config.connections.set(
					this.add_dialog.verified_connection.url,
					this.add_dialog.verified_connection
				);
				this.render_connections();
				this.dialog.app.config.save();
			});

			this.add_file_dialog = new FileConnectionAdd();
			this.add_file_dialog.dialog_closed.connect(() => {
				if (this.add_file_dialog.registered_url == null) {
					this.render_file_connection();
					return;
				}
				this.dialog.app.config.filesd_client.url = this.add_file_dialog.registered_url;
				this.dialog.app.config.filesd_client.addresses =
					this.add_file_dialog.registered_addresses;
				this.dialog.app.config.filesd_client.server_id =
					this.add_file_dialog.server_id;

				//FIXME =- this ifdef does not make sense - why not do the same thing on desktop
#if ANDROID
				/* The Android pairing hello uses a temporary TLS stream.
				 * Connect the persistent RPC before exposing Agent Pi. */
				this.dialog.app.config.filesd_client.state = FilesdClient.State.ENABLED;
#else
				this.dialog.app.config.filesd_client.state = FilesdClient.State.SOCKET;
#endif
				this.dialog.app.config.save();
				this.render_file_connection();
#if ANDROID
				this.dialog.parent.reconnect.begin();
#endif
			});
			this.add_file_dialog.error_occurred.connect((error_message) => {
				this.toast_overlay.add_toast(new Adw.Toast(error_message) {
					timeout = 5
				});
				this.add_file_dialog.present(this.dialog);
				GLib.Idle.add(() => {
					this.add_file_dialog.can_close = true;
					return false;
				});
			});

			// Initial render of connections
#if !ANDROID && !G_OS_WIN32
			this.file_server_row = new FileServerRow(
				this.dialog.app.config.filesd,
				this.dialog.parent,
				this.toast_overlay);
			this.boxed_list.append(this.file_server_row.expander);
			this.arrow(this.file_server_row.expander, this.file_server_row.expander);
#endif
			this.render_connections();
			this.render_approved.begin();
		}

		/**
		 * Tests connection and saves to config on success.
		 *
		 * @param url Connection URL to verify
		 */
		private async void verify_connection(string url)
		{
			var row = this.rows.get(url);
			var newUrl = row.urlEntry.text.strip();

			if (newUrl == "") {
				return;
			}

			var newName = row.nameEntry.text.strip();
			var test_connection = new OLLMchat.Settings.Connection() {
				name = newName != "" ? newName : newUrl,
				url = newUrl
			};
			row.apply_config(test_connection);
			if (!test_connection.url.has_prefix("http://") && !test_connection.url.has_prefix("https://")) {
				test_connection.url = "https://" + test_connection.url;
			}
			newUrl = test_connection.url;
#if ANDROID
			AndroidConnectionConfigTls.apply_to_connection(test_connection);
#endif

			var original_timeout = test_connection.timeout;
			test_connection.timeout = 5;
			var connect_error = "";
			try {
				var models_call = new OLLMchat.Call.Models(test_connection);
				var models = yield models_call.exec_models();
				GLib.debug("Connection verified, found %d models", models.size);
			} catch (Error e) {
				connect_error = e.message;
			}

			if (connect_error != "") {
				if (!(yield test_connection.try_api())) {
					test_connection.timeout = original_timeout;
					GLib.warning("Failed to verify connection: " + connect_error);
					return;
				}
				if (newName == "") {
					test_connection.name = test_connection.url;
				}
			}

			yield test_connection.detect_ollama();

			if (test_connection.ollama_native != 1) {
				var prev_url = test_connection.url;
				if (yield test_connection.try_api()) {
					yield test_connection.detect_ollama();
					if (test_connection.ollama_native == 1 && newName == "") {
						test_connection.name = test_connection.url;
					}
				}
				if (test_connection.ollama_native != 1) {
					test_connection.url = prev_url;
					test_connection.ollama_native = 0;
				}
			}

			test_connection.timeout = original_timeout;
			newUrl = test_connection.url;
			row.nameEntry.grab_focus();
			row.urlEntry.text = newUrl;
			row.url = newUrl;

			if (newUrl != url) {
				this.dialog.app.config.connections.unset(url);
				this.dialog.app.config.connections.set(newUrl, test_connection);
				this.rows.set(newUrl, row);
				this.rows.unset(url);
			}
			if (newUrl == url) {
				this.dialog.app.config.connections.set(url, test_connection);
			}

			row.expander.title = "LLM: " + test_connection.name;
			row.expander.subtitle = "";
			row.clearUnverified();
			this.dialog.app.config.save();
		}

		/**
		 * Removes connection from config.connections map and updates visibility of Remove buttons.
		 * Hides Remove button if only one connection left.
		 * 
		 * @param url Connection URL to remove
		 */
		private void remove_connection(string url)
		{
			if (this.dialog.app.config.connections.size <= 1) {
				return; // Cannot remove last connection
			}

			this.dialog.app.config.connections.unset(url);
			this.render_connections();
			this.dialog.app.config.save();
		}

		public void render_connections()
		{
			var can_remove = this.dialog.app.config.connections.size > 1;

			// Find and remove connections that no longer exist in config
			var urls_to_remove = new Gee.ArrayList<string>();
			foreach (var entry in this.rows.entries) {
				if (!this.dialog.app.config.connections.has_key(entry.key)) {
					urls_to_remove.add(entry.key);
				}
			}

			foreach (var url in urls_to_remove) {
				this.rows.get(url).expander.unparent();
				this.rows.unset(url);
			}

			// Add new connections that don't have rows yet
			foreach (var entry in this.dialog.app.config.connections.entries) {
				if (!this.rows.has_key(entry.key)) {
					this.add_connection_row(entry.key, entry.value, can_remove);
					continue;
				}
				// Update Remove button visibility for existing row
				this.rows.get(entry.key).removeButton.visible = can_remove;
			}
			this.render_file_connection();
		}

		/**
		 * Move each expander arrow to the left of its title.
		 *
		 * The built-in arrow is ''adw-expander-arrow-symbolic'',
		 * which this icon theme does not ship, so it draws as a
		 * broken image on the right of switches. Collapsed uses
		 * ''pan-end-symbolic''. Expanded uses
		 * ''pan-down-symbolic''.
		 *
		 * @param widget Widget to walk, usually an expander
		 * @param row Expander that owns the arrow being moved
		 */
		private void arrow(Gtk.Widget widget, Adw.ExpanderRow row)
		{
			if (widget is Adw.ExpanderRow) {
				row = (Adw.ExpanderRow) widget;
			}
			if (widget.has_css_class("expander-row-arrow")) {
				var image = (Gtk.Image) widget;
				image.unparent();
				image.remove_css_class("expander-row-arrow");
				image.valign = Gtk.Align.CENTER;
				image.icon_name = row.expanded ? "pan-down-symbolic" : "pan-end-symbolic";
				row.add_prefix(image);
				row.notify["expanded"].connect(() => {
					image.icon_name = row.expanded ? "pan-down-symbolic" : "pan-end-symbolic";
				});
				return;
			}
			var child = widget.get_first_child();
			while (child != null) {
				var next = child.get_next_sibling();
				this.arrow(child, row);
				child = next;
			}
		}

		/**
		 * Adds a single connection row to the UI.
		 * 
		 * @param url Connection URL (key in config.connections map)
		 * @param connection Connection object
		 * @param can_remove Whether Remove button should be visible
		 */
		private void add_connection_row(string url, OLLMchat.Settings.Connection connection, bool can_remove)
		{
			var row = new ConnectionRow(connection, url, can_remove);

			row.remove_requested.connect(() => {
				this.remove_connection(row.url);
			});
			row.verify_requested.connect(() => {
				this.verify_connection.begin(row.url);
			});
			row.defaultSwitch.notify["active"].connect(() => {
				this.on_default_changed(row.url, row.defaultSwitch.active);
			});

			this.rows.set(url, row);
			this.arrow(row.expander, row.expander);
			this.boxed_list.append(row.expander);
		}

		/**
		 * Load approved client certs and render each as a read-only expander.
		 *
		 * @since 1.0
		 */
		public async void render_approved()
		{
			var win = this.dialog.parent;
			if (win == null || win.project_manager == null) {
				return;
			}
			OLLMrpc.Response response;
			try {
				response = yield win.project_manager.rpc.call(
					new OLLMrpc.Request() {
						method = "ClientCert.approved_certs"
					});
			} catch (GLib.Error e) {
				GLib.debug("approved_certs failed: %s", e.message);
				return;
			}
			foreach (var row in this.approved_rows) {
				this.boxed_list.remove(row);
			}
			this.approved_rows.clear();
			if (response.retval.type() == GLib.Type.INVALID) {
				return;
			}
		var clients = (Gee.ArrayList<OLLMapp.ClientCert>) response.retval.get_object();
		var n = 0;
		foreach (var client in clients) {
			n++;
			var row = new ApprovedClientRow(client, n);
			row.remove_requested.connect(() => {
				this.remove_approved.begin(row.id);
			});
			this.approved_rows.add(row.expander);
			this.arrow(row.expander, row.expander);
			this.boxed_list.append(row.expander);
		}
		}

		private async void remove_approved(int64 id)
		{
			var win = this.dialog.parent;
			if (win == null || win.project_manager == null) {
				return;
			}
			try {
				yield win.project_manager.rpc.call(new OLLMrpc.Request() {
					method = "ClientCert.client_cert",
					args = OLLMrpc.args("sx", "remove", id)
				});
			} catch (GLib.Error e) {
				GLib.debug("client_cert remove failed: %s", e.message);
				return;
			}
			this.render_approved.begin();
		}

		/**
		 * Called when a connection's default switch is toggled.
		 * 
		 * Applies config from UI, then ensures only one connection is default.
		 * If unsetting default and this is the only connection, it will be set back to default.
		 *
		 * @param url Connection URL
		 * @param is_default Whether this connection should be default
		 */
		private void on_default_changed(string url, bool is_default)
		{
			// Prevent recursion when we update other switches
			if (this.updating_defaults) {
				return;
			}

			var row = this.rows.get(url);
			var connection = this.dialog.app.config.connections.get(url);

			// Apply config from UI first
			row.apply_config(connection);

			// If unsetting default and this is the only connection, set it back to default
			if (!is_default && this.dialog.app.config.connections.size == 1) {
				this.updating_defaults = true;
				connection.is_default = true;
				row.defaultSwitch.active = true;
				this.updating_defaults = false;
				return;
			}

			// Update other connections based on the new state
			this.updating_defaults = true;
			var found_first = false;
			foreach (var entry in this.dialog.app.config.connections.entries) {
				if (entry.key == url) {
					continue;
				}

				if (is_default) {
					// Setting this as default: clear all other connections
					entry.value.is_default = false;
					if (this.rows.has_key(entry.key)) {
						this.rows.get(entry.key).defaultSwitch.active = false;
					}
					continue;
				}

				if (found_first) {
					continue;
				}
				
				// Unsetting default: set the first other connection as default
				entry.value.is_default = true;
				if (this.rows.has_key(entry.key)) {
					this.rows.get(entry.key).defaultSwitch.active = true;
				}
				found_first = true;
			}
			this.updating_defaults = false;
		}

		private void render_file_connection()
		{
			this.add_file_btn.visible =
				this.dialog.app.config.filesd_client.url.strip() == "";
			if (this.file_connection_row != null) {
				this.file_connection_row.expander.unparent();
				this.file_connection_row = null;
			}
			var client = this.dialog.app.config.filesd_client;
			if (client.url.strip() == "") {
				return;
			}
			this.file_connection_row = new FileConnectionRow(client, this.dialog.parent);
			this.arrow(this.file_connection_row.expander, this.file_connection_row.expander);
			this.file_connection_row.remove_requested.connect(() => {
				var was_live = client.state == FilesdClient.State.LIVE
					|| client.state == FilesdClient.State.SOCKET;
#if !ANDROID
				var row = this.file_connection_row;
#endif
				/* AgentDropdown listens to this object. Mutating its state
				 * notifies the filter before the connection data is cleared. */
				client.state = FilesdClient.State.REQUESTED;
				client.url = "";
				client.addresses = "";
				client.server_id = "";
				this.render_file_connection();
				this.dialog.app.config.save();
				if (!was_live) {
					return;
				}
#if ANDROID
				/* Android has no local file daemon to reconnect after removal.
				 * Drop the remote RPC state and return to Chatter. */
				var data_dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat");
				this.dialog.parent.project_manager.replace_rpc(
					new OLLMrpc.Client(data_dir, "ollmfilesd.pid", "ollmfilesd.sock"));
				var empty = this.dialog.parent.history_manager.create_new_session();
				empty.project_path = this.dialog.parent.history_manager.session.project_path;
				empty.agent_name = "chatter";
				this.dialog.parent.chat_widget.switch_to_session.begin(empty);
#else
				row.reconnect.begin(false);
#endif
			});
			Adw.ExpanderRow? insert_after = null;
			foreach (var row in this.rows.values) {
				insert_after = row.expander;
			}
			if (insert_after != null) {
				this.boxed_list.insert_child_after(
					this.file_connection_row.expander, insert_after);
				return;
			}
			this.boxed_list.append(this.file_connection_row.expander);
		}

		/**
		 * Applies all connection row UI values to their corresponding connection objects.
		 */
		public void apply_config()
		{
			foreach (var entry in this.rows.entries) {
				entry.value.apply_config(this.dialog.app.config.connections.get(entry.key));
			}
#if !ANDROID && !G_OS_WIN32
			this.file_server_row.apply_config();
#endif
		}

		/**
		 * Fill Desktop server widgets from {@link OLLMchat.Settings.Config2.filesd}.
		 *
		 * Called when the settings dialog is shown, same moment as
		 * {@link ToolsPage.load_configs}. The first time a project
		 * manager exists, this also listens for ''event.pair''.
		 */
		public void load_config()
		{
#if !ANDROID && !G_OS_WIN32
			this.file_server_row.load_config();
			this.allow_btn.visible = this.file_server_row.running;
#endif
			if (this.pair_wired || this.dialog.parent.project_manager == null) {
				return;
			}
			this.pair_wired = true;
			this.dialog.parent.project_manager.notification.connect((notif) => {
				if (notif.method != "event.pair") {
					return;
				}
				this.pairing_dialog.result(notif.action);
			});
		}


	}
}
