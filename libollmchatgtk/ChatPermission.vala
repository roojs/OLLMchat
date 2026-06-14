/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
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
	 * Permission widget that displays permission requests with buttons.
	 * 
	 * This widget is designed to be integrated into ChatWidget between
	 * ChatView and ChatInput. It handles showing/hiding internally and
	 * uses async methods to return user responses.
	 * 
	 * @since 1.0
	 */
	public class ChatPermission : Gtk.Frame
	{
		private Gtk.Label question_label;
		private Gtk.Label password_label;
		private Gtk.PasswordEntry password_entry;
		private Gtk.Label password_error_label;
		private Gtk.Box button_box;
		private SourceFunc? resume_callback = null;
		private OLLMchat.ChatPermission.PermissionResponse? pending_response = null;
		private bool pending_high_risk = false;
		private string pending_elevation_password = "";
		
		// Store button references for dynamic show/hide
		private Gtk.Button deny_always_btn;
		private Gtk.Button deny_once_btn;
		private Gtk.Button allow_once_btn;
		private Gtk.Button allow_always_btn;
		
		/**
		 * Creates a new ChatPermission widget.
		 * 
		 * @since 1.0
		 */
		public ChatPermission()
		{
			// Create question label
			this.question_label = new Gtk.Label("") {
				wrap = true,
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 8
			};

			this.password_label = new Gtk.Label("Your password (sudo):") {
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 4
			};
			this.password_entry = new Gtk.PasswordEntry() {
				hexpand = true,
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 4
			};
			this.password_entry.add_css_class("elevation-password-entry");
			this.password_error_label = new Gtk.Label("") {
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 8,
				wrap = true
			};
			this.password_error_label.add_css_class("elevation-password-error");
			
			// Create button row
			this.button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 12,
				halign = Gtk.Align.START
			};
			
			// Create buttons with styling and store references
			this.deny_always_btn = this.create_button("Deny Always", "Permanently deny this permission", OLLMchat.ChatPermission.PermissionResponse.DENY_ALWAYS, true);
			this.deny_once_btn = this.create_button("Deny", "Deny this one time only", OLLMchat.ChatPermission.PermissionResponse.DENY_ONCE, true);
			this.allow_once_btn = this.create_button("Allow", "Allow this one time only", OLLMchat.ChatPermission.PermissionResponse.ALLOW_ONCE, false);
			this.allow_always_btn = this.create_button("Allow Always", "Permanently allow this permission", OLLMchat.ChatPermission.PermissionResponse.ALLOW_ALWAYS, false);
			
			// Add buttons to button box
			this.button_box.append(this.deny_always_btn);
			this.button_box.append(this.deny_once_btn);
			this.button_box.append(this.allow_once_btn);
			this.button_box.append(this.allow_always_btn);
			
			// Create main container
			var container = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true
			};
			container.append(this.question_label);
			container.append(this.password_label);
			container.append(this.password_entry);
			container.append(this.password_error_label);
			container.append(this.button_box);
			
			// Configure frame
			this.margin_top = 16;
			this.hexpand = true;
			this.set_child(container);
			this.add_css_class("permission-widget");
			this.password_label.set_visible(false);
			this.password_entry.set_visible(false);
			this.password_error_label.set_visible(false);
			this.set_visible(false);

			this.password_entry.changed.connect(() => {
				if (this.pending_high_risk) {
					this.allow_once_btn.sensitive = this.password_entry.get_text().strip() != "";
				}
				this.password_error_label.set_visible(false);
			});
			this.password_entry.activate.connect(() => {
				if (!this.pending_high_risk) {
					return;
				}
				if (!this.allow_once_btn.sensitive) {
					return;
				}
				this.validate_elevation_and_resume.begin(
					OLLMchat.ChatPermission.PermissionResponse.ALLOW_ONCE);
			});
		}
		
		/**
		 * Requests permission from the user with the given question.
		 * 
		 * Shows the widget, waits for user response, then hides the widget.
		 * 
		 * @param question The permission question to display
		 * @param one_time When true, hides "Allow Always" and "Deny Always" (see {@link OLLMchat.Tool.RequestBase.one_time_only})
		 * @param high_risk When true, styles the row as high-risk (e.g. root elevation)
		 * @param elevation_password Password entered for high-risk elevation (empty when denied)
		 * @return The user's permission response
		 * @since 1.0
		 */
		public async OLLMchat.ChatPermission.PermissionResponse request(
			string question,
			bool one_time = false,
			bool high_risk = false,
			out string elevation_password)
		{
			elevation_password = "";
			this.pending_high_risk = high_risk;
			this.pending_elevation_password = "";
			// Update question text
			this.question_label.label = question;
			
			// Show/hide buttons based on one_time flag
			this.deny_always_btn.visible = !one_time;
			this.allow_always_btn.visible = !one_time;
			// allow_once_btn is always visible

			this.password_label.set_visible(high_risk);
			this.password_entry.set_visible(high_risk);
			this.password_error_label.set_visible(false);
			if (high_risk) {
				this.password_entry.text = "";
				this.password_error_label.label = "";
				this.allow_once_btn.sensitive = false;
			}
			
			if (high_risk) {
				this.add_css_class ("high-risk");
				this.allow_once_btn.remove_css_class ("suggested-action");
				this.allow_once_btn.add_css_class ("destructive-action");
				this.allow_once_btn.label = "Allow (root)";
			}
			if (!high_risk) {
				this.remove_css_class ("high-risk");
				this.allow_once_btn.remove_css_class ("destructive-action");
				this.allow_once_btn.add_css_class ("suggested-action");
				this.allow_once_btn.label = "Allow";
				this.allow_once_btn.sensitive = true;
			}
			
			// Show the widget
			this.set_visible(true);

			if (high_risk) {
				GLib.Idle.add(() => {
					this.password_entry.grab_focus();
					return false;
				});
			}
			
			// Wait for user response using callback pattern
			this.pending_response = null;
			this.resume_callback = request.callback;
			
			// Yield and wait for callback to be invoked
			yield;
			
			// Clean up
			this.resume_callback = null;
			
			// Hide the widget
			this.set_visible(false);
			this.remove_css_class ("high-risk");
			this.allow_once_btn.remove_css_class ("destructive-action");
			this.allow_once_btn.add_css_class ("suggested-action");
			this.allow_once_btn.label = "Allow";
			this.allow_once_btn.sensitive = true;
			this.password_label.set_visible(false);
			this.password_entry.set_visible(false);
			this.password_error_label.set_visible(false);
			this.password_error_label.label = "";
			this.password_entry.text = "";
			this.pending_high_risk = false;
			elevation_password = this.pending_elevation_password;
			this.pending_elevation_password = "";
			
			return this.pending_response ?? OLLMchat.ChatPermission.PermissionResponse.DENY_ONCE;
		}

		/**
		 * Verifies the sudo password with {@literal sudo -S true} before resuming
		 * the permission prompt. Wrong passwords stay in the dialog; the LLM never
		 * sees authentication failure.
		 */
		private async void validate_elevation_and_resume(
			OLLMchat.ChatPermission.PermissionResponse response)
		{
			this.allow_once_btn.sensitive = false;
			this.deny_once_btn.sensitive = false;
			this.deny_always_btn.sensitive = false;
			this.allow_always_btn.sensitive = false;

			var password = this.password_entry.get_text();
			var ok = false;
#if !G_OS_WIN32
			if (GLib.Environment.find_program_in_path ("sudo") != null) {
				try {
					var klauncher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.NONE);
					var kproc = klauncher.spawnv ({"sudo", "-k"});
					kproc.wait (null);
					var flags = GLib.SubprocessFlags.STDOUT_PIPE
						| GLib.SubprocessFlags.STDERR_PIPE
						| GLib.SubprocessFlags.STDIN_PIPE;
					var launcher = new GLib.SubprocessLauncher (flags);
					var proc = launcher.spawnv ({"sudo", "-S", "true"});
					var stdin = proc.get_stdin_pipe ();
					stdin.write_all ((password + "\n").data, null);
					stdin.close (null);
					yield proc.wait_async (null);
					ok = proc.get_successful ();
				} catch (GLib.Error e) {
					ok = false;
				}
			}
#endif
			this.deny_once_btn.sensitive = true;
			this.deny_always_btn.sensitive = this.deny_always_btn.visible;
			this.allow_always_btn.sensitive = this.allow_always_btn.visible;

			if (!ok) {
				this.password_error_label.label = "Wrong password. Try again.";
				this.password_error_label.set_visible(true);
				this.password_entry.text = "";
				this.allow_once_btn.sensitive = false;
				this.password_entry.grab_focus();
				return;
			}

			this.pending_elevation_password = password;
			this.pending_response = response;
			if (this.resume_callback != null) {
				this.resume_callback();
			}
		}
		
		/**
		 * Creates a styled permission button.
		 */
		private Gtk.Button create_button(string label, string tooltip, OLLMchat.ChatPermission.PermissionResponse response, bool is_deny)
		{
			var btn = new Gtk.Button.with_label(label) {
				tooltip_text = tooltip
			};
			
			if (is_deny) {
				btn.add_css_class("destructive-action");
			} else {
				btn.add_css_class("suggested-action");
			}
			
			// Set cursor to pointer (fixes issue with TextView showing text cursor)
			var cursor = new Gdk.Cursor.from_name("pointer", null);
			if (cursor != null) {
				btn.set_cursor(cursor);
			}
			
			btn.clicked.connect(() => {
				switch (response) {
					case OLLMchat.ChatPermission.PermissionResponse.DENY_ONCE:
					case OLLMchat.ChatPermission.PermissionResponse.DENY_ALWAYS:
						this.pending_response = response;
						if (this.resume_callback != null) {
							this.resume_callback();
						}
						break;
					case OLLMchat.ChatPermission.PermissionResponse.ALLOW_ONCE:
					case OLLMchat.ChatPermission.PermissionResponse.ALLOW_ALWAYS:
						if (this.pending_high_risk) {
							if (this.password_entry.get_text().strip() == "") {
								return;
							}
							this.validate_elevation_and_resume.begin (response);
							break;
						}
						this.pending_response = response;
						if (this.resume_callback != null) {
							this.resume_callback();
						}
						break;
				}
			});
			
			return btn;
		}
	}
}
