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
		
		// Models page action bar (shown only when Models tab is active)
		private Gtk.Box models_action_box;
		private Gtk.SearchBar models_search_bar;
		private Gtk.SearchEntry models_search_entry;
		private Gtk.Button models_add_btn;
		private Gtk.Button models_refresh_btn;

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

			// Create models action bar (initially hidden)
			this.create_models_action_bar();

			// Create connections page
			this.connections_page = new Settings.ConnectionsPage(this);
			this.add(this.connections_page);

			// Create models page
			this.models_page = new Settings.ModelsPage(this);
			this.add(this.models_page);
			
			// Connect to page visibility to show/hide action bar
			this.models_page.notify["visible"].connect(this.on_models_page_visibility_changed);
			this.connections_page.notify["visible"].connect(this.on_connections_page_visibility_changed);
			
			// Initial visibility check
			this.update_models_action_bar_visibility();

			// Connect closed signal to save config when dialog closes
			this.closed.connect(this.on_closed);
		}
		
		/**
		 * Creates the models page action bar with search and buttons.
		 */
		private void create_models_action_bar()
		{
			// Create horizontal action bar
			this.models_action_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 12,
				visible = false
			};

			// Create search bar (always visible when shown)
			this.models_search_bar = new Gtk.SearchBar();
			this.models_search_entry = new Gtk.SearchEntry() {
				placeholder_text = "Search Models",
				hexpand = true
			};
			this.models_search_entry.changed.connect(() => {
				if (this.models_page != null) {
					this.models_page.search_filter = this.models_search_entry.text;
					this.models_page.filter_models(this.models_search_entry.text);
				}
			});
			this.models_search_bar.connect_entry(this.models_search_entry);
			this.models_search_bar.set_child(this.models_search_entry);
			// Make search bar always visible
			this.models_search_bar.set_key_capture_widget(this);
			this.models_search_bar.set_search_mode(true);
			this.models_action_box.append(this.models_search_bar);

			// Create Add Model button (placeholder - not implemented)
			this.models_add_btn = new Gtk.Button.with_label("Add Model") {
				css_classes = {"suggested-action"},
				sensitive = false,
				tooltip_text = "Not yet implemented"
			};
			this.models_action_box.append(this.models_add_btn);

			// Create Refresh button
			this.models_refresh_btn = new Gtk.Button.with_label("Refresh") {
				css_classes = {"suggested-action"}
			};
			this.models_refresh_btn.clicked.connect(() => {
				if (this.models_page != null) {
					this.models_page.render_models.begin();
				}
			});
			this.models_action_box.append(this.models_refresh_btn);
			
			// Add action bar to dialog (outside scrollable area)
			// We'll add it as a child of the dialog's content area
			// Note: Adw.PreferencesDialog doesn't have a direct way to add widgets outside pages,
			// so we'll need to use a workaround - add it to a header bar or use extra-child
			// For now, let's try adding it as an extra child if available, or we might need
			// to restructure to use a custom layout
			// Actually, let's check if we can use set_extra_child or similar
		}
		
		/**
		 * Updates visibility of models action bar based on which page is visible.
		 */
		private void update_models_action_bar_visibility()
		{
			// Show action bar only when models page is visible
			this.models_action_box.visible = (this.models_page != null && this.models_page.visible);
		}
		
		/**
		 * Called when models page visibility changes.
		 */
		private void on_models_page_visibility_changed()
		{
			this.update_models_action_bar_visibility();
		}
		
		/**
		 * Called when connections page visibility changes.
		 */
		private void on_connections_page_visibility_changed()
		{
			this.update_models_action_bar_visibility();
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

