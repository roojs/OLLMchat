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
	 * Widget group for the single outbound file-server connection row.
	 */
	public class FileConnectionRow : Object
	{
		public signal void remove_requested();
		public signal void enabled_changed(bool enabled);

		public Adw.ExpanderRow expander { get; private set; }
		public Gtk.Button check_button { get; private set; }

		public FileConnectionRow(OLLMchat.Settings.FilesdClient client)
		{
			var subtitle = client.approved ? "Active" : "Requested";
			var title = client.url;
			try {
				title = GLib.Uri.parse(client.url, GLib.UriFlags.NONE).get_host();
			} catch (GLib.UriError e) {
			}
			this.expander = new Adw.ExpanderRow() {
				title = title,
				subtitle = subtitle,
				can_focus = false,
				focus_on_click = false
			};

			var url_row = new Adw.ActionRow() {
				title = "URL"
			};
			url_row.add_suffix(new Gtk.Label(client.url) {
				xalign = 1,
				selectable = true,
				ellipsize = Pango.EllipsizeMode.MIDDLE
			});
			this.expander.add_row(url_row);

			var status_row = new Adw.ActionRow() {
				title = "Status"
			};
			status_row.add_suffix(new Gtk.Label(subtitle) {
				xalign = 1
			});
			this.expander.add_row(status_row);

			var enabled_switch = new Gtk.Switch() {
				active = client.enabled,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var enabled_row = new Adw.ActionRow() {
				title = "Enabled"
			};
			enabled_row.add_suffix(enabled_switch);
			enabled_switch.notify["active"].connect(() => {
				this.enabled_changed(enabled_switch.active);
			});
			this.expander.add_row(enabled_row);

			this.check_button = new Gtk.Button.with_label("Check") {
				sensitive = false,
				tooltip_text = "Check whether the desktop has approved this device (Phase 2)"
			};
			var check_row = new Adw.ActionRow() {
				title = "Registration"
			};
			check_row.add_suffix(this.check_button);
			this.expander.add_row(check_row);

			var remove_button = new Gtk.Button.with_label("Remove") {
				css_classes = {"destructive-action"}
			};
			remove_button.clicked.connect(() => {
				this.remove_requested();
			});
			var button_row = new Adw.ActionRow();
			button_row.add_suffix(remove_button);
			this.expander.add_row(button_row);
		}
	}
}
