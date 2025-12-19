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

namespace OLLMcoder.Files
{
	/**
	 * Represents a file in the project.
	 * 
	 * Files can be in multiple projects (due to softlinks/symlinks).
	 * All alias references are tracked in ProjectManager's alias_map.
	 */
	public class File : FileBase
	{
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public File(OLLMcoder.ProjectManager manager)
		{
			base(manager);
			this.base_type = "f";
		}
		
		/**
		 * Named constructor: Create a File from FileInfo.
		 * 
		 * @param parent The parent Folder (required)
		 * @param info The FileInfo object from directory enumeration
		 * @param path The full path to the file
		 */
		public File.new_from_info(
			OLLMcoder.ProjectManager manager,
			Folder? parent,
			GLib.FileInfo info,
			string path)
		{
			base(manager);
			this.base_type = "f";
			this.path = path;
			if (parent != null) {
				this.parent = parent;
				this.parent_id = parent.id;
			}
			
			// Set last_modified from FileInfo
			var mod_time = info.get_modification_date_time();
			if (mod_time != null) {
				this.last_modified = mod_time.to_unix();
			}
			
			// Detect and set is_text from content type
			var  content_type = info.get_content_type();
 			this.is_text = content_type != null && content_type != "" &&  content_type.has_prefix("text/");
			
			// Set icon_name from content type if available
			if (content_type != null && content_type != "") {
				var icon_name = GLib.ContentType.get_generic_icon_name(content_type);
				this.icon_name = (icon_name != null && icon_name != "") ? icon_name : "text-x-generic";
				
			}
			
			// Detect language from filename if not already set
			if (this.language == null || this.language == "") {
				this.detect_language();
			}
		}
		
		/**
		 * Detect programming language from file extension using GtkSource.LanguageManager.
		 * Sets the language property if a match is found.
		 */
		private void detect_language()
		{
			if (this.path == null || this.path == "") {
				return;
			}
			
			try {
				var lang_manager = GtkSource.LanguageManager.get_default();
				var language = lang_manager.guess_language(this.path, null);
				if (language != null) {
					// Get the language ID (e.g., "vala", "python", "javascript")
					this.language = language.get_id();
					GLib.debug("File.detect_language: Detected language '%s' for file '%s'", 
						this.language, this.path);
				}
			} catch (GLib.Error e) {
				GLib.debug("File.detect_language: Failed to detect language for '%s': %s", 
					this.path, e.message);
			}
		}
		
		/**
		 * Text buffer for this file (GTK-specific, nullable, created when file is first opened).
		 */
		public GtkSource.Buffer? text_buffer { get; set; default = null; }
		
		/**
		 * Last cursor line number (stored in database, default: 0).
		 */
		public int cursor_line { get; set; default = 0; }
		
		/**
		 * Last cursor character offset (stored in database, default: 0).
		 */
		public int cursor_offset { get; set; default = 0; }
		
		/**
		 * Last scroll position (stored in database, optional, default: 0).
		 */
		public int scroll_position { get; set; default = 0; }
		
		/**
		 * Whether file is currently open in editor.
		 * Computed property: Returns true if file was viewed within last week.
		 */
		public bool is_open {
			get {
				if (this.last_viewed == 0) {
					return false;
				}
				var now = new DateTime.now_local();
				var one_week_ago = now.add_days(-7);
				var viewed_time = new DateTime.from_unix_local(this.last_viewed);
				return viewed_time.compare(one_week_ago) > 0;
			}
		}
		
		
		/**
		 * Whether the file needs approval (inverted from is_approved).
		 * true = needs approval, false = approved.
		 */
		public bool needs_approval { get; set; default = true; }
		
		/**
		 * Whether the file has unsaved changes.
		 */
		public bool is_unsaved { get; set; default = false; }
		
		
		/**
		 * Filename of last approved copy (default: empty string).
		 */
		public string last_approved_copy_path { get; set; default = ""; }
		
		private string _icon_name = "";
		/**
		 * Icon name for binding in lists.
		 * Returns icon_name if set, otherwise derives from file content type.
		 */
		public override string icon_name {
			get {
				if (this._icon_name != "") {
					return this._icon_name;
				}
				if (this.path == "") {
					return "text-x-generic";
				}
				// Use Gio.ContentType to guess content type from filename
				string? content_type = null;
				try {
					var file = GLib.File.new_for_path(this.path);
					var file_info = file.query_info(
						GLib.FileAttribute.STANDARD_CONTENT_TYPE,
						GLib.FileQueryInfoFlags.NONE,
						null
					);
					content_type = file_info.get_content_type();
				} catch {
					// If we can't query, try guessing from filename
					content_type = GLib.ContentType.guess(this.path, null, null);
				}
				if (content_type != null && content_type != "") {
					// Get generic icon name from content type
					var icon_name = GLib.ContentType.get_generic_icon_name(content_type);
					if (icon_name != null && icon_name != "") {
						this._icon_name = icon_name;
						return this._icon_name;
					}
				}
				// Default fallback
				return "text-x-generic";
			}
			set {
				this._icon_name = value; // as we can save it in the DB to save time..
			}
		}
		
		/**
		 * Display name with path: basename on first line, dirname on second line in grey.
		 * Format: {basename}\n<span grey small dirname>
		 */
		public string display_with_path {
			owned get {
				return GLib.Path.get_basename(this.path) +
					 "\n<span foreground=\"grey\" size=\"small\">" + 
					GLib.Markup.escape_text(GLib.Path.get_dirname(this.path)) + 
					"</span>";
			}
		}
		
		/**
		 * Display name with basename only: basename on first line.
		 * Format: {basename}\n
		 */
		public string display_basename {
			owned get {
				return GLib.Path.get_basename(this.path) + "\n";
			}
		}
		// we need the private to get around woned issues...
		private string _display_with_indicators = "";
		/**
		 * Display text with status indicators (approved, unsaved).
		 */
		public override string display_with_indicators {
			get {
				this._display_with_indicators = 
					this.display_basename + (!this.needs_approval ? " ✓" : "") 
					+ (this.is_unsaved ? " ●" : "");
				return this._display_with_indicators; // Checkmark when approved (not needs_approval)
			}
		}
		
		/**
		 * Emitted when file content changes.
		 */
		public signal void changed();
		
		/**
		 * Read file contents asynchronously.
		 * 
		 * @return File contents as string
		 * @throws Error if file cannot be read
		 */
		public async string read_async() throws Error
		{
			var file = GLib.File.new_for_path(this.path);
			if (!file.query_exists()) {
				throw new GLib.FileError.NOENT("File not found: " + this.path);
			}
			
			uint8[] data;
			string etag;
			yield file.load_contents_async(null, out data, out etag);
			
			return (string)data;
		}
		
		/**
		 * Write file contents.
		 * 
		 * @param contents Contents to write
		 * @throws Error if file cannot be written
		 */
		public void write(string contents) throws Error
		{
			var file = GLib.File.new_for_path(this.path);
			var parent = file.get_parent();
			if (parent != null && !parent.query_exists()) {
				parent.make_directory_with_parents(null);
			}
			
			var output_stream = file.replace(null, false, GLib.FileCreateFlags.NONE, null);
			var data_stream = new GLib.DataOutputStream(output_stream);
			data_stream.put_string(contents, null);
			data_stream.close(null);
			
			// Update last_modified from filesystem after writing
			this.last_modified = this.mtime_on_disk();
			
			// Save to database with sync to disk
			if (this.manager.db != null) {
				this.saveToDB(this.manager.db, null, true);
			}
			
			this.changed();
		}
		
		/**
		 * Gets file contents, optionally limited to first N lines.
		 * 
		 * @param max_lines Maximum number of lines to return (0 = all lines)
		 * @return File contents, or empty string if not available
		 */
		public string get_contents(int max_lines = 0)
		{
			if (this.text_buffer == null) {
				return "";
			}
			
			Gtk.TextIter start, end;
			this.text_buffer.get_bounds(out start, out end);
			
			if (max_lines > 0) {
				// Limit to first max_lines
				var line_end = start;
				line_end.forward_lines(max_lines - 1);
				if (!line_end.ends_line()) {
					line_end.forward_to_line_end();
				}
				return this.text_buffer.get_text(start, line_end, true);
			}
			
			return this.text_buffer.get_text(start, end, true);
		}
		
		/**
		 * Gets the total number of lines in the file.
		 * 
		 * @return Line count, or 0 if not available
		 */
		public int get_line_count()
		{
			if (this.text_buffer == null) {
				return 0;
			}
			
			Gtk.TextIter start, end;
			this.text_buffer.get_bounds(out start, out end);
			return end.get_line() + 1;
		}
		
		/**
		 * Gets the currently selected text (only valid for active file).
		 * Updates cursor position and saves to database.
		 * 
		 * @return Selected text, or empty string if nothing is selected
		 */
		public string get_selected_code()
		{
			if (this.text_buffer == null) {
				return "";
			}
			
			// Update cursor position from buffer
			Gtk.TextIter cursor;
			this.text_buffer.get_iter_at_mark(out cursor, this.text_buffer.get_insert());
			this.cursor_line = cursor.get_line();
			this.cursor_offset = cursor.get_line_offset();
			
			// Save to database
			if (this.manager.db != null) {
				this.saveToDB(this.manager.db, null, false);
				this.manager.db.is_dirty = true;
			}
			
			Gtk.TextIter start, end;
			if (!this.text_buffer.get_selection_bounds(out start, out end)) {
				return "";
			}
			
			return this.text_buffer.get_text(start, end, true);
		}
		
		/**
		 * Gets the content of a specific line.
		 * 
		 * @param line Line number (0-based)
		 * @return Line content, or empty string if not available
		 */
		public string get_line_content(int line)
		{
			if (this.text_buffer == null) {
				return "";
			}
			
			Gtk.TextIter iter;
			if (!this.text_buffer.get_iter_at_line(out iter, line)) {
				return "";
			}
			
			var line_end = iter;
			if (!line_end.ends_line()) {
				line_end.forward_to_line_end();
			}
			
			return this.text_buffer.get_text(iter, line_end, true);
		}
		
		/**
		 * Gets the current cursor position (line number).
		 * Updates cursor_line and cursor_offset properties and saves to database.
		 * 
		 * @return Line number (0-based), or -1 if not available
		 */
		public int get_cursor_position()
		{
			if (this.text_buffer == null) {
				return -1;
			}
			
			Gtk.TextIter cursor;
			this.text_buffer.get_iter_at_mark(out cursor, this.text_buffer.get_insert());
			this.cursor_line = cursor.get_line();
			this.cursor_offset = cursor.get_line_offset();
			
			// Save to database
			if (this.manager.db != null) {
				this.saveToDB(this.manager.db, null, false);
				this.manager.db.is_dirty = true;
			}
			
			return this.cursor_line;
		}
	}
}
