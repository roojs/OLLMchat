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

namespace OLLMapp.SettingsDialog
{
	/**
	 * Dialog that shows a spinner while checking connection.
	 * 
	 * Used during connection verification to provide user feedback.
	 * 
	 * @since 1.0
	 */
	public class CheckingConnectionDialog : Adw.Dialog
	{
		/**
		 * Parent window to attach the dialog to.
		 */
		public Gtk.Window parent { get; construct; }
		
		/**
		 * Creates a new CheckingConnectionDialog.
		 * 
		 * @param parent Parent window to attach the dialog to
		 */
		public CheckingConnectionDialog(Gtk.Window parent)
		{
			Object(
				title: "Checking Connection",
				parent: parent
			);
			
			// Create content box
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
			
			var label = new Gtk.Label("Verifying connection to server...") {
				halign = Gtk.Align.CENTER
			};
			box.append(label);
			
			this.set_child(box);
		}
		
		/**
		 * Shows the dialog.
		 * 
		 * Parent is the main OllmchatWindow - should always be valid and visible when settings are opened.
		 */
		public void show_dialog()
		{
		
			this.present(this.parent);
		}
		
		/**
		 * Hides the dialog.
		 * 
		 * Hides the dialog so it can be reopened later.
		 */
		public void hide_dialog()
		{
			this.close();
		}
	}
}
