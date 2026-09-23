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
	 * Banner showing the newest pending client-cert registration with
	 * Accept / Reject / Ban. Lives on {@link MainDialog.action_bar_area}
	 * (same slot as {@link PullManagerBanner}).
	 *
	 * @since 1.0
	 */
	public class RegistrationBanner : Gtk.Box
	{
		public MainDialog dialog { get; construct; }

		private Gtk.Label label;
		private Gtk.Button accept_button;
		private Gtk.Button reject_button;
		private Gtk.Button ban_button;
		private int64 pending_id = 0;

		public RegistrationBanner(MainDialog dialog)
		{
			Object(
				dialog: dialog,
				orientation: Gtk.Orientation.HORIZONTAL,
				spacing: 12,
				margin_start: 12,
				margin_end: 12,
				margin_top: 12,
				margin_bottom: 12,
				visible: false
			);
			this.label = new Gtk.Label("") {
				hexpand = true,
				xalign = 0,
				ellipsize = Pango.EllipsizeMode.END
			};
			this.append(this.label);
			this.accept_button = new Gtk.Button.with_label("Accept") {
				css_classes = {"suggested-action"}
			};
			this.accept_button.clicked.connect(() => {
				this.act.begin("accept");
			});
			this.append(this.accept_button);
			this.reject_button = new Gtk.Button.with_label("Reject");
			this.reject_button.clicked.connect(() => {
				this.act.begin("reject");
			});
			this.append(this.reject_button);
			this.ban_button = new Gtk.Button.with_label("Ban") {
				css_classes = {"destructive-action"}
			};
			this.ban_button.clicked.connect(() => {
				this.act.begin("ban");
			});
			this.append(this.ban_button);
		}

		/**
		 * Reload the newest pending row into the banner; hide when none.
		 */
		public async void refresh()
		{
			var win = this.dialog.parent;
			if (win == null || win.project_manager == null) {
				return;
			}
			OLLMrpc.Response response;
			try {
				response = yield win.project_manager.rpc.call(
					new OLLMrpc.Request() {
						method = "RPC-ClientCert.pending_cert"
					});
			} catch (GLib.Error e) {
				GLib.debug("pending_cert failed: %s", e.message);
				return;
			}
			if (response.retval.type() == GLib.Type.INVALID) {
				return;
			}
			var pending = (OLLMapp.ClientCert) response.retval.get_object();
			this.pending_id = pending.id;
			if (pending.id == 0) {
				this.visible = false;
				return;
			}
			var short_fp = pending.fingerprint.length > 12
				? pending.fingerprint.substring(0, 12) : pending.fingerprint;
			var when = new GLib.DateTime.from_unix_local(pending.created)
				.format("%H:%M");
			var who = pending.requester != "" ? pending.requester : "unknown";
			this.label.label = "Pending: %s — %s — fp %s — %s".printf(
				who, pending.ip, short_fp, when);
			this.visible = true;
		}

		private async void act(string action)
		{
			var win = this.dialog.parent;
			if (win == null || win.project_manager == null || this.pending_id == 0) {
				return;
			}
			try {
				yield win.project_manager.rpc.call(new OLLMrpc.Request() {
					method = "RPC-ClientCert.client_cert",
					args = OLLMrpc.args("sx", action, this.pending_id)
				});
			} catch (GLib.Error e) {
				GLib.debug("client_cert %s failed: %s", action, e.message);
				return;
			}
			this.refresh.begin();
			if (action != "accept") {
				return;
			}
			this.dialog.connections_page.render_approved.begin();
			win.notification(new OLLMrpc.Notification() {
				method = "Banner.show",
				message = "Device approved — on the phone, tap Check on the file connection"
			});
		}
	}
}
