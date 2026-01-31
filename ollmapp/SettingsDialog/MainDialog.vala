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
	public class MainDialog : Adw.Dialog
	{
		/**
		 * Application interface (provides config and data_dir)
		 */
		public OLLMchat.ApplicationInterface app { get; construct; }
		
		private ConnectionsPage connections_page;
		private ModelsPage models_page;
		private ProjectsPage projects_page;
		private ToolsPage tools_page;
		
		// ViewStack for pages and ViewSwitcher for tabs
		private Adw.ViewStack view_stack;
		private Adw.ViewSwitcher view_switcher;
		
		// Area for pages to add action bars (fixed at bottom, outside scrollable content)
		public Gtk.Box action_bar_area { get; private set; }
		
		// Track previous visible child for activation/deactivation
		// Initialized to dummy instance so we never have to check for null
		private SettingsPage previous_visible_child { get; set; default = new SettingsPage(); }
		
		/**
		 * Pull manager instance (shared across all pages)
		 */
		public PullManager pull_manager { get; private set; }
		
		/**
		 * Progress banner for pull operations (displayed above action widgets)
		 */
		private PullManagerBanner progress_banner;
		
		/**
		 * Checking connection dialog (reused for connection verification)
		 */
		private CheckingConnectionDialog checking_connection_dialog;
		
		/**
		 * Current parent window (stored for use in check_all_connections)
		 */
		public OllmchatWindow parent;

		/**
		 * Creates a new MainDialog.
		 * 
		 * @param app ApplicationInterface instance (provides config and data_dir)
		 */
		public MainDialog(OllmchatWindow parent)
		{
			Object(app: parent.app);
			this.parent = parent;
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
			
			// View stack directly in main box; each page has its own ScrolledWindow
			this.view_stack.vexpand = true;
			this.view_stack.hexpand = true;
			main_box.append(this.view_stack);
			
			// Create PullManager instance (shared across all pages)
			this.pull_manager = new PullManager(this.app);
			
			// Create progress banner for pull operations
			this.progress_banner = new PullManagerBanner(this.pull_manager);
			
			// Create action bar area (fixed at bottom, outside scrollable content)
			this.action_bar_area = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				visible = false,
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 12
			};
			// Add progress banner above action widgets (always visible when action bar area is visible)
			this.action_bar_area.prepend(this.progress_banner);
			this.progress_banner.visible = false;
			main_box.append(this.action_bar_area);
			
			// Set main box as dialog content
			this.set_child(main_box);

			// Create models page
			this.models_page = new ModelsPage(this);
			this.view_stack.add_titled(this.models_page,
				 this.models_page.page_name,
				  this.models_page.page_title);
			// Add action widget to action bar area (initially hidden)
			this.action_bar_area.append(this.models_page.action_widget);
			this.models_page.action_widget.visible = false;

			// Create connections page
			this.connections_page = new ConnectionsPage(this);
			this.view_stack.add_titled(this.connections_page, 
				this.connections_page.page_name, 
				this.connections_page.page_title);
			// Add action widget to action bar area (initially hidden)
			this.action_bar_area.append(this.connections_page.action_widget);
			this.connections_page.action_widget.visible = false;
			
			// Create projects page (store bound when dialog is shown via ensure_loaded())
			this.projects_page = new ProjectsPage(this);
			this.view_stack.add_titled(this.projects_page,
				this.projects_page.page_name,
				this.projects_page.page_title);
			this.action_bar_area.append(this.projects_page.action_widget);
			this.projects_page.action_widget.visible = false;

			// Create tools page
			this.tools_page = new ToolsPage(this);
			this.view_stack.add_titled(this.tools_page,
				this.tools_page.page_name,
				this.tools_page.page_title);
			// Add action widget to action bar area (initially hidden)
			this.action_bar_area.append(this.tools_page.action_widget);
			this.tools_page.action_widget.visible = false;
			
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
		 * Progress banner visibility is managed by PullManagerBanner itself.
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
		}

		/**
		 * Shows the settings dialog and initializes models page.
		 * 
		 * @param parent Parent window to attach the dialog to
		 * @param page_name Optional page name to switch to (e.g., "connections", "models")
		 */
		public async void show_dialog(string? page_name = null)
		{
			// Present the main dialog immediately
			
			// Create and show checking connection dialog
			var checking_connection_dialog = new CheckingConnectionDialog(this.parent);
			checking_connection_dialog.show_dialog();

			yield this.check_all_connections();
			
			// Hide checking connection dialog
			checking_connection_dialog.hide_dialog();
			
			// Load tools and configs for tools page (non-blocking)
			this.tools_page.load_tools();
			this.tools_page.load_configs();
			
			// Bind projects list to ProjectManager (once; project_manager not available at dialog creation)
			this.projects_page.load_projects();
			
			// Initialize progress bars for any existing active pulls
			this.progress_banner.initialize_existing_pulls();
			
			// Switch to specified page if provided
			if (page_name != null) {
				this.view_stack.set_visible_child_name(page_name);
			}
			
			// Show checking connection dialog
			//this.parent.checking_connection_dialog.show_dialog();

			// Check version on all connections in the background

			// Hide checking dialog when done
			//this.parent.checking_connection_dialog.hide_dialog();

			// Refresh models after connection checks complete
			this.present(parent);

			// Refresh ConnectionModels first, then render models page
			var parent_window = this.parent as OllmchatWindow;
			if (parent_window != null && parent_window.history_manager != null) {
				yield parent_window.history_manager.connection_models.refresh();
			}
			this.models_page.render_models.begin();
		}

		/**
		 * Called when dialog is closed, saves configuration to file.
		 */
		private void on_closed()
		{
			// Save all model options before closing
			this.models_page.save_all_options();
			
			// Apply all connection values from UI before closing
			this.connections_page.apply_config();
			
			// Check version on all connections and update is_working flag
			this.check_all_connections.begin();
			
			this.app.config.save();
			
			// Emit changed signal to notify components that config has been updated
			this.app.config.changed();
		}

		/**
		 * Checks version on all connections and updates is_working flag.
		 */
		private async void check_all_connections()
		{
			
			
			foreach (var entry in this.app.config.connections.entries) {
				var connection = entry.value;
				try {
					// Test connection by calling models endpoint directly with short timeout
					var original_timeout = connection.timeout;
					connection.timeout = 5;  // 5 seconds - connection check should be quick
					try {
						var models_call = new OLLMchat.Call.Models(connection);
						yield models_call.exec_models();
						connection.is_working = true;
					} finally {
						connection.timeout = original_timeout;
					}
				} catch (Error e) {
					connection.is_working = false;
					GLib.debug("Connection %s is not working: %s", connection.url, e.message);
				}
			}
			
		}
	}
}
