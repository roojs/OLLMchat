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
	 * Source view component with code editor.
	 * 
	 * Provides a code editor with project and file selection dropdowns.
	 * Manages buffer switching, language detection, and state persistence.
	 * 
	 * FIXME: Error handling and user interaction
	 * ===========================================
	 * Currently, many operations that can fail (file reading, database operations, etc.)
	 * silently fail or only log warnings. We need proper error handling with user
	 * interaction (dialogs, notifications) for:
	 * - File read/write failures
	 * - Database operation failures
	 * - File system errors
	 * - Buffer modification conflicts
	 * - Session restoration failures
	 * 
	 * Operations like refresh_file(), restore_active_state(), and file loading should
	 * provide user feedback and allow recovery/retry options.
	 */
	public class SourceView : Gtk.Box
	{
		public OLLMfiles.ProjectManager manager { get; private set; }
		private ProjectDropdown project_dropdown;
		private FileDropdown file_dropdown;
		private Gtk.Button save_button;
		private Approvals? approvals = null;
		private GtkSource.View source_view;
		private Gtk.ScrolledWindow scrolled_window;
		
		/**
		* Timeout source for debouncing scroll position saves.
		*/
		private uint? scroll_save_timeout_id = null;
		
		/**
		* Search-related components.
		*/
		private Gtk.Box search_bar;
		private Gtk.SearchEntry search_entry;
		private Gtk.Label search_results_label;
		private Gtk.Button search_next_button;
		private Gtk.Button search_back_button;
		private GtkSource.SearchContext? search_context = null;
		private int last_search_end = 0;
		private Gtk.CheckButton case_sensitive_checkbox;
		private Gtk.CheckButton regex_checkbox;
		private Gtk.CheckButton multiline_checkbox;
			
		/**
		 * Currently active file.
		 */
		public OLLMfiles.File? current_file { get; private set; default = null; }
		
		/**
		 * Currently active project (folder with is_project = true).
		 */
		public OLLMfiles.Folder? current_project {
			get { return this.manager.active_project; }
		}
		
		/**
		 * Current buffer.
		 */
		public GtkSource.Buffer? current_buffer {
			get { return this.source_view.buffer as GtkSource.Buffer; }
		}
		
		/**
		 * Signal handler ID for delete_id notification on current file.
		 * Used to disconnect the handler when switching files.
		 */
		private ulong? delete_id_handler_id = null;
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public SourceView(OLLMfiles.ProjectManager manager)
		{
			Object(orientation: Gtk.Orientation.VERTICAL);
			this.manager = manager;
		
			// Create header bar with dropdowns
			var header_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				margin_start = 5,
				margin_end = 5,
				margin_top = 0,
				margin_bottom = 0
			};
			
			// Project dropdown (left-aligned)
			this.project_dropdown = new ProjectDropdown(this.manager);
			this.project_dropdown.project_selected.connect(this.on_project_selected);
			header_bar.append(this.project_dropdown);
			
			// File dropdown (next to project)
			this.file_dropdown = new FileDropdown();
			this.file_dropdown.file_selected.connect(this.on_file_selected);
			// Hide file dropdown initially (no project selected)
			this.file_dropdown.visible = false;
			header_bar.append(this.file_dropdown);
			
			// Spacer to push save button to the right
			var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			};
			header_bar.append(spacer);
			
			// Save button (right-aligned)
			this.save_button = new Gtk.Button.from_icon_name("media-floppy") {
				tooltip_text = "Save file",
				hexpand = false,
				sensitive = false  // Disabled until file is open
			};
			this.save_button.clicked.connect(() => {
				this.save_file.begin();
			});
			header_bar.append(this.save_button);
			
			// Create Approvals widget with ProjectManager
			this.approvals = new Approvals(this.manager);
			
			// Add approvals bar to header bar (after save button)
			header_bar.append(this.approvals);
			
			// Connect file_selected signal to open files
			this.approvals.file_selected.connect((file) => {
				this.open_file.begin(file, null);
			});
			
			this.append(header_bar);
			
			// Create ScrolledWindow for code editor
			this.scrolled_window = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = true
			};
			
			// Create SourceView
			this.source_view = new GtkSource.View() {
				editable = true,
				cursor_visible = true,
				show_line_numbers = true,
				highlight_current_line = true,
				show_line_marks = true,
				wrap_mode = Gtk.WrapMode.NONE,
				hexpand = true,
				vexpand = true
			};
			// Add CSS class for monospace font styling
			this.source_view.add_css_class("source-view");
			
			this.scrolled_window.set_child(this.source_view);
			// Hide sourceview initially until a file is opened
			this.scrolled_window.visible = false;
			this.append(this.scrolled_window);
			
			// Create search footer bar (will be hidden initially)
			this.create_search_bar();
			
			// Connect to buffer modified signal
			var source_buffer = this.source_view.buffer as GtkSource.Buffer;
			source_buffer.notify["modified"].connect(() => {
				if (this.current_file != null) {
					this.current_file.is_unsaved = source_buffer.get_modified();
				}
			});
			
			// TODO: Clipboard feature needs proper design - see TODO.md
			// Connect to copy-clipboard signal to store file reference metadata
			// this.source_view.copy_clipboard.connect(() => {
			// 	this.on_copy_clipboard();
			// });
			
			// Connect to scroll events to track scroll position
			var vadjustment = this.scrolled_window.vadjustment;
			if (vadjustment != null) {
				vadjustment.value_changed.connect(() => {
					this.on_scroll_changed();
				});
			}
			
			// Add scroll controller to prevent background scrolling when dropdown popups are visible
			var scroll_blocker = new Gtk.EventControllerScroll(
				Gtk.EventControllerScrollFlags.BOTH_AXES |
				Gtk.EventControllerScrollFlags.DISCRETE |
				Gtk.EventControllerScrollFlags.KINETIC
			);
			scroll_blocker.scroll.connect((dx, dy) => {
				// If any dropdown popup is visible, stop scroll events from reaching the source view
				if (this.project_dropdown.popup.visible || this.file_dropdown.popup.visible) {
					return true;
				}
				return false;
			});
			scroll_blocker.propagation_phase = Gtk.PropagationPhase.CAPTURE;
			this.add_controller(scroll_blocker);
			
			// Add keyboard shortcuts
			var controller = new Gtk.EventControllerKey();
			controller.key_pressed.connect((keyval, keycode, state) => {
				var ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
				var shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
				
				if (ctrl && keyval == Gdk.Key.s) {
					this.save_file.begin();
					return true;
				}
				
				if (ctrl && keyval == Gdk.Key.f) {
					// Focus search entry
					this.search_entry.grab_focus();
					this.search_entry.select_region(0, -1);
					return true;
				}
				
				if (ctrl && keyval == Gdk.Key.g) {
					if (shift) {
						// Ctrl+Shift+G: backward search
						this.backward_search(true);
					} else {
						// Ctrl+G: forward search
						this.forward_search(true);
					}
					return true;
				}
				
				return false;
			});
			this.add_controller(controller);
		
			
			// Editor state restoration should be called from view switching code
			// after projects are loaded from database
		}
		
		/**
		 * Apply manager state to UI.
		 * 
		 * Reads active project and file from manager properties and applies them to the UI.
		 * This method should only restore UI state - all data loading happens before calling this.
		 * 
		 * Uses manager.active_project and manager.active_file properties.
		 */
		public async void apply_manager_state()
		{
			// Only apply UI state from manager properties - all data is already loaded
			// Use manager's active_project and active_file properties
			
			if (this.manager.active_project == null) {
				return;
			}
			
			// Check if we're already on the same project - if so, don't change active file
			bool same_project = (this.project_dropdown.selected_project != null && 
								this.project_dropdown.selected_project.path == this.manager.active_project.path);
			
			// Project is already activated by restore_active_state(), just update UI
			// Update file dropdown's project
			this.file_dropdown.project = this.manager.active_project;
			
			// Update project dropdown placeholder only if it's different (avoid unnecessary updates)
			// Note: on_selected() already handles clearing entry and setting placeholder,
			// so we only need to update if it's different to avoid duplicate work
			var expected_placeholder = this.manager.active_project.path_basename;
			if (this.project_dropdown.placeholder_text != expected_placeholder) {
				this.project_dropdown.placeholder_text = expected_placeholder;
			}
			
			// If we're switching to the same project, don't change the active file
			if (same_project) {
				return;
			}
			
			if (this.manager.active_file == null) {
				return;
			}
			
			// Open file (will restore cursor/scroll position from file.cursor_line, etc.)
			yield this.open_file(this.manager.active_file);
		}
		
		/**
		 * Handle project selection change.
		 */
		private void on_project_selected(OLLMfiles.Folder? project)
		{
			if (project == null) {
				// Hide file dropdown when no project is selected
				this.file_dropdown.visible = false;
				return;
			}
			
			// Show file dropdown when project is selected
			this.file_dropdown.visible = true;
			
			// Lock file dropdown during project change
			this.file_dropdown.sensitive = false;
			this.file_dropdown.add_css_class("loading");
			this.open_project.begin(project, (obj, res) => {
				this.open_project.end(res);
				// Unlock file dropdown after project change completes
				this.file_dropdown.sensitive = true;
				this.file_dropdown.remove_css_class("loading");
				// Switch focus to file dropdown entry after project is opened
				GLib.Idle.add(() => {
					// Access the entry through a method or make it accessible
					// For now, just grab focus on the file dropdown widget
					this.file_dropdown.grab_focus();
					return false;
				});
			});
		}
		
		/**
		 * Handle file selection change.
		 */
		private void on_file_selected(OLLMfiles.File? file)
		{
			if (file == null) {
				// Disconnect delete_id signal handler when no file is selected
				this.disconnect_delete_id_handler();
				
				// Set default placeholder when no file is selected
				this.file_dropdown.placeholder_text = "Select file...";
				// Hide sourceview, search bar and disable save button when no file
				this.scrolled_window.visible = false;
				this.search_bar.visible = false;
				this.save_button.sensitive = false;
				return;
			}
			
			// If file hasn't changed, no need to do anything
			if (this.current_file != null && this.current_file.path == file.path) {
				return;
			}
			
			// Lock source view during file load
			this.source_view.editable = false;
			this.source_view.add_css_class("loading");
			this.file_dropdown.placeholder_text = "Loading..";

			
			this.open_file.begin(file, null, (obj, res) => {
				this.open_file.end(res);
				// Unlock source view after file load completes
				this.source_view.editable = true;
				this.source_view.remove_css_class("loading");
			});
		}
		
		/**
		 * Open/switch to a file, optionally navigate to a specific line.
		 * 
		 * @param file The file to open
		 * @param line_number Optional line number to navigate to (overrides saved position)
		 */
		public async void open_file(OLLMfiles.File file, int? line_number = null)
		{
			// Save current file state if switching away
			if (this.current_file != null && this.current_file != file) {
				this.save_current_file_state();
				// Disconnect delete_id signal handler from previous file
				this.disconnect_delete_id_handler();
			}
			
			// Notify manager to activate file
			this.manager.activate_file(file);
			
			// Ensure buffer exists and is a GtkSource.Buffer (GtkSourceFileBuffer extends it)
			this.manager.buffer_provider.create_buffer(file);
			
			// Get GtkSource.Buffer (GtkSourceFileBuffer extends it)
			var gtk_buffer = file.buffer as GtkSource.Buffer;
			 
			
			// Load file content asynchronously if buffer hasn't been loaded
			if (!file.buffer.is_loaded) {
				try {
					yield file.buffer.read_async();
				} catch (Error e) {
					GLib.warning("Failed to read file %s: %s", file.path, e.message);
					gtk_buffer.text = "";
				}
			}
			
			// Switch view to file's buffer (GtkSourceFileBuffer IS a GtkSource.Buffer)
			this.source_view.set_buffer(gtk_buffer);
			this.current_file = file;
			
			// Connect to delete_id signal to monitor file deletion
			// Disconnect any existing handler first
			this.disconnect_delete_id_handler();
			// Connect to notify::delete_id signal
			this.delete_id_handler_id = file.notify["delete-id"].connect(() => {
				if (file.delete_id > 0) {
					this.handle_file_deleted(file);
				}
			});
			
			// Show sourceview and search bar when file is opened (even if deleted)
			this.scrolled_window.visible = true;
			this.search_bar.visible = true;
			
			// Check if file is already deleted
			if (file.delete_id > 0) {
				this.handle_file_deleted(file);
			} else {
				// Remove deleted CSS class if it was set
				this.source_view.remove_css_class("file-deleted");
				
				// Enable save button when file is open
				this.save_button.sensitive = true;
				
				// Make editor editable
				this.source_view.editable = true;
			}
			
			// Reset search context when switching files
			this.search_context = null;
			this.last_search_end = 0;
			if (this.search_entry != null) {
				this.search_entry.text = "";
			}
			this.update_search_results();
			
			// Restore or set cursor position
			if (line_number != null) {
				this.navigate_to_line(line_number);
			} else {
				this.restore_cursor_position(file);
				this.restore_scroll_position(file);
			}
			
			// Update last_viewed timestamp when file is actually opened (saved to database)
			var now = new DateTime.now_local();
			file.last_viewed = now.to_unix();
			file.last_modified = file.mtime_on_disk();
			// Save to database (metadata-only change - cursor/scroll not changed yet)
			this.manager.on_file_metadata_change(file);
			
			// Update placeholder text with file basename
			// Note: selected_file is now read-only and set when dialog closes
			this.file_dropdown.placeholder_text = Path.get_basename(file.path);
		}
		
		/**
		 * Open/switch to a project.
		 * 
		 * @param project The project to open
		 */
	public async void open_project(OLLMfiles.Folder project)
	{
		// Notify manager to activate project (this will emit signal even if already active)
		yield this.manager.activate_project(project);
		
		// Update file dropdown's project
		this.file_dropdown.project = project;
		
		// Disabled: Don't set project dropdown selection programmatically
		// this.project_dropdown.selected_project = project;
		
		// Update placeholder text with project name (use path_basename to match on_selected)
		this.project_dropdown.placeholder_text = project.path_basename;
			
			// Find and trigger active file (or null if none)
			var active_file = project.project_files.get_active_file();
			this.on_file_selected(active_file);
		}
		
		/**
		 * Navigate to a specific line in the current file.
		 * 
		 * @param line_number The line number to navigate to (0-based)
		 */
		public void navigate_to_line(int line_number)
		{
			var buffer = this.source_view.buffer;
			
			Gtk.TextIter iter;
			if (buffer.get_iter_at_line(out iter, line_number)) {
				buffer.place_cursor(iter);
				this.source_view.scroll_to_iter(iter, 0.0, false, 0.0, 0.5);
			}
		}
		
		/**
		 * Refresh current file from disk (if no unsaved changes).
		 * 
		 * FIXME: This should prompt the user about unsaved changes and handle errors
		 * with user interaction (dialogs, notifications).
		 */
		public async void refresh_file()
		{
			if (this.current_file == null || this.current_file.buffer == null) {
				return;
			}
			
			var buffer = this.current_file.buffer as GtkSource.Buffer;
			if (buffer == null) {
				return;
			}
			
			if (buffer.get_modified()) {
				// FIXME: Prompt user about unsaved changes
				GLib.error("File has unsaved changes, not reloading");
				return;
			}
			
			try {
				yield this.current_file.buffer.read_async();
			} catch (Error e) {
				// FIXME: Show error dialog to user
				GLib.warning("Failed to reload file %s: %s", this.current_file.path, e.message);
			}
		}
		
		/**
		 * Save current file state (cursor position and scroll position).
		 */
		private void save_current_file_state()
		{
			if (this.current_file == null) {
				return;
			}
			
			// Cancel any pending scroll save timeout
			if (this.scroll_save_timeout_id != null) {
				GLib.Source.remove(this.scroll_save_timeout_id);
				this.scroll_save_timeout_id = null;
			}
			
			var buffer = this.source_view.buffer;
			// Save cursor position
			Gtk.TextIter cursor_iter;
			buffer.get_iter_at_mark(out cursor_iter, buffer.get_insert());
			this.current_file.cursor_line = cursor_iter.get_line();
			this.current_file.cursor_offset = cursor_iter.get_line_offset();
			
			// Save scroll position (first visible line)
			this.save_scroll_position();
			
			// Update last_viewed timestamp
			var now = new DateTime.now_local();
			this.current_file.last_viewed = now.to_unix();
			
			// Notify manager to save to database (metadata-only change - cursor/scroll position)
			this.manager.on_file_metadata_change(this.current_file);
		}
		
		/**
		 * Save scroll position (first visible line) to current file.
		 */
		private void save_scroll_position()
		{
			if (this.current_file == null) {
				return;
			}
			
			// Get visible rectangle
			Gdk.Rectangle visible_rect;
			this.source_view.get_visible_rect(out visible_rect);
			
			// Get iter at top of visible area
			Gtk.TextIter top_iter;
			if (this.source_view.get_iter_at_location(out top_iter, visible_rect.x, visible_rect.y)) {
				// Get line number of first visible line
				this.current_file.scroll_position = top_iter.get_line();
			}
		}
		
		/**
		 * Handle scroll change event.
		 * Rate-limited: only saves scroll position after scrolling stops (500ms delay).
		 */
		private void on_scroll_changed()
		{
			if (this.current_file == null) {
				return;
			}
			
			// Cancel existing timeout if any
			if (this.scroll_save_timeout_id != null) {
				GLib.Source.remove(this.scroll_save_timeout_id);
			}
			
			// Set up new timeout to save scroll position after scrolling stops
			this.scroll_save_timeout_id = GLib.Timeout.add(500, () => {
				// Save scroll position and update database (metadata-only change)
				this.save_scroll_position();
				this.manager.on_file_metadata_change(this.current_file);
				this.scroll_save_timeout_id = null;
				return false; // Only run once
			});
		}
		
		/**
		 * Restore cursor position from file state and scroll it into view.
		 */
		private void restore_cursor_position(OLLMfiles.File file)
		{
			var buffer = this.source_view.buffer;
			
			// Restore cursor position and scroll into view
			if (file.cursor_line >= 0 && file.cursor_offset >= 0) {
				// Use navigate_to_line to handle line navigation and scrolling
				this.navigate_to_line(file.cursor_line);
				
				// Then adjust the offset (character position within the line)
				Gtk.TextIter iter;
				if (buffer.get_iter_at_line_offset(out iter, file.cursor_line, file.cursor_offset)) {
					buffer.place_cursor(iter);
				}
			}
		}
		
		/**
		 * Restore scroll position from file state.
		 */
		private void restore_scroll_position(OLLMfiles.File file)
		{
			if (file.scroll_position > 0) {
				// Use Idle to restore scroll position after layout is complete
				GLib.Idle.add(() => {
					var buffer = this.source_view.buffer;
					Gtk.TextIter iter;
					if (buffer.get_iter_at_line(out iter, file.scroll_position)) {
						// Scroll to the first visible line
						this.source_view.scroll_to_iter(iter, 0.0, false, 0.0, 0.0);
					}
					return false; // Only run once
				});
			}
		}
		
		/**
		 * Create search footer bar with search entry, results label, and navigation buttons.
		 */
		private void create_search_bar()
		{
			this.search_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5) {
				margin_start = 5,
				margin_end = 5,
				margin_top = 5,
				margin_bottom = 5,
				vexpand = false
			};
			
			// Search entry
			this.search_entry = new Gtk.SearchEntry() {
				hexpand = true,
				placeholder_text = "Search...",
				search_delay = 300
			};
			this.search_entry.search_changed.connect(() => {
				this.perform_search(this.search_entry.text);
			});
			
			// Handle Enter key in search entry
			var search_entry_controller = new Gtk.EventControllerKey();
			search_entry_controller.key_pressed.connect((keyval, keycode, state) => {
				if (keyval == Gdk.Key.Return && this.search_entry.text.length > 0) {
					this.forward_search(true);
					return true;
				}
				if (keyval == Gdk.Key.g && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
					this.forward_search(true);
					return true;
				}
				return false;
			});
			this.search_entry.add_controller(search_entry_controller);
			
			// Results label
			this.search_results_label = new Gtk.Label("No Results") {
				margin_start = 4,
				margin_end = 4
			};
			
			// Next button
			this.search_next_button = new Gtk.Button.from_icon_name("go-down") {
				tooltip_text = "Next match",
				sensitive = false
			};
			this.search_next_button.clicked.connect(() => {
				this.forward_search(true);
			});
			
			// Back button
			this.search_back_button = new Gtk.Button.from_icon_name("go-up") {
				tooltip_text = "Previous match",
				sensitive = false
			};
			this.search_back_button.clicked.connect(() => {
				this.backward_search(true);
			});
			
			// Settings menu button
			var settings_menu_button = new Gtk.MenuButton() {
				icon_name = "emblem-system",
				tooltip_text = "Search settings",
				always_show_arrow = true
			};
			
			// Create settings popover
			var settings_popover = new Gtk.Popover();
			var settings_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5) {
				margin_start = 10,
				margin_end = 10,
				margin_top = 10,
				margin_bottom = 10
			};
			
			this.case_sensitive_checkbox = new Gtk.CheckButton.with_label("Case Sensitive");
			this.case_sensitive_checkbox.toggled.connect(() => {
				this.update_search_settings();
			});
			
			this.regex_checkbox = new Gtk.CheckButton.with_label("Regex");
			this.regex_checkbox.toggled.connect(() => {
				this.update_search_settings();
			});
			
			this.multiline_checkbox = new Gtk.CheckButton.with_label("Multi-line (add \\n)");
			this.multiline_checkbox.toggled.connect(() => {
				this.update_search_settings();
			});
			
			settings_box.append(this.case_sensitive_checkbox);
			settings_box.append(this.regex_checkbox);
			settings_box.append(this.multiline_checkbox);
			settings_popover.set_child(settings_box);
			settings_menu_button.popover = settings_popover;
			
			// Add all widgets to search bar
			this.search_bar.append(this.search_entry);
			this.search_bar.append(this.search_results_label);
			this.search_bar.append(this.search_next_button);
			this.search_bar.append(this.search_back_button);
			this.search_bar.append(settings_menu_button);
			
			// Hide search bar initially (same as sourceview)
			this.search_bar.visible = false;
			this.append(this.search_bar);
		}
		
		/**
		 * Perform search with given text.
		 */
		private void perform_search(string search_text)
		{
			if (this.current_buffer == null) {
				this.search_context = null;
				this.update_search_results();
				return;
			}
			
			// Create search settings
			var search_settings = new GtkSource.SearchSettings();
			search_settings.case_sensitive = this.case_sensitive_checkbox.active;
			search_settings.regex_enabled = this.regex_checkbox.active;
			search_settings.wrap_around = false;
			
			// Create search context
			this.search_context = new GtkSource.SearchContext(this.current_buffer, search_settings);
			this.search_context.set_highlight(true);
			
			// Process multiline option
			var txt = search_text;
			if (this.multiline_checkbox.active) {
				txt = search_text.replace("\\n", "\n");
			}
			
			search_settings.set_search_text(txt);
			
			// Reset search position
			this.last_search_end = 0;
			
			// Update results display
			this.update_search_results();
		}
		
		/**
		 * Update search settings for current search context.
		 */
		private void update_search_settings()
		{
			if (this.search_context == null) {
				return;
			}
			
			// Re-perform search with new settings
			this.perform_search(this.search_entry.text);
		}
		
		/**
		 * Update search results label and button states.
		 */
		private void update_search_results()
		{
			if (this.search_context == null) {
				this.search_results_label.label = "No Results";
				this.search_next_button.sensitive = false;
				this.search_back_button.sensitive = false;
				return;
			}
			
			var count = this.search_context.get_occurrences_count();
			if (count < 0) {
				this.search_results_label.label = "??? Matches";
				this.search_next_button.sensitive = false;
				this.search_back_button.sensitive = false;
				return;
			}
			
			if (count > 0) {
				this.search_results_label.label = "%d Matches".printf(count);
				this.search_next_button.sensitive = true;
				this.search_back_button.sensitive = true;
			} else {
				this.search_results_label.label = "No Matches";
				this.search_next_button.sensitive = false;
				this.search_back_button.sensitive = false;
			}
		}
		
		/**
		 * Perform forward search (find next match).
		 */
		private void forward_search(bool change_focus)
		{
			if (this.current_buffer == null) {
				return;
			}
			
			Gtk.TextIter beg, st, en;
			bool has_wrapped_around;
			this.current_buffer.get_iter_at_offset(out beg, this.last_search_end);
			
			if (!this.search_context.forward(beg, out st, out en, out has_wrapped_around)) {
				// No match found, reset to start
				this.last_search_end = 0;
				return;
			}
			
			if (has_wrapped_around) {
				// Don't wrap around, just stop
				return;
			}
			
			this.last_search_end = en.get_offset();
			if (change_focus) {
				this.source_view.grab_focus();
			}
			this.current_buffer.place_cursor(st);
			this.source_view.scroll_to_iter(st, 0.1, true, 0.0, 0.5);
		}
		
		/**
		 * Perform backward search (find previous match).
		 */
		private void backward_search(bool change_focus)
		{
			if (this.current_buffer == null) {
				return;
			}
			
			Gtk.TextIter beg, st, en;
			bool has_wrapped_around;
			this.current_buffer.get_iter_at_offset(out beg, this.last_search_end - 1);
			
			if (!this.search_context.backward(beg, out st, out en, out has_wrapped_around)) {
				// No match found, reset to end
				Gtk.TextIter end_iter;
				this.current_buffer.get_end_iter(out end_iter);
				this.last_search_end = end_iter.get_offset();
				return;
			}
			
			this.last_search_end = en.get_offset();
			if (change_focus) {
				this.source_view.grab_focus();
			}
			this.current_buffer.place_cursor(st);
			this.source_view.scroll_to_iter(st, 0.1, true, 0.0, 0.5);
		}
		
		// TODO: Clipboard feature needs proper design - see TODO.md
		// /**
		//  * Handle copy-clipboard signal to store file reference metadata.
		//  */
		// private void on_copy_clipboard()
		// {
		// 	if (this.current_file == null) {
		// 		return;
		// 	}
		// 	
		// 	var buffer = this.source_view.buffer as GtkSource.Buffer;
		// 	if (buffer == null) {
		// 		return;
		// 	}
		// 	
		// 	// Get selection bounds
		// 	Gtk.TextIter start_iter, end_iter;
		// 	if (!buffer.get_selection_bounds(out start_iter, out end_iter)) {
		// 		// No selection, don't store metadata
		// 		return;
		// 	}
		// 	
		// 	// Get line numbers (0-based)
		// 	int start_line = start_iter.get_line();
		// 	int end_line = end_iter.get_line();
		// 	
		// 	// Get selected text
		// 	string? selected_text = buffer.get_text(start_iter, end_iter, false);
		// 	
		// 	// Store metadata for later retrieval on paste
		// 	// Use static method directly since we're in the same library and have File object
		// 	OLLMcoder.ClipboardMetadata.store_file(this.current_file, start_line, end_line, selected_text);
		// }
		
		/**
		 * Save current file to disk.
		 */
		public async void save_file()
		{
			if (this.current_file == null || this.current_file.buffer == null) {
				return;
			}
			
			// FIXME: User interaction needed - show warning dialog when trying to save deleted file
			// Currently silently returns, but should warn user that file is deleted and cannot be saved.
			// Could show a dialog like "File has been deleted and cannot be saved. Would you like to restore it?"
			// or at minimum show a notification/warning message to the user.
			if (this.current_file.delete_id > 0) {
				GLib.warning("Cannot save file %s: file has been deleted (delete_id=%lld)", 
					this.current_file.path, this.current_file.delete_id);
				// TODO: Show user-visible warning/notification dialog
				return;
			}
			
			// Sync buffer to file
			try {
				yield this.current_file.buffer.sync_to_file();
				this.current_file.is_unsaved = false;
				
				// Save state to database and force immediate save to disk
				this.save_current_file_state();
				if (this.manager.db != null) {
					this.manager.db.backupDB();
				}
			} catch (Error e) {
				GLib.warning("Failed to save file %s: %s", this.current_file.path, e.message);
			}
		}
		
		/**
		 * Disconnect delete_id signal handler.
		 */
		private void disconnect_delete_id_handler()
		{
			if (this.delete_id_handler_id == null || this.current_file == null) {
				return;
			}
			this.current_file.disconnect(this.delete_id_handler_id);
			this.delete_id_handler_id = null;
		}
		
		/**
		 * Handle file deletion in editor.
		 * 
		 * Called when delete_id > 0 is detected on the current file.
		 * Clears buffer contents, shows "file deleted" indicator, and disables editing.
		 * 
		 * @param file The deleted file
		 */
		private void handle_file_deleted(OLLMfiles.File file)
		{
			// Clear buffer contents
			if (file.buffer != null) {
				file.buffer.clear.begin((obj, res) => {
					try {
						file.buffer.clear.end(res);
					} catch (Error e) {
						GLib.warning("Failed to clear buffer for deleted file %s: %s", file.path, e.message);
					}
				});
			}
			
			// Show "file deleted" indicator in placeholder
			this.file_dropdown.placeholder_text = Path.get_basename(file.path) + " (deleted)";
			
			// Disable editing
			this.source_view.editable = false;
			
			// Disable save button
			this.save_button.sensitive = false;
			
			// Add CSS class to indicate deleted state (for potential styling)
			this.source_view.add_css_class("file-deleted");
			
			// Note: Future enhancement - when sourceview can handle diffs, show the original file
			// content as red deleted (like a diff view showing deleted lines)
			// Can access deletion info via: file.delete_id -> FileHistory record
		}
		
	}
}
