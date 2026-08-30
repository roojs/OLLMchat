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

namespace OLLMchatGtk
{
	/**
	 * Root sudo prompt owned by {@link ChatPermission}.
	 *
	 * Stores a successful password in libsecret. Later prompts hide the
	 * entry and require a two-second hold on Allow. Wrong stored secrets
	 * fall back to the type form. Windows and Android compile a no-op stub.
	 *
	 * == Example ==
	 *
	 * {{{
	 * this.sudo = new Sudo(this.allow_once_btn);
	 * this.sudo.checked.connect((password) => {
	 *     this.pending_elevation_password = password;
	 *     this.resume_callback();
	 * });
	 * if (high_risk) {
	 *     this.sudo.prepare.begin();
	 * }
	 * }}}
	 */
	public class Sudo : Gtk.Box
	{
		/**
		 * Emitted after {@link check} with hold false succeeds.
		 *
		 * @param password the verified sudo password
		 */
		public signal void checked(string password);

		/**
		 * True while {@link check} with hold false is running.
		 *
		 * @param on true to disable Deny in {@link ChatPermission}
		 */
		public signal void busy(bool on);

		/**
		 * Overlay that packs Allow in the permission button row.
		 */
		public Gtk.Overlay overlay;
		private Gtk.Button allow;
		private Gtk.Label label;
		private Gtk.PasswordEntry entry;
		private Gtk.Label error_label;
		private Gtk.Box hold_fill;
		private uint hold_timeout_src = 0;
		private int64 hold_start_us = 0;
		private bool holding = false;
		private Secret.Schema schema;

		/**
		 * Wrap Allow in an overlay and own the password row.
		 *
		 * @param allow the permission Allow button (packed via {@link overlay})
		 */
		public Sudo(Gtk.Button allow)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.allow = allow;
			this.hexpand = true;
			this.schema = new Secret.Schema(
				"org.roojs.ollmchat.Sudo",
				Secret.SchemaFlags.NONE,
				"user", Secret.SchemaAttributeType.STRING);
			this.label = new Gtk.Label("Your password (sudo):") {
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 4,
				visible = false
			};
			this.entry = new Gtk.PasswordEntry() {
				hexpand = true,
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 4,
				visible = false,
				css_classes = { "elevation-password-entry" }
			};
			this.error_label = new Gtk.Label("") {
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 8,
				wrap = true,
				visible = false,
				css_classes = { "elevation-password-error" }
			};
			this.append(this.label);
			this.append(this.entry);
			this.append(this.error_label);
			this.hold_fill = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				halign = Gtk.Align.START,
				valign = Gtk.Align.FILL,
				hexpand = false,
				vexpand = true,
				width_request = 1,
				visible = false,
				can_target = false,
				css_classes = { "sudo-hold-fill" }
			};
			this.overlay = new Gtk.Overlay();
			this.overlay.set_child(this.allow);
			this.overlay.add_overlay(this.hold_fill);
			this.entry.changed.connect(() => {
				if (this.holding) {
					return;
				}
				this.allow.sensitive = this.entry.get_text().strip() != "";
				this.error_label.visible = false;
			});
			this.entry.activate.connect(() => {
				this.submit();
			});
			var hold_press = new Gtk.GestureClick();
			hold_press.pressed.connect(this.on_hold_pressed);
			hold_press.released.connect((n_press, x, y) => {
				if (this.hold_timeout_src == 0) {
					return;
				}
				GLib.Source.remove(this.hold_timeout_src);
				this.hold_timeout_src = 0;
				this.hold_fill.width_request = 1;
				this.hold_fill.visible = false;
			});
			hold_press.cancel.connect(() => {
				if (this.hold_timeout_src == 0) {
					return;
				}
				GLib.Source.remove(this.hold_timeout_src);
				this.hold_timeout_src = 0;
				this.hold_fill.width_request = 1;
				this.hold_fill.visible = false;
			});
			this.allow.add_controller(hold_press);
			var hold_motion = new Gtk.EventControllerMotion();
			hold_motion.leave.connect(() => {
				if (this.hold_timeout_src == 0) {
					return;
				}
				GLib.Source.remove(this.hold_timeout_src);
				this.hold_timeout_src = 0;
				this.hold_fill.width_request = 1;
				this.hold_fill.visible = false;
			});
			this.allow.add_controller(hold_motion);
		}

		/**
		 * Look up a stored secret. If present, {@link check} with hold true.
		 * Otherwise show the type form.
		 */
		public async void prepare()
		{
			this.reset();
			this.allow.remove_css_class("suggested-action");
			this.allow.add_css_class("destructive-action");
			this.allow.label = "Allow (root)";
			this.allow.sensitive = false;
			this.entry.text = "";
			this.error_label.label = "";
			this.error_label.visible = false;
			var stored = "";
			try {
				stored = Secret.password_lookup_sync(this.schema, null,
					"user", GLib.Environment.get_user_name());
			} catch (GLib.Error e) {
				stored = "";
			}
			if (stored == null || stored == "") {
				this.holding = false;
				this.label.visible = true;
				this.entry.visible = true;
				GLib.Idle.add(() => {
					this.entry.grab_focus();
					return false;
				});
				return;
			}
			this.entry.text = stored;
			this.label.visible = false;
			this.entry.visible = false;
			yield this.check(true);
		}

		/**
		 * Hide the password row and cancel a hold in progress.
		 */
		public void reset()
		{
			if (this.hold_timeout_src != 0) {
				GLib.Source.remove(this.hold_timeout_src);
				this.hold_timeout_src = 0;
			}
			this.hold_fill.visible = false;
			this.hold_fill.width_request = 1;
			this.holding = false;
			this.label.visible = false;
			this.entry.visible = false;
			this.error_label.visible = false;
			this.error_label.label = "";
			this.entry.text = "";
			this.allow.remove_css_class("destructive-action");
			this.allow.add_css_class("suggested-action");
			this.allow.label = "Allow";
			this.allow.sensitive = true;
		}

		/**
		 * Typed Allow or Enter. Ignored while a hold is armed.
		 */
		public void submit()
		{
			if (this.holding) {
				return;
			}
			if (this.entry.get_text().strip() == "") {
				return;
			}
			this.allow.sensitive = false;
			this.busy(true);
			this.check.begin(false);
		}

		/**
		 * ''sudo -k'' then ''sudo -S true''.
		 *
		 * @param hold true from {@link prepare}: success arms hold. false from
		 *             {@link submit} / {@link on_hold_tick}: success stores and {@link checked}.
		 */
		private async void check(bool hold)
		{
			var error = "";
			try {
				var proc = new GLib.Subprocess.newv({"sudo", "-k"}, GLib.SubprocessFlags.NONE);
				proc.wait(null);
			} catch (GLib.Error e) {
				error = e.message;
			}
			var ok = false;
			if (error == "") {
				try {
					var proc = new GLib.Subprocess.newv({"sudo", "-S", "true"},
						GLib.SubprocessFlags.STDOUT_PIPE
						| GLib.SubprocessFlags.STDERR_PIPE
						| GLib.SubprocessFlags.STDIN_PIPE);
					var stdin = proc.get_stdin_pipe();
					stdin.write_all((this.entry.get_text() + "\n").data, null);
					stdin.close(null);
					yield proc.wait_async(null);
					ok = proc.get_successful();
				} catch (GLib.Error e) {
					error = e.message;
				}
			}
			if (error == "" && ok && hold) {
				this.holding = true;
				this.label.visible = false;
				this.entry.visible = false;
				this.allow.sensitive = true;
				this.allow.label = "Hold 2s — use saved password";
				return;
			}
			if (error == "" && ok) {
				var password = this.entry.get_text();
				this.store(password);
				this.checked(password);
				return;
			}
			if (error != "") {
				this.error_label.label = error;
			}
			if (error == "") {
				this.error_label.label = "Wrong password. Try again.";
			}
			this.busy(false);
			this.error_label.visible = true;
			this.entry.text = "";
			this.allow.sensitive = false;
			this.holding = false;
			this.label.visible = true;
			this.entry.visible = true;
			this.allow.label = "Allow (root)";
			try {
				Secret.password_clear_sync(this.schema, null,
					"user", GLib.Environment.get_user_name());
			} catch (GLib.Error e) {
			}
			this.entry.grab_focus();
		}

		/**
		 * Store @password in libsecret. Ignores store errors.
		 *
		 * @param password sudo password to save
		 */
		private void store(string password)
		{
			Secret.password_store.begin(this.schema, Secret.COLLECTION_DEFAULT,
				"OLLMchat sudo", password, null, (obj, res) => {
					try {
						Secret.password_store.end(res);
					} catch (GLib.Error e) {
					}
				}, "user", GLib.Environment.get_user_name());
		}

		/**
		 * Arm the two-second fill. No-op when not in hold mode.
		 *
		 * @param n_press unused (Gtk.GestureClick)
		 * @param x unused
		 * @param y unused
		 */
		private void on_hold_pressed(int n_press, double x, double y)
		{
			if (!this.holding) {
				return;
			}
			this.hold_fill.visible = true;
			this.hold_fill.width_request = 1;
			this.hold_start_us = GLib.get_monotonic_time();
			if (this.hold_timeout_src != 0) {
				GLib.Source.remove(this.hold_timeout_src);
			}
			this.hold_timeout_src = GLib.Timeout.add(50, this.on_hold_tick);
		}

		/**
		 * Grow the fill. At two seconds, {@link check} with hold false.
		 *
		 * @return true to keep the timeout
		 */
		private bool on_hold_tick()
		{
			var elapsed_ms = (GLib.get_monotonic_time() - this.hold_start_us) / 1000;
			this.hold_fill.width_request = (int) ((this.allow.get_width() * elapsed_ms) / 2000);
			if (elapsed_ms < 2000) {
				return true;
			}
			this.hold_timeout_src = 0;
			this.hold_fill.visible = false;
			this.hold_fill.width_request = 1;
			this.allow.sensitive = false;
			this.busy(true);
			this.check.begin(false);
			return false;
		}
	}
}
