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

namespace OLLMcoder
{
	/**
	 * Horizontal box widget containing buttons for file approval workflow.
	 * 
	 * Contains:
	 * - Approve button (approves selected file)
	 * - Reject button (reverts selected file)
	 * - Next/popover button (existing functionality with task-due icon, popover on mouseover)
	 * 
	 * Monitors ReviewFiles and updates button visibility accordingly.
	 */
	public class Approvals : Gtk.Box
	{
		private OLLMfiles.ProjectManager project_manager;
		
		// Buttons (in order: approve, reject, next)
		private Gtk.Button approve_button;
		private Gtk.Button reject_button;
		private Gtk.Button next_button;  // Existing popover button functionality
		
		// Existing popover functionality (moved from button to next_button)
		private Gtk.Popover popover;
		private Gtk.ListView list_view;
		private Gtk.SingleSelection selection;
		private List.SortedList<OLLMfiles.File> sorted_model;
		private Gtk.EventControllerMotion button_motion;
		private Gtk.EventControllerMotion popover_motion;
		private bool blocking_selection_handler = false;
		private uint hide_timeout_id = 0;
		private uint cooldown_timeout_id = 0;
		private bool in_cooldown = false;
		private ulong? review_files_handler_id = null;
		
		/**
		 * Currently selected file (or null).
		 */
		private OLLMfiles.File? selected_file { get; set; default = null; }
		
		/**
		 * Emitted when a file is selected/clicked.
		 */
		public signal void file_selected(OLLMfiles.File file);
		
		/**
		 * Constructor.
		 * 
		 * @param project_manager The ProjectManager instance (required)
		 */
		public Approvals(OLLMfiles.ProjectManager project_manager)
		{
			Object(orientation: Gtk.Orientation.HORIZONTAL);
			this.project_manager = project_manager;
			
			// Create approve button
			this.approve_button = new Gtk.Button.with_label("Approve") {
				css_classes = {"oc-approve", "suggested-action"},
				visible = false
			};
			this.approve_button.clicked.connect(this.on_approve_clicked);
			this.append(this.approve_button);
			
			// Create reject button
			this.reject_button = new Gtk.Button.with_label("Reject") {
				css_classes = {"oc-reject"},
				tooltip_text = "Revert file to previous version",
				visible = false
			};
			this.reject_button.clicked.connect(this.on_reject_clicked);
			this.append(this.reject_button);
			
			// Create next/popover button with task-due icon
			this.next_button = new Gtk.Button() {
				icon_name = "task-due",
				visible = false
			};
			
			// Create popover with autohide disabled
			this.popover = new Gtk.Popover() {
				autohide = false
			};
			this.popover.set_parent(this.next_button);
			
			// Create empty ListStore as initial model (will be replaced when project is available)
			var empty_store = new GLib.ListStore(typeof(OLLMfiles.File));
			
			// Create sorted model with empty store and sorter
			this.sorted_model = this.create_sorted_model(empty_store);
			
			// Create selection model with sorted model
			this.selection = new Gtk.SingleSelection(this.sorted_model) {
				autoselect = false,
				can_unselect = true,
				selected = Gtk.INVALID_LIST_POSITION
			};
			
			// Create ListView with selection model and factory
			this.list_view = new Gtk.ListView(this.selection, this.create_factory());
			
			// Add ListView to popover
			var scrolled = new Gtk.ScrolledWindow();
			scrolled.set_child(this.list_view);
			this.popover.set_child(scrolled);
			
			// Connect to active_project_changed signal
			this.project_manager.active_project_changed.connect(this.activate_project);
			
			// Connect to active_file_changed signal (internal handling)
			this.project_manager.active_file_changed.connect(this.on_active_file_changed);
			
			// Set up motion controllers on next_button
			this.button_motion = new Gtk.EventControllerMotion();
			this.button_motion.enter.connect(() => {
				if (this.in_cooldown) {
					return;
				}
				this.cancel_hide_timeout();
				this.popover.popup();
				this.update_popover_size();
			});
			this.button_motion.leave.connect(() => {
				if (this.in_cooldown) {
					return;
				}
				this.schedule_hide();
			});
			this.next_button.add_controller(this.button_motion);
			
			this.popover_motion = new Gtk.EventControllerMotion();
			this.popover_motion.enter.connect(() => {
				this.cancel_hide_timeout();
			});
			this.popover_motion.leave.connect(() => {
				this.schedule_hide();
			});
			(this.popover as Gtk.Widget).add_controller(this.popover_motion);
			
			// Connect to next_button clicked signal
			this.next_button.clicked.connect(() => {
				this.popover.popdown();
				this.start_cooldown();
			});
			
			// Append next_button to box (third button)
			this.append(this.next_button);
			
			// Connect to popover closed signal (fires when clicking outside)
			this.popover.closed.connect(() => {
				this.cancel_hide_timeout();
			});
			
			// Connect to selection changed signal (fires for both user clicks and programmatic changes)
			this.selection.selection_changed.connect(() => {
				if (this.blocking_selection_handler) {
					return;
				}
				this.update_selected_file();
			});
			
			// Initialize with current active_project
			this.activate_project(this.project_manager.active_project);
			
			// Initially hide button
			this.visible = false;
		}
		
		/**
		 * Handle active file change (internal).
		 * 
		 * Updates selection when active file changes:
		 * - If file is in ReviewFiles, select it (blocks handler, no signal emitted)
		 * - If file is not in ReviewFiles, clear selection internally
		 */
		private void on_active_file_changed(OLLMfiles.File? file)
		{
			if (file == null || this.project_manager.active_project == null) {
				// No file active or no project: clear selection internally
				this.clear_selection();
				return;
			}
			
			// Check if file is in ReviewFiles
			if (this.project_manager.active_project.review_files.file_map.has_key(file.path)) {
				// File is in ReviewFiles: select it (blocks handler, no signal emitted)
				this.select_file(file);
				return;
			} 
			// File is not in ReviewFiles: clear selection internally
			this.clear_selection();
		}
		
		/**
		 * Handle active project change.
		 */
		private void activate_project(OLLMfiles.Folder? project)
		{
			// Clear handler first
			if (this.review_files_handler_id != null) {
				this.review_files_handler_id = null;
			}
			
			// Create empty ListStore for when project is null
			var empty_store = new GLib.ListStore(typeof(OLLMfiles.File));
			
			// Create sorted model with empty store (or project's review_files if available)
			var source_model = project != null ?
				project.review_files as GLib.ListModel : empty_store;
			
			this.sorted_model = this.create_sorted_model(source_model);
			this.selection.model = this.sorted_model;
			this.visible = false;
			
			if (project == null) {
				return;
			}
			
			// Connect to review_files.items_changed signal
			this.review_files_handler_id = project.review_files.items_changed.connect(() => {
				this.update_button_visibility();
				
				// Check if selected file still needs approval
				if (this.selected_file == null) {
					return;
				}
				if (!this.selected_file.is_need_approval) {
					// Selected file no longer needs approval: clear selection internally
					this.clear_selection();
				}
			});
			
			// Update button visibility
			this.update_button_visibility();
		}
		
		/**
		 * Update button visibility based on review_files count and selected file.
		 */
		private void update_button_visibility()
		{
			if (this.project_manager.active_project == null) {
				this.visible = false;
				this.next_button.visible = false;
				this.approve_button.visible = false;
				this.reject_button.visible = false;
				return;
			}
			
			// Next button visibility: based on ReviewFiles countclear_selection
			this.next_button.visible = (
				this.project_manager.active_project.review_files.get_n_items() > 0);
			
			// Approve and reject button visibility: both require selected file
			this.approve_button.visible = (this.selected_file != null);
			this.reject_button.visible = (this.selected_file != null);
			
			// Overall widget visibility: show if any button should be visible
			this.visible = (this.next_button.visible || this.approve_button.visible);
		}
		
		/**
		 * Create sorted model with sorter for last_modified (descending).
		 */
		private OLLMcoder.List.SortedList<OLLMfiles.File> create_sorted_model(GLib.ListModel source_model)
		{
			var sorter = new Gtk.CustomSorter((a, b) => {
				var file_a = a as OLLMfiles.File;
				var file_b = b as OLLMfiles.File;
				return file_a.last_modified > file_b.last_modified ? -1 :
					(file_a.last_modified < file_b.last_modified ? 1 : 0);
			});
			
			// Filter that matches all items (no filtering, just sorting)
			var filter = new Gtk.CustomFilter((item) => {
				return true;
			});
			
			return new OLLMcoder.List.SortedList<OLLMfiles.File>(source_model, sorter, filter);
		}
		
		/**
		 * Create factory for list items.
		 */
		private Gtk.ListItemFactory create_factory()
		{
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null) {
					return;
				}
				
				var label = new Gtk.Label("") {
					use_markup = true,
					halign = Gtk.Align.START,
					ellipsize = Pango.EllipsizeMode.END
				};
				list_item.child = label;
			});
			factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				var file = list_item.item as OLLMfiles.File;
				if (file == null) {
					return;
				}
				var label = list_item.child as Gtk.Label;
				if (label == null) {
					return;
				}
				
				// Bind to properties
				file.bind_property("display-approval-text", label, "label",
					GLib.BindingFlags.SYNC_CREATE);
				file.bind_property("display-approval-tooltip", label, "tooltip-text",
					GLib.BindingFlags.SYNC_CREATE);
			});
			return factory;
		}
		
		/**
		 * Programmatically select a file (blocks handler).
		 */
		public void select_file(OLLMfiles.File file)
		{
			this.blocking_selection_handler = true;
			
			if (this.project_manager.active_project == null) {
				this.blocking_selection_handler = false;
				return;
			}
			
			// Get file from review_files (verifies it exists and gets the actual object)
			var review_file = this.project_manager.active_project.review_files.file_map.get(
					file.path);
			if (review_file == null) {
				this.blocking_selection_handler = false;
				return;
			}
			
			// Find position in sorted model using find_position
			uint position = this.sorted_model.find_position(review_file);
			if (position != Gtk.INVALID_LIST_POSITION) {
				this.selection.selected = position;
				this.selected_file = review_file;
			}
			
			this.blocking_selection_handler = false;
		}
		
		/**
		 * Select next file in list.
		 */
		private void select_next()
		{
			uint current = this.selection.selected;
			uint n_items = this.sorted_model.get_n_items();
			
			if (n_items == 0) {
				return;
			}
			
			uint next = current == Gtk.INVALID_LIST_POSITION ? 0 :
				(current < n_items - 1 ? current + 1 : 0);
			
			if (next != Gtk.INVALID_LIST_POSITION) {
				this.selection.selected = next;
			}
		}
		
		/**
		 * Clear selection (blocks handler).
		 */
		private void clear_selection()
		{
			this.blocking_selection_handler = true;
			this.selection.unselect_all();
			this.selected_file = null;
			this.blocking_selection_handler = false;
		}
		
		/**
		 * Update selected_file from current selection.
		 */
		private void update_selected_file()
		{
			if (this.selection.selected == Gtk.INVALID_LIST_POSITION) {
				this.selected_file = null;
				this.update_button_visibility();
				return;
			}
			
			var file = this.sorted_model.get_item_typed(this.selection.selected);
			this.selected_file = file;
			this.file_selected(file);
			this.update_button_visibility();
		}
		
		/**
		 * Handle approve button click.
		 */
		private void on_approve_clicked()
		{
			// Disable buttons during operation
			this.approve_button.sensitive = false;
			this.reject_button.sensitive = false;
			
			// Approve file (handles FileHistory approval and database updates)
			this.selected_file.approve();
			
			// Refresh ReviewFiles (file will be removed)
			this.project_manager.active_project.refresh_review();
			
			// Re-enable buttons and update visibility
			this.approve_button.sensitive = true;
			this.reject_button.sensitive = true;
			this.update_button_visibility();
		}
		
		/**
		 * Handle reject button click.
		 */
		private void on_reject_clicked()
		{
			// Disable buttons during operation
			this.approve_button.sensitive = false;
			this.reject_button.sensitive = false;
			
			// Revert the file (handles FileHistory revert and database updates)
			this.selected_file.revert.begin((obj, res) => {
				try {
					this.selected_file.revert.end(res);
					
					// Refresh ReviewFiles (file may be removed or updated)
					this.project_manager.active_project.refresh_review();
					
					// Re-enable buttons and update visibility
					
				} catch (GLib.Error e) {
					GLib.warning("Failed to revert file: %s", e.message);
					// Re-enable buttons on error
				
				}
				this.approve_button.sensitive = true;
				this.reject_button.sensitive = true;
				this.update_button_visibility();
			});
		}
		
		/**
		 * Adjust popover height based on list size.
		 */
		private void update_popover_size()
		{
			uint n_items = this.sorted_model.get_n_items();
			if (n_items == 0) {
				return;
			}
			
			// Calculate height: min 100px, max 400px, ~30px per item
			int calculated_height = (int)(n_items * 30);
			calculated_height = calculated_height < 100 ? 100 :
				(calculated_height > 400 ? 400 : calculated_height);
			
			// Set size request on popover content
			var child = this.popover.get_child();
			if (child != null) {
				child.set_size_request(-1, calculated_height);
			}
		}
		
		/**
		 * Cancel pending hide timeout.
		 */
		private void cancel_hide_timeout()
		{
			if (this.hide_timeout_id != 0) {
				GLib.Source.remove(this.hide_timeout_id);
				this.hide_timeout_id = 0;
			}
		}
		
		/**
		 * Schedule popover to hide in 3 seconds.
		 */
		private void schedule_hide()
		{
			this.cancel_hide_timeout();
			this.hide_timeout_id = GLib.Timeout.add_seconds(3, () => {
				this.popover.popdown();
				this.hide_timeout_id = 0;
				return false;
			});
		}
		
		/**
		 * Start 3 second cooldown after button click.
		 */
		private void start_cooldown()
		{
			if (this.cooldown_timeout_id != 0) {
				GLib.Source.remove(this.cooldown_timeout_id);
			}
			
			this.in_cooldown = true;
			this.cooldown_timeout_id = GLib.Timeout.add_seconds(3, () => {
				this.in_cooldown = false;
				this.cooldown_timeout_id = 0;
				return false;
			});
		}
		
	}
}
