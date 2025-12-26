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
	 * Uses Adw.PreferencesDialog with Adw.ViewStack for tabs.
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
		
		private Adw.ViewStack view_stack;
		private Settings.ConnectionsPage connections_page;
		private Settings.ModelsPage models_page;

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

			// Create view stack for tabs
			this.view_stack = new Adw.ViewStack();

			// Create connections page
			this.connections_page = new Settings.ConnectionsPage(this);
			this.view_stack.add_titled(
				this.connections_page,
				"connections",
				"Connections"
			);

			// Create models page
			this.models_page = new Settings.ModelsPage(this);
			this.view_stack.add_titled(
				this.models_page,
				"models",
				"Models"
			);

			// Add view stack to a preferences page
			var page = new Adw.PreferencesPage();
			var group = new Adw.PreferencesGroup();
			group.add(this.view_stack);
			page.add(group);
			this.add(page);

			// Connect closed signal to save config when dialog closes
			this.closed.connect(this.on_closed);
		}

		/**
		 * Shows the settings dialog and initializes models page.
		 * 
		 * @param parent Parent window to attach the dialog to
		 */
		public void show(Gtk.Window? parent = null)
		{
			// Refresh models when dialog is shown (every time)
			this.models_page.render_models.begin();
			
			// Present the dialog
			if (parent != null) {
				this.present(parent);
			} else {
				this.present();
			}
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

