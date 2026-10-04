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
	 * One-minute window that shows a PIN while a device pairs.
	 *
	 * {@link open} draws a new six-digit PIN and a line that counts
	 * down from sixty seconds. {@link result} toasts
	 * ''number rejected'' or closes after one device pairs.
	 * The title bar closes the dialog. {@link pairing} is true
	 * only while the dialog is open.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var pair = new OLLMapp.SettingsDialog.PairingDialog(page);
	 * pair.open();
	 * pair.result("rejected");
	 * }}}
	 */
	public class PairingDialog : Adw.Dialog
	{
		/**
		 * Connections tab that owns this dialog.
		 *
		 * Toasts, the listen socket, and the parent window
		 * are read from this page.
		 */
		private unowned ConnectionsPage page;

		private OLLMrpc.Transport.PairPublish publish;

		/**
		 * Six digits the phone must type. Empty until {@link open}.
		 */
		public string pin { get; private set; default = ""; }

		/**
		 * True while this dialog is counting down.
		 */
		public bool pairing { get; private set; default = false; }

		private Gtk.Label pin_label;
		private Gtk.ProgressBar line;
		private uint tick_id = 0;
		private int remaining = 60;

		/**
		 * @param page Connections tab that owns this dialog
		 */
		public PairingDialog(ConnectionsPage page)
		{
			Object(title: "Allow New Device");
			this.page = page;
			this.publish = new OLLMrpc.Transport.PairPublish();
			this.publish.failed.connect(() => {
				this.page.toast_overlay.add_toast(new Adw.Toast(
					"Could not publish the pairing service"));
			});
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			box.append(new Adw.HeaderBar());
			var body = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24
			};
			this.pin_label = new Gtk.Label("") {
				halign = Gtk.Align.CENTER,
				css_classes = { "pairing-pin" }
			};
			body.append(this.pin_label);
			this.line = new Gtk.ProgressBar() {
				fraction = 1,
				hexpand = true
			};
			body.append(this.line);
			box.append(body);
			this.set_child(box);
			this.set_content_width(560);
			this.closed.connect(() => {
				if (this.tick_id == 0) {
					return;
				}
				GLib.Source.remove(this.tick_id);
				this.tick_id = 0;
				this.pairing = false;
				this.arm("");
				this.publish.stop();
			});
		}

		/**
		 * Show a new PIN and start the sixty-second line.
		 *
		 * Host ''0.0.0.0'' publishes
		 * {@link OLLMrpc.Transport.TcpListen.ifaces}. Any other
		 * host publishes that one address.
		 */
		public void open()
		{
			if (this.tick_id != 0) {
				GLib.Source.remove(this.tick_id);
				this.tick_id = 0;
			}
			var n = GLib.Random.int_range(0, 1000000);
			this.pin = "%06d".printf(n);
			this.pin_label.label = this.pin;
			this.remaining = 60;
			this.line.fraction = 1;
			this.pairing = true;
			this.arm(this.pin);
			var socket = this.page.dialog.app.config.filesd.socket;
			var colon = socket.last_index_of(":");
			if (colon > 0) {
				var host = socket.substring(0, colon);
				var parsed = 0;
				int.try_parse(socket.substring(colon + 1), out parsed);
				if (parsed >= 1024 && parsed <= 65535) {
					string[] addrs = {};
					if (host == "0.0.0.0") {
						addrs = OLLMrpc.Transport.TcpListen.ifaces();
					}
					if (host != "" && host != "0.0.0.0") {
						addrs = { host };
					}
					this.publish.start(addrs, (uint16) parsed);
				}
			}
			this.present(this.page.dialog);
			this.tick_id = GLib.Timeout.add_seconds(1, () => {
				this.remaining -= 1;
				this.line.fraction = this.remaining / 60.0;
				if (this.remaining > 0) {
					return true;
				}
				this.tick_id = 0;
				this.pairing = false;
				this.arm("");
				this.publish.stop();
				this.close();
				return false;
			});
		}

		/**
		 * Apply one ''event.pair'' result.
		 *
		 * ''rejected'' toasts ''number rejected'' and leaves the PIN
		 * up. ''done'' clears the daemon PIN, withdraws mDNS, and
		 * closes.
		 *
		 * @param action ''rejected'' or ''done''
		 */
		public void result(string action)
		{
			switch (action) {
				case "rejected":
					this.page.toast_overlay.add_toast(new Adw.Toast("number rejected"));
					return;
				case "done":
					this.arm("");
					this.publish.stop();
					this.pairing = false;
					if (this.tick_id != 0) {
						GLib.Source.remove(this.tick_id);
						this.tick_id = 0;
					}
					this.close();
					return;
				default:
					return;
			}
		}

		/**
		 * Send ''pin'' to {@link OLLMfilesd.ClientCert.pair}.
		 *
		 * Empty clears the window. A failed arm while a PIN is
		 * showing toasts ''Could not start pairing''.
		 *
		 * @param pin six digits, or empty
		 */
		private void arm(string pin)
		{
			var mgr = this.page.dialog.parent.project_manager;
			if (mgr == null) {
				if (pin == "") {
					return;
				}
				this.page.toast_overlay.add_toast(new Adw.Toast("Could not start pairing"));
				return;
			}
			mgr.rpc.call.begin(new OLLMrpc.Request() {
				method = "ClientCert.pair",
				args = OLLMrpc.args("s", pin)
			}, (obj, res) => {
				try {
					mgr.rpc.call.end(res);
				} catch (GLib.Error e) {
					if (pin == "") {
						return;
					}
					this.page.toast_overlay.add_toast(
						new Adw.Toast("Could not start pairing"));
				}
			});
		}
	}
}
