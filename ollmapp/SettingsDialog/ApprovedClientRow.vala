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
	 * Widget group for a single approved client-cert row in the connections page.
	 *
	 * Responsible for creating and managing all widgets for an approved client row.
	 *
	 * @since 1.0
	 */
	public class ApprovedClientRow : Object
	{
		/**
		 * Emitted when the remove button is clicked.
		 */
		public signal void remove_requested();

		/**
		 * The client-cert id (used to identify this row).
		 */
		public int64 id { get; construct; }

		/**
		 * The expander row containing all client fields.
		 */
		public Adw.ExpanderRow expander { get; private set; }

		/**
		 * Creates a new ApprovedClientRow with all widgets.
		 *
		 * @param client Approved ClientCert to render
		 * @param fallback_num 1-based index used for the title when requester is empty
		 */
		public ApprovedClientRow(OLLMapp.ClientCert client, int fallback_num)
		{
			Object(id: client.id);

			this.expander = new Adw.ExpanderRow() {
				title = client.requester != "" ? client.requester : "Client %d".printf(fallback_num),
				subtitle = client.fingerprint,
				can_focus = false,
				focus_on_click = false
			};

			var when_row = new Adw.ActionRow() {
				title = "Registered"
			};
			var when = new GLib.DateTime.from_unix_local(client.created).format("%Y-%m-%d %H:%M");
			when_row.add_suffix(new Gtk.Label(when) {
				xalign = 1
			});
			this.expander.add_row(when_row);

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
