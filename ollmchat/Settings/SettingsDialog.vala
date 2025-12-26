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
	 * Uses Adw.PreferencesDialog with multiple Adw.PreferencesPage objects for tabs.
	 * Only responsible for displaying and changing configuration, not loading/saving.
	 * Loading is done by the caller before creating the dialog.
	 * Saving is done automatically on close.
	 * 
	 * @since 1.0
	 */
	public class SettingsDialog : Adw.PreferencesDialog
	{
		/**
		 * Reference to configuration object (contains connections map)
		 */
		public OLLMchat.Settings.Config2 config { get; construct; }
		
		// `models_list` (Gee.List<ModelInfo>?) - List of available models from all connections (commented out until model tab is added)
		// `model_manager` (ModelManager?) - Optional ModelManager for managing model list (if created) (commented out until model tab is added)
		
		// `refresh_models()` - Emitted when models need to be refreshed (main window can connect to this) (commented out until model tab is added)
		
		private Settings.ConnectionsPage connections_page;
		private Settings.ModelsPage models_page;
		
		// Area for pages to add action bars (outside scrollable content)
		public Gtk.Box action_bar_area { get; private set; }

		/**
		 * Creates a new SettingsDialog.
		 * 
		 * @param config Configuration object (should be loaded by caller before creating dialog)
		 */
		public SettingsDialog(OLLMchat.Settings.Config2 config)
		{
			Object(config: config);
		
			this.title = "Settings";
			this.set_content_width(800);
			this.set_content_height(600);

			// Create action bar area (initially empty, pages can add widgets here)
			this.action_bar_area = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				visible = false
			};

			// Create connections page
			this.connections_page = new Settings.ConnectionsPage(this);
			this.add(this.connections_page);

			// Create models page (will add its action bar to action_bar_area)
			this.models_page = new Settings.ModelsPage(this);
			this.add(this.models_page);
			
			// Connect to page visibility to show/hide action bar area
			this.models_page.notify["visible"].connect(this.on_page_visibility_changed);
			this.connections_page.notify["visible"].connect(this.on_page_visibility_changed);
			
			// Wrap dialog content to add fixed header area
			// Get the current child (the PreferencesDialog's internal content)
			var original_child = this.get_child();
			if (original_child != null) {
				// Unparent the original child so we can reparent it
				original_child.unparent();
				
				// Create a wrapper box with action bar area at top and original content below
				var wrapper_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
				
				// Add action bar area at top (fixed, not scrollable)
				wrapper_box.append(this.action_bar_area);
				
				// Add original content below (this will be scrollable)
				wrapper_box.append(original_child);
				
				// Set the wrapper as the new child
				this.set_child(wrapper_box);
			}
			
			// Initial visibility check
			this.update_action_bar_visibility();

			// Connect closed signal to save config when dialog closes
			this.closed.connect(this.on_closed);
		}
		
		/**
		 * Updates visibility of action bar area based on which page is visible.
		 */
		private void update_action_bar_visibility()
		{
			// Show action bar area only when models page is visible
			this.action_bar_area.visible = (this.models_page != null && this.models_page.visible);
		}
		
		/**
		 * Called when page visibility changes.
		 */
		private void on_page_visibility_changed()
		{
			this.update_action_bar_visibility();
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
				this.config.save();
			} catch (GLib.Error e) {
				GLib.warning("Failed to save config: %s", e.message);
			}
		}
	}
}

