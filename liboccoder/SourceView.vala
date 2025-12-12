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
	 */
	public class SourceView : Gtk.Box
	{
		private ProjectManager manager;
		private ProjectDropdown project_dropdown;
		private FileDropdown file_dropdown;
		private GtkSource.View source_view;
		private Gtk.ScrolledWindow scrolled_window;
		private Files.File? current_file = null;
		
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
			this.source_view.buffer.notify["modified"].connect(() => {
				if (this.current_file != null) {
					this.current_file.is_unsaved = this.source_view.buffer.modified;
				}
			});
			
			// Restore session on startup
			this.restore_session();
		}
		
		/**
		 * Handle project selection change.
		 */
		private void on_project_selected(Files.Project? project)
		{
			if (project != null) {
				this.open_project(project);
			}
		}
		
		/**
		 * Handle file selection change.
		 */
		private void on_file_selected(Files.File? file)
		{
			if (file != null) {
				this.open_file(file);
			}
		}
		
		/**
		 * Open/switch to a file, optionally navigate to a specific line.
		 * 
		 * @param file The file to open
		 * @param line_number Optional line number to navigate to (overrides saved position)
		 */
		public void open_file(Files.File file, int? line_number = null)
		{
			// Save current file state if switching away
			if (this.current_file != null && this.current_file != file) {
				this.save_current_file_state();
			}
			
			// Notify manager to activate file
			this.manager.activate_file(file);
			
			// Check if file has existing buffer
			if (file.text_buffer == null) {
				// Create new buffer
				var language = this.detect_language(file.path);
				GtkSource.Buffer buffer;
				if (language != null) {
					buffer = new GtkSource.Buffer.with_language(language);
				} else {
					buffer = new GtkSource.Buffer(null);
				}
				
				// Load file content
				try {
					buffer.text = file.read();
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
		}
		
		/**
		 * Open/switch to a project.
		 * 
		 * @param project The project to open
		 */
		public void open_project(Files.Project project)
		{
			// Notify manager to activate project
			this.manager.activate_project(project);
			
			// Update file dropdown's project
			this.file_dropdown.project = project;
			
			// Update project dropdown
			this.project_dropdown.selected_project = project;
		}
		
		/**
		 * Get currently active file.
		 * 
		 * @return The currently active File object, or null if none
		 */
		public Files.File? get_current_file()
		{
			return this.current_file;
		}
		
		/**
		 * Get currently active project.
		 * 
		 * @return The currently active Project object, or null if none
		 */
		public Files.Project? get_current_project()
		{
			return this.manager.get_active_project();
		}
		
		/**
		 * Get current buffer.
		 * 
		 * @return The current GtkSource.Buffer
		 */
		public GtkSource.Buffer? get_current_buffer()
		{
			return this.source_view.buffer as GtkSource.Buffer;
		}
		
		/**
		 * Navigate to a specific line in the current file.
		 * 
		 * @param line_number The line number to navigate to (0-based)
		 */
		public void navigate_to_line(int line_number)
		{
			var buffer = this.source_view.buffer;
			if (buffer == null) {
				return;
			}
			
			Gtk.TextIter iter;
			if (buffer.get_iter_at_line(out iter, line_number)) {
				buffer.place_cursor(iter);
				this.source_view.scroll_to_iter(iter, 0.0, false, 0.0, 0.5);
			}
		}
		
		/**
		 * Refresh current file from disk (if no unsaved changes).
		 */
		public void refresh_file()
		{
			if (this.current_file == null) {
				return;
			}
			
			var buffer = this.source_view.buffer as GtkSource.Buffer;
			if (buffer == null) {
				return;
			}
			
			if (buffer.modified) {
				// TODO: Prompt user about unsaved changes
				GLib.warning("File has unsaved changes, not reloading");
				return;
			}
			
			try {
				buffer.text = this.current_file.read();
			} catch (Error e) {
				GLib.warning("Failed to reload file %s: %s", this.current_file.path, e.message);
			}
		}
		
		/**
		 * Restore session (active project and file) from database.
		 */
		public void restore_session()
		{
			if (this.manager.db == null) {
				return;
			}
			
			// Query for active project
			var project_query = new SQ.Query<Files.FileBase>(this.manager.db, "filebase");
			project_query.typemap = new Gee.HashMap<string, Type>();
			project_query.typemap["p"] = typeof(Files.Project);
			project_query.typemap["f"] = typeof(Files.File);
			project_query.typemap["d"] = typeof(Files.Folder);
			project_query.typekey = "base_type";
			
			var projects = project_query.selectExecute("base_type = 'p' AND is_active = 1 LIMIT 1");
			if (projects.size > 0) {
				var project = projects[0] as Files.Project;
				if (project != null) {
					// Restore project state (without saving, just setting)
					project.is_active = true;
					this.open_project(project);
					
					// Query for active file in this project
					var file_query = new SQ.Query<Files.FileBase>(this.manager.db, "filebase");
					file_query.typemap = new Gee.HashMap<string, Type>();
					file_query.typemap["f"] = typeof(Files.File);
					file_query.typekey = "base_type";
					
					var files = file_query.selectExecute("base_type = 'f' AND is_active = 1 LIMIT 1");
					if (files.size > 0) {
						var file = files[0] as Files.File;
						if (file != null) {
							// Restore file state (without saving, just setting)
							file.is_active = true;
							this.open_file(file);
						}
					}
				}
			}
		}
		
		/**
		 * Save current file state (cursor position, scroll position).
		 */
		private void save_current_file_state()
		{
			if (this.current_file == null) {
				return;
			}
			
			var buffer = this.source_view.buffer;
			if (buffer == null) {
				return;
			}
			
			// Save cursor position
			Gtk.TextIter cursor_iter;
			buffer.get_iter_at_mark(out cursor_iter, buffer.get_insert());
			this.current_file.cursor_line = cursor_iter.get_line();
			this.current_file.cursor_offset = cursor_iter.get_line_offset();
			
			// Save scroll position (approximate, using visible area)
			// Note: GtkSource.View doesn't provide direct scroll position access,
			// so we'll use cursor line as a proxy
			this.current_file.scroll_position = 0.0; // TODO: Implement proper scroll position tracking
			
			// Update last_viewed timestamp
			var now = new DateTime.now_local();
			this.current_file.last_viewed = now.to_unix();
			
			// Notify manager to save to database
			this.manager.notify_file_changed(this.current_file);
		}
		
		/**
		 * Restore cursor position from file state.
		 */
		private void restore_cursor_position(Files.File file)
		{
			var buffer = this.source_view.buffer;
			if (buffer == null) {
				return;
			}
			
			// Restore cursor position
			if (file.cursor_line >= 0 && file.cursor_offset >= 0) {
				Gtk.TextIter iter;
				if (buffer.get_iter_at_line_offset(out iter, file.cursor_line, file.cursor_offset)) {
					buffer.place_cursor(iter);
					this.source_view.scroll_to_iter(iter, 0.0, false, 0.0, 0.5);
				}
			}
		}
		
		/**
		 * Detect language from file path/extension.
		 * 
		 * @param path The file path
		 * @return GtkSource.Language if detected, null otherwise
		 */
		private GtkSource.Language? detect_language(string path)
		{
			var lang_manager = GtkSource.LanguageManager.get_default();
			
			// Try to guess language from file path
			var language = lang_manager.guess_language(path, null);
			if (language != null) {
				return language;
			}
			
			// Fallback: try to extract extension and map common extensions
			var file = GLib.File.new_for_path(path);
			var basename = file.get_basename();
			var last_dot = basename.last_index_of_char('.');
			if (last_dot >= 0 && last_dot < basename.length - 1) {
				var ext = basename.substring(last_dot + 1);
				// Try common language IDs
				var lang_id = this.map_extension_to_language_id(ext);
				if (lang_id != null) {
					return lang_manager.get_language(lang_id);
				}
			}
			
			return null;
		}
		
		/**
		 * Map file extension to GtkSource language ID.
		 * 
		 * @param ext File extension (without dot)
		 * @return Language ID or null if not found
		 */
		private string? map_extension_to_language_id(string ext)
		{
			var ext_lower = ext.down();
			
			// Common mappings
			switch (ext_lower) {
				case "vala":
				case "vapi":
					return "vala";
				case "c":
					return "c";
				case "h":
					return "c";
				case "cpp":
				case "cc":
				case "cxx":
				case "hpp":
					return "cpp";
				case "js":
					return "javascript";
				case "ts":
					return "typescript";
				case "py":
					return "python";
				case "java":
					return "java";
				case "xml":
					return "xml";
				case "html":
				case "htm":
					return "html";
				case "css":
					return "css";
				case "json":
					return "json";
				case "md":
					return "markdown";
				case "sh":
				case "bash":
					return "sh";
				case "sql":
					return "sql";
				case "php":
					return "php";
				case "rb":
					return "ruby";
				case "go":
					return "go";
				case "rs":
					return "rust";
				case "swift":
					return "swift";
				case "kt":
					return "kotlin";
				case "scala":
					return "scala";
				default:
					return null;
			}
		}
	}
}
