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

namespace OLLMapp
{
	/**
	 * Modal spinner with a status line (startup, connection checks, etc.).
	 *
	 * @since 1.0
	 */
	public class BusyDialog : Adw.Dialog
	{
		/**
		 * Parent window to attach the dialog to.
		 */
		public Gtk.Window parent { get; construct; }

		public Gtk.Label status_label { get; private set; }

		/**
		 * @param parent Parent window to attach the dialog to
		 */
		public BusyDialog(Gtk.Window parent)
		{
			Object(
				title: "Please wait",
				parent: parent
			);

			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24,
				spacing = 12
			};

			var spinner = new Gtk.Spinner() {
				spinning = true,
				halign = Gtk.Align.CENTER,
				width_request = 48,
				height_request = 48
			};
			box.append(spinner);

			this.status_label = new Gtk.Label("") {
				halign = Gtk.Align.CENTER,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD_CHAR,
				max_width_chars = 40
			};
			box.append(this.status_label);

			this.set_child(box);
		}
	}
}
