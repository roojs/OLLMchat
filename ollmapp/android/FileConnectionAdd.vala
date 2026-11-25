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

[CCode (cheader_filename = "android-pair-browse.h")]
extern unowned string ollmapp_android_phone_label();

namespace OLLMapp.SettingsDialog
{
	/**
	 * Phone dialog for the outbound file-server connection.
	 *
	 * Listens for the pairing service, then asks for the twelve digits
	 * the desktop shows: the PIN, then its certificate check digits.
	 * UI follows the Argus ''Register'' phase model: one phase drives layout.
	 */
	public class FileConnectionAdd : Adw.PreferencesDialog
	{
		/**
		 * Pairing UI phase. Each value maps to a fixed widget layout in
		 * {@link apply_layout}.
		 */
		private enum Phase
		{
			IDLE,
			BROWSING,
			AWAITING_PIN,
			ENROLLING,
			/** Wrong or rejected PIN; keep the entry. */
			FAILED_PIN,
			/** Discovery or transport failure; hide the entry. */
			FAILED_LINK
		}

		/**
		 * ''tcp://host:port'' that answered hello. Null until then.
		 * {@link ConnectionsPage} reads this on {@link dialog_closed}.
		 */
		public string? registered_url { get; private set; }

		/**
		 * Every ''host:port'' from the reply, one per line.
		 */
		public string registered_addresses { get; private set; default = ""; }

		/**
		 * Desktop id from the pairing mDNS TXT record.
		 */
		public string server_id { get; private set; default = ""; }

		private Gtk.Label listen_label;
		private Gtk.Spinner browse_spinner;
		private Gtk.Entry pin_entry;
		private Gtk.Box pin_box;
		private Gtk.Button request_button;
		private Adw.PreferencesGroup group;
		private Phase phase = Phase.IDLE;
		private string status_detail = "";
		private string found = "";
		private uint browse_id = 0;
		private uint pin_auto_id = 0;

		public signal void error_occurred(string error_message);
		public signal void dialog_closed();

		public FileConnectionAdd()
		{
			this.title = "Add Remote Desktop Environment";
			this.set_content_height(360);
			this.set_content_width(720);

			var page = new Adw.PreferencesPage();
			this.group = new Adw.PreferencesGroup();
			var pin_label = new Gtk.Label("Enter the twelve-digit code") {
				xalign = 0.5f,
				justify = Gtk.Justification.CENTER,
				css_classes = {"dim-label"}
			};
			this.pin_entry = new Gtk.Entry() {
				placeholder_text = "000000000000",
				max_length = 12,
				input_purpose = Gtk.InputPurpose.DIGITS,
				input_hints = Gtk.InputHints.NO_EMOJI | Gtk.InputHints.NO_SPELLCHECK,
				enable_emoji_completion = false,
				xalign = 0.5f,
				hexpand = true,
				height_request = 64,
				css_classes = {"title-1"}
			};
			this.pin_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				visible = false,
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
			this.pin_box.append(pin_label);
			this.pin_box.append(this.pin_entry);
			this.browse_spinner = new Gtk.Spinner() {
				halign = Gtk.Align.CENTER,
				margin_top = 12,
				visible = false
			};
			this.listen_label = new Gtk.Label("Listening for a desktop…") {
				wrap = true,
				xalign = 0.5f,
				justify = Gtk.Justification.CENTER,
				margin_top = 12
			};
			this.group.add(this.listen_label);
			this.group.add(this.browse_spinner);
			this.group.add(this.pin_box);
			page.add(this.group);

			this.request_button = new Gtk.Button() {
				label = "Request",
				css_classes = {"suggested-action"},
				sensitive = false
			};
			var footer = new Adw.PreferencesGroup();
			footer.add(this.request_button);
			page.add(footer);
			this.add(page);

			this.pin_entry.changed.connect(() => {
				if (this.pin_auto_id != 0) {
					GLib.Source.remove(this.pin_auto_id);
					this.pin_auto_id = 0;
				}
				if (this.phase != Phase.AWAITING_PIN
					&& this.phase != Phase.FAILED_PIN) {
					return;
				}
				var pin = this.pin_entry.text.strip();
				if (pin.length != 12) {
					this.request_button.sensitive = false;
					this.request_button.remove_css_class("suggested-action");
					return;
				}
				for (var i = 0; i < pin.length; i++) {
					if (pin[i] < '0' || pin[i] > '9') {
						this.request_button.sensitive = false;
						this.request_button.remove_css_class("suggested-action");
						return;
					}
				}
				this.request_button.label = "Request";
				this.request_button.add_css_class("suggested-action");
				this.request_button.sensitive = true;
				this.pin_auto_id = GLib.Timeout.add(1500, () => {
					this.pin_auto_id = 0;
					if (this.phase == Phase.ENROLLING) {
						return false;
					}
					var current = this.pin_entry.text.strip();
					if (current.length != 12) {
						return false;
					}
					for (var j = 0; j < current.length; j++) {
						if (current[j] < '0' || current[j] > '9') {
							return false;
						}
					}
					this.request.begin();
					return false;
				});
			});
			this.pin_entry.activate.connect(() => {
				if (this.pin_auto_id != 0) {
					GLib.Source.remove(this.pin_auto_id);
					this.pin_auto_id = 0;
				}
				if (this.phase == Phase.AWAITING_PIN
					|| this.phase == Phase.FAILED_PIN) {
					this.request.begin();
				}
			});
			this.request_button.clicked.connect(() => {
				switch (this.phase) {
					case Phase.AWAITING_PIN:
					case Phase.FAILED_PIN:
						this.request.begin();
						break;

					case Phase.FAILED_LINK:
						this.start_browse();
						break;

					default:
						break;
				}
			});
			this.closed.connect(() => {
				this.can_close = true;
				if (this.browse_id != 0) {
					GLib.Source.remove(this.browse_id);
					this.browse_id = 0;
				}
				if (this.pin_auto_id != 0) {
					GLib.Source.remove(this.pin_auto_id);
					this.pin_auto_id = 0;
				}
				var browse_root = this.get_root() as Gtk.Window;
				if (browse_root != null) {
					android_pair_browse_stop(browse_root);
				}
				this.pin_entry.text = "";
				this.phase = Phase.IDLE;
				this.status_detail = "";
				this.apply_layout();
				this.dialog_closed();
			});
		}

		/**
		 * Applies widget visibility and chrome for the current {@link phase}.
		 */
		private void apply_layout()
		{
			this.listen_label.label = this.status_detail;
			switch (this.phase) {
				case Phase.IDLE:
					this.browse_spinner.stop();
					this.browse_spinner.visible = false;
					this.pin_box.visible = false;
					this.request_button.label = "Request";
					this.request_button.remove_css_class("suggested-action");
					this.request_button.sensitive = false;
					break;

				case Phase.BROWSING:
					this.browse_spinner.visible = true;
					this.browse_spinner.start();
					this.pin_box.visible = false;
					this.request_button.label = "Request";
					this.request_button.remove_css_class("suggested-action");
					this.request_button.sensitive = false;
					break;

				case Phase.AWAITING_PIN:
					this.browse_spinner.stop();
					this.browse_spinner.visible = false;
					this.pin_box.visible = true;
					this.request_button.label = "Request";
					this.request_button.remove_css_class("suggested-action");
					this.request_button.sensitive = false;
					GLib.Idle.add(() => {
						this.pin_entry.grab_focus();
						this.pin_entry.reset_im_context();
						return false;
					});
					break;

				case Phase.ENROLLING:
					this.browse_spinner.visible = true;
					this.browse_spinner.start();
					this.pin_box.visible = true;
					this.request_button.label = "Requesting";
					this.request_button.remove_css_class("suggested-action");
					this.request_button.sensitive = false;
					break;

				case Phase.FAILED_PIN:
					this.browse_spinner.stop();
					this.browse_spinner.visible = false;
					this.pin_box.visible = true;
					this.pin_entry.text = "";
					this.request_button.label = "Request";
					this.request_button.remove_css_class("suggested-action");
					this.request_button.sensitive = false;
					GLib.Idle.add(() => {
						this.pin_entry.grab_focus();
						this.pin_entry.reset_im_context();
						return false;
					});
					break;

				case Phase.FAILED_LINK:
					this.browse_spinner.stop();
					this.browse_spinner.visible = false;
					this.pin_box.visible = false;
					this.pin_entry.text = "";
					this.request_button.label = "Listen again";
					this.request_button.remove_css_class("suggested-action");
					this.request_button.sensitive = true;
					break;

				default:
					break;
			}
		}

		private void start_browse()
		{
			if (this.browse_id != 0) {
				GLib.Source.remove(this.browse_id);
				this.browse_id = 0;
			}
			var browse_root = this.get_root() as Gtk.Window;
			if (browse_root != null) {
				android_pair_browse_stop(browse_root);
			}
			this.found = "";
			this.server_id = "";
			this.phase = Phase.BROWSING;
			this.status_detail = "Listening for a desktop…";
			this.apply_layout();
			this.browse_id = GLib.Idle.add(() => {
				this.browse_id = 0;
				var window = this.get_root() as Gtk.Window;
				if (window == null) {
					this.phase = Phase.FAILED_LINK;
					this.status_detail = "No desktop found";
					this.apply_layout();
					this.error_occurred("No desktop found");
					return false;
				}
				android_pair_browse_start(window);
				this.browse_id = GLib.Timeout.add(200, () => {
					if (this.phase != Phase.BROWSING) {
						this.browse_id = 0;
						return false;
					}
					var hit = android_pair_browse_poll();
					if (hit == "") {
						return true;
					}
					var root = this.get_root() as Gtk.Window;
					if (root != null) {
						android_pair_browse_stop(root);
					}
					this.browse_id = 0;
					if (hit == "none") {
						this.phase = Phase.FAILED_LINK;
						this.status_detail = "No desktop found";
						this.apply_layout();
						this.error_occurred("No desktop found");
						return false;
					}
					var nl = hit.index_of("\n");
					if (nl <= 0 ||
						!GLib.Uuid.string_is_valid(hit.substring(0, nl))) {
						this.phase = Phase.FAILED_LINK;
						this.status_detail = "No server id";
						this.apply_layout();
						this.error_occurred("No server id");
						return false;
					}
					this.server_id = hit.substring(0, nl);
					this.found = hit.substring(nl + 1);
					this.phase = Phase.AWAITING_PIN;
					this.status_detail =
						"Desktop at " + this.found +
						". Enter the twelve-digit code.";
					this.apply_layout();
					return false;
				});
				return false;
			});
		}

		/**
		 * Prepares the dialog before {@link Gtk.Window.present}.
		 */
		public void show_add()
		{
			this.registered_url = null;
			this.registered_addresses = "";
			this.server_id = "";
			this.found = "";
			if (this.pin_auto_id != 0) {
				GLib.Source.remove(this.pin_auto_id);
				this.pin_auto_id = 0;
			}
			this.pin_entry.text = "";
			this.start_browse();
		}

		private async void request()
		{
			if (this.phase == Phase.ENROLLING) {
				return;
			}
			if (this.phase != Phase.AWAITING_PIN
				&& this.phase != Phase.FAILED_PIN) {
				this.phase = Phase.FAILED_LINK;
				this.status_detail = "No desktop found";
				this.apply_layout();
				this.error_occurred("No desktop found");
				return;
			}
			if (this.found == "") {
				this.phase = Phase.FAILED_LINK;
				this.status_detail = "No desktop found";
				this.apply_layout();
				this.error_occurred("No desktop found");
				return;
			}
			var colon = this.found.last_index_of(":");
			if (colon <= 0) {
				this.phase = Phase.FAILED_LINK;
				this.status_detail = "Bad address";
				this.apply_layout();
				this.error_occurred("Bad address");
				return;
			}
			var port = 0;
			if (!int.try_parse(this.found.substring(colon + 1), out port)) {
				this.phase = Phase.FAILED_LINK;
				this.status_detail = "Bad address";
				this.apply_layout();
				this.error_occurred("Bad address");
				return;
			}
			var host = this.found.substring(0, colon);
			if (!GLib.Uuid.string_is_valid(this.server_id)) {
				this.phase = Phase.FAILED_LINK;
				this.status_detail = "No server id";
				this.apply_layout();
				this.error_occurred("No server id");
				return;
			}
			var pin = this.pin_entry.text.strip();
			if (pin.length != 12) {
				this.phase = Phase.FAILED_PIN;
				this.status_detail = "Enter the twelve digits";
				this.apply_layout();
				this.error_occurred("Enter the twelve digits");
				return;
			}
			for (var i = 0; i < pin.length; i++) {
				if (pin[i] < '0' || pin[i] > '9') {
					this.phase = Phase.FAILED_PIN;
					this.status_detail = "Enter the twelve digits";
					this.apply_layout();
					this.error_occurred("Enter the twelve digits");
					return;
				}
			}
			this.phase = Phase.ENROLLING;
			this.status_detail = "Registering…";
			this.apply_layout();
			var phone = new OLLMchat.Settings.FilesdClient();
			phone.server_id = this.server_id;
			var force_register = false;
			while (true) {
				var code = phone.try_connection(
					host, (uint16) port, pin, force_register,
					ollmapp_android_phone_label());
				if (!force_register) {
					switch (code) {
						case (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED:
						case (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR:
							force_register = true;
							continue;
						default:
							break;
					}
				}
				if (code != 0) {
					var label = "The desktop rejected the request.";
					var next = Phase.FAILED_PIN;
					switch (code) {
						case (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED:
							label =
								"This phone is not registered with the desktop.";
							break;

						case (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR:
							label = "Could not reach the desktop.";
							next = Phase.FAILED_LINK;
							break;

						default:
							break;
					}
					this.phase = next;
					this.status_detail = label;
					this.apply_layout();
					GLib.warning("%s", label);
					this.error_occurred(label);
					return;
				}
				this.registered_url = phone.url;
				this.registered_addresses = phone.addresses;
				this.close();
				return;
			}
		}
	}

	[CCode (cname = "ollmapp_android_pair_browse_start", cheader_filename = "android-pair-browse.h")]
	private extern void android_pair_browse_start(Gtk.Window window);

	[CCode (cname = "ollmapp_android_pair_browse_poll", cheader_filename = "android-pair-browse.h")]
	private extern string android_pair_browse_poll();

	[CCode (cname = "ollmapp_android_pair_browse_stop", cheader_filename = "android-pair-browse.h")]
	private extern void android_pair_browse_stop(Gtk.Window window);
}