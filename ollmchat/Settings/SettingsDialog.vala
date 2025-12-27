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

namespace OLLMchat.Settings
{
	/**
	 * Main settings dialog for displaying and changing configuration.
	 * 
	 * Uses Adw.Dialog with ViewStack/ViewSwitcher for tabs and custom layout
	 * to support fixed action bars outside scrollable content.
	 * Only responsible for displaying and changing configuration, not loading/saving.
	 * Loading is done by the caller before creating the dialog.
	 * Saving is done automatically on close.
	 * 
	 * @since 1.0
	 */
	public class SettingsDialog : Adw.Dialog
	{
		/**
		 * Application interface (provides config and data_dir)
		 */
		public OLLMchat.ApplicationInterface app { get; construct; }
		
		private Settings.ConnectionsPage connections_page;
		private Settings.ModelsPage models_page;
		
		// ViewStack for pages and ViewSwitcher for tabs
		private Adw.ViewStack view_stack;
		private Adw.ViewSwitcher view_switcher;
		
		// ScrolledWindow for pages
		public Gtk.ScrolledWindow scrolled_window { get; private set; }
		
		// Viewport for pages (child of ScrolledWindow)
		public Gtk.Viewport viewport { get; private set; }
		
		// Area for pages to add action bars (fixed at bottom, outside scrollable content)
		public Gtk.Box action_bar_area { get; private set; }
		
		// Track previous visible child for activation/deactivation
		// Initialized to dummy instance so we never have to check for null
		private SettingsPage previous_visible_child { get; set; default = new SettingsPage(); }

		/**
		 * Creates a new SettingsDialog.
		 * 
		 * @param app ApplicationInterface instance (provides config and data_dir)
		 */
		public SettingsDialog(OLLMchat.ApplicationInterface app)
		{
			Object(app: app);
		
			this.title = "Settings";
			this.set_content_width(800);
			this.set_content_height(800);

			// Create main container
			var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			
			// Create ViewStack for pages first
			this.view_stack = new Adw.ViewStack();
			
			// Create header bar with ViewSwitcher for tabs
			var header_bar = new Adw.HeaderBar();
			this.view_switcher = new Adw.ViewSwitcher() {
				stack = this.view_stack,
				policy = Adw.ViewSwitcherPolicy.WIDE
			};
			header_bar.set_title_widget(this.view_switcher);
			main_box.append(header_bar);
			
			// Create scrollable area for pages
			this.scrolled_window = new Gtk.ScrolledWindow() {
				vexpand = true,
				hexpand = true
			};
			// ScrolledWindow automatically wraps non-scrollable children in a Viewport
			this.scrolled_window.set_child(this.view_stack);
			// Get the Viewport that was automatically created
			this.viewport = this.scrolled_window.get_child() as Gtk.Viewport;
			main_box.append(this.scrolled_window);
			
			// Create action bar area (fixed at bottom, outside scrollable content)
			this.action_bar_area = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				visible = false,
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 12
			};
			main_box.append(this.action_bar_area);
			
			// Set main box as dialog content
			this.set_child(main_box);

			// Create models page
			this.models_page = new Settings.ModelsPage(this);
			this.view_stack.add_titled(this.models_page,
				 this.models_page.page_name,
				  this.models_page.page_title);
			// Add action widget to action bar area (initially hidden)
			this.action_bar_area.append(this.models_page.action_widget);
			this.models_page.action_widget.visible = false;

			// Create connections page
			this.connections_page = new Settings.ConnectionsPage(this);
			this.view_stack.add_titled(this.connections_page, 
				this.connections_page.page_name, 
				this.connections_page.page_title);
			// Add action widget to action bar area (initially hidden)
			this.action_bar_area.append(this.connections_page.action_widget);
			this.connections_page.action_widget.visible = false;
			
			// Connect to page visibility to show/hide action widgets
			this.view_stack.notify["visible-child"].connect(this.on_page_changed);
			
			// Initial activation of the default visible page
			this.on_page_changed();

			// Connect closed signal to save config when dialog closes
			this.closed.connect(this.on_closed);
		}
		
		/**
		 * Called when page changes.
		 * 
		 * Manages action widgets visibility in the action bar area.
		 */
		private void on_page_changed()
		{
			// Hide previous page's action widget
			this.previous_visible_child.action_widget.visible = false;

			// Get current page
			var current_page = this.view_stack.get_visible_child() as SettingsPage;
			this.previous_visible_child = current_page;
			
			// Show current page's action widget
			current_page.action_widget.visible = true;
			this.action_bar_area.visible = true;
			
			// Scroll to top when switching tabs
			this.scrolled_window.vadjustment.value = 0;
		}

		/**
		 * Shows the settings dialog and initializes models page.
		 * 
		 * @param parent Parent window to attach the dialog to
		 */
		public void show_dialog(Gtk.Window? parent = null)
		{
			// Refresh models when dialog is shown (every time)
			this.models_page.render_models.begin();
			
			// Present the dialog
			this.present(parent);
		}

		/**
		 * Called when dialog is closed, saves configuration to file.
		 */
		private void on_closed()
		{
			// Save all model options before closing
			this.models_page.save_all_options();
			
			try {
				this.app.config.save();
			} catch (GLib.Error e) {
				GLib.warning("Failed to save config: %s", e.message);
			}
		}
	}
}

