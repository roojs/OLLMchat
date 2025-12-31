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

namespace OLLMchat
{
	/**
	 * Banner widget that displays file change warnings with action buttons.
	 */
	public class FileChangeBanner : Gtk.Box
	{
		public Gtk.Button overwrite_button { get; private set; }
		public Gtk.Button refresh_button { get; private set; }
		public Gtk.Button ignore_button { get; private set; }
		public Gtk.Label label { get; private set; }
		public Gtk.Revealer revealer { get; private set; }
		
		/**
		 * Creates a new FileChangeBanner.
		 * 
		 * @param window The window instance (for accessing project_manager)
		 */
		public FileChangeBanner(OllmchatWindow window)
		{
			Object(
				orientation: Gtk.Orientation.HORIZONTAL,
				spacing: 12,
				margin_start: 12,
				margin_end: 12,
				margin_top: 6,
				margin_bottom: 6
			);
			
			this.css_classes = {"banner"};
			
			// Create revealer and set this banner as its child
			this.revealer = new Gtk.Revealer() {
				child = this,
				reveal_child = false,
				transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN
			};
			
			this.label = new Gtk.Label("") {
				hexpand = true,
				halign = Gtk.Align.START,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD_CHAR
			};
			this.append(this.label);
			
			// Create button box
			var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			
			// Overwrite button (save buffer to disk)
			this.overwrite_button = new Gtk.Button.with_label("Overwrite") {
				css_classes = {"destructive-action"}
			};
			button_box.append(this.overwrite_button);
			
			// Refresh button (load from disk into buffer)
			this.refresh_button = new Gtk.Button.with_label("Refresh") {
				css_classes = {"suggested-action"}
			};
			button_box.append(this.refresh_button);
			
			// Ignore button (dismiss banner)
			this.ignore_button = new Gtk.Button.with_label("Ignore");
			this.ignore_button.clicked.connect(() => {
				this.hide();
			});
			button_box.append(this.ignore_button);
			
			this.append(button_box);
		}
		
		/**
		 * Shows the banner with the specified filename.
		 * 
		 * @param filename The name of the file that has changed
		 */
		public new void show(string filename)
		{
			this.label.label = "File '" + filename + "' has been modified on disk, but you have unsaved changes.";
			this.revealer.reveal_child = true;
		}
		
		/**
		 * Hides the banner.
		 */
		public new void hide()
		{
			this.revealer.reveal_child = false;
		}
	}
}

