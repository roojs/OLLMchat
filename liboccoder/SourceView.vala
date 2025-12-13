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
	 * Operations like refresh_file(), restore_session(), and file loading should
	 * provide user feedback and allow recovery/retry options.
	 */
	public class SourceView : Gtk.Box
	{
		private ProjectManager manager;
		private ProjectDropdown project_dropdown;
		private FileDropdown file_dropdown;
		private GtkSource.View source_view;
		private Gtk.ScrolledWindow scrolled_window;
		
		/**
		 * Currently active file.
		 */
		public Files.File? current_file { get; private set; default = null; }
		
		/**
		 * Currently active project (folder with is_project = true).
		 */
		public Files.Folder? current_project {
			get { return this.manager.active_project; }
		}
		
		/**
		 * Current buffer.
		 */
		public GtkSource.Buffer? current_buffer {
			get { return this.source_view.buffer as GtkSource.Buffer; }
		}
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public SourceView(ProjectManager manager)
		{
			Object(orientation: Gtk.Orientation.VERTICAL);
			this.manager = manager;
			
			// Create header bar with dropdowns
			var header_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10) {
				margin_start = 5,
				margin_end = 5,
				margin_top = 5,
				margin_bottom = 5
			};
			
			// Project dropdown (left-aligned)
			this.project_dropdown = new ProjectDropdown(this.manager);
			this.project_dropdown.project_selected.connect(this.on_project_selected);
			header_bar.append(this.project_dropdown);
			
			// Spacer to push file dropdown to the right
			var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			};
			header_bar.append(spacer);
			
			// File dropdown (right-aligned)
			this.file_dropdown = new FileDropdown();
			this.file_dropdown.file_selected.connect(this.on_file_selected);
			header_bar.append(this.file_dropdown);
			
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
			
			this.scrolled_window.set_child(this.source_view);
			this.append(this.scrolled_window);
			
			// Connect to buffer modified signal
			var source_buffer = this.source_view.buffer as GtkSource.Buffer;
			source_buffer.notify["modified"].connect(() => {
				if (this.current_file != null) {
					this.current_file.is_unsaved = source_buffer.get_modified();
				}
			});
		
			
			// Restore session on startup (not sure if it should be done here..)
			//this.restore_session();
		}
		
		/**
		 * Handle project selection change.
		 */
		private void on_project_selected(Files.Folder? project)
		{
			if (project == null) {
				return;
			}
			
			// Lock file dropdown during project change
			this.file_dropdown.sensitive = false;
			this.file_dropdown.add_css_class("loading");
			this.open_project.begin(project, (obj, res) => {
				this.open_project.end(res);
				// Unlock file dropdown after project change completes
				this.file_dropdown.sensitive = true;
				this.file_dropdown.remove_css_class("loading");
			});
		}
		
		/**
		 * Handle file selection change.
		 */
		private void on_file_selected(Files.File? file)
		{
			if (file == null) {
				// Set default placeholder when no file is selected
				this.file_dropdown.placeholder_text = "Select file...";
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

			
			this.open_file.begin(file, (obj, res) => {
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
		public async void open_file(Files.File file, int? line_number = null)
		{
			// Save current file state if switching away
			if (this.current_file != null && this.current_file != file) {
				this.save_current_file_state();
			}
			
			// Notify manager to activate file
			this.manager.activate_file(file);
			
			// Check if file has existing buffer
			if (file.text_buffer == null) {
				// Create new buffer using file's language property
				GtkSource.Buffer buffer;
				if (file.language != null && file.language != "") {
					var lang_manager = GtkSource.LanguageManager.get_default();
					var language = lang_manager.get_language(file.language);
					if (language != null) {
						buffer = new GtkSource.Buffer.with_language(language);
					} else {
						buffer = new GtkSource.Buffer(null);
					}
				} else {
					buffer = new GtkSource.Buffer(null);
				}
				
				// Load file content asynchronously
				try {
					buffer.text = yield file.read_async();
				} catch (Error e) {
					GLib.warning("Failed to read file %s: %s", file.path, e.message);
					buffer.text = "";
				}
				
				file.text_buffer = buffer;
			}
			
			// Switch view to file's buffer
			this.source_view.set_buffer(file.text_buffer);
			this.current_file = file;
			
			// Restore or set cursor position
			if (line_number != null) {
				this.navigate_to_line(line_number);
			} else {
				this.restore_cursor_position(file);
			}
			
			// Update last_viewed timestamp
			var now = new DateTime.now_local();
			file.last_viewed = now.to_unix();
			this.manager.notify_file_changed(file);
			
			// Update dropdowns
			this.file_dropdown.selected_file = file;
			
			// Update placeholder text with file basename
			this.file_dropdown.placeholder_text = Path.get_basename(file.path);
		}
		
		/**
		 * Open/switch to a project.
		 * 
		 * @param project The project to open
		 */
		public async void open_project(Files.Folder project)
		{
			// Notify manager to activate project

			yield this.manager.activate_project(project);
			
			// Update file dropdown's project
			this.file_dropdown.project = project;
			
			// Update project dropdown
			this.project_dropdown.selected_project = project;
			
			// Update placeholder text with project name
			this.project_dropdown.placeholder_text = project.display_name;
			
			// Find and trigger active file (or null if none)
			var active_file = project.project_files != null ? project.project_files.get_active_file() : null;
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
			if (this.current_file == null) {
				return;
			}
			
			var buffer = this.source_view.buffer as GtkSource.Buffer;
			
			
			if (buffer.get_modified()) {
				// FIXME: Prompt user about unsaved changes
				GLib.error("File has unsaved changes, not reloading");
				return;
			}
			
			try {
				buffer.text = yield this.current_file.read_async();
			} catch (Error e) {
				// FIXME: Show error dialog to user
				GLib.warning("Failed to reload file %s: %s", this.current_file.path, e.message);
			}
		}
		
		/**
		 * Save current file state (cursor position).
		 */
		private void save_current_file_state()
		{
			if (this.current_file == null) {
				return;
			}
			
			var buffer = this.source_view.buffer;
			// Save cursor position
			Gtk.TextIter cursor_iter;
			buffer.get_iter_at_mark(out cursor_iter, buffer.get_insert());
			this.current_file.cursor_line = cursor_iter.get_line();
			this.current_file.cursor_offset = cursor_iter.get_line_offset();
			
			// Update last_viewed timestamp
			var now = new DateTime.now_local();
			this.current_file.last_viewed = now.to_unix();
			
			// Notify manager to save to database
			this.manager.notify_file_changed(this.current_file);
		}
		
		/**
		 * Restore cursor position from file state and scroll it into view.
		 */
		private void restore_cursor_position(Files.File file)
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
		
	}
}
