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
	 * down from sixty seconds. {@link rejected} toasts
	 * ''number rejected'' and leaves that PIN up. {@link pairing}
	 * is true only while the dialog is open.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var pair = new OLLMapp.SettingsDialog.PairingDialog(page);
	 * pair.open();
	 * pair.rejected();
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
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24
			};
			this.pin_label = new Gtk.Label("") {
				halign = Gtk.Align.CENTER,
				css_classes = { "pairing-pin" }
			};
			box.append(this.pin_label);
			this.line = new Gtk.ProgressBar() {
				fraction = 1,
				hexpand = true
			};
			box.append(this.line);
			this.set_child(box);
			this.set_content_width(560);
			this.closed.connect(() => {
				if (this.tick_id == 0) {
					return;
				}
				GLib.Source.remove(this.tick_id);
				this.tick_id = 0;
				this.pairing = false;
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
				this.publish.stop();
				this.close();
				return false;
			});
		}

		/**
		 * Toast ''number rejected''. The PIN and the dialog stay.
		 */
		public void rejected()
		{
			this.page.toast_overlay.add_toast(new Adw.Toast("number rejected"));
		}
	}
}
