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

namespace OLLMfiles
{
	/**
	 * Result of checking if a file has been updated on disk.
	 */
	public enum FileUpdateStatus {
		NO_CHANGE,              // File hasn't changed on disk
		CHANGED_HAS_UNSAVED     // File changed on disk, buffer has unsaved changes - needs warning
	}
	
	/**
	 * Represents a file in the project.
	 * 
	 * Files can be in multiple projects (due to softlinks/symlinks).
	 * All alias references are tracked in ProjectManager's alias_map.
	 * 
	 * Constructors include File(manager) for basic construction, File.new_from_info()
	 * for creating from FileInfo during directory scan, and File.new_fake() for files
	 * not in database (id = -1).
	 * 
	 * == Content Access ==
	 * 
	 * All content access methods delegate to file.buffer. Ensure buffer is created before use:
	 * {{{
	 * if (file.buffer == null) {
	 *     file.manager.buffer_provider.create_buffer(file);
	 * }
	 * var contents = yield file.buffer.read_async();
	 * }}}
	 */
	public class File : FileBase
	{
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public File(ProjectManager manager)
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
			ProjectManager manager,
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
			
			// Detect language from filename if not already set
			if (this.language == null || this.language == "") {
				this.detect_language();
			}
		}
		
		/**
		 * Named constructor: Create a fake File object for files not in database.
		 * 
		 * Fake files are used for accessing files outside the project scope.
		 * They have id = -1 and skip database operations.
		 * 
		 * @param manager The ProjectManager instance (required)
		 * @param path The full path to the file
		 */
		public File.new_fake(ProjectManager manager, string path)
		{
			base(manager);
			this.base_type = "f";
			this.path = path;
			this.id = -1; // Indicates not in database (fake file)
			
			// Detect language from filename
			this.detect_language();
			
			// Set is_text from content type if available
			try {
				var file = GLib.File.new_for_path(path);
				if (file.query_exists()) {
					var file_info = file.query_info(
						GLib.FileAttribute.STANDARD_CONTENT_TYPE,
						GLib.FileQueryInfoFlags.NONE,
						null
					);
					var content_type = file_info.get_content_type();
					this.is_text = content_type != null && content_type != "" && content_type.has_prefix("text/");
					
					// Set last_modified from FileInfo
					var mod_time = file_info.get_modification_date_time();
					if (mod_time != null) {
						this.last_modified = mod_time.to_unix();
					}
				}
			} catch (GLib.Error e) {
				// File might not exist yet, that's okay for fake files
				GLib.debug("File.new_fake: Could not query file info for %s: %s", path, e.message);
			}
		}
		
		/**
		 * Detect programming language from file extension using buffer provider.
		 * Sets the language property if a match is found.
		 */
		private void detect_language()
		{
			if (this.path == null || this.path == "") {
				return;
			}
			
			var detected = this.manager.buffer_provider.detect_language(this);
			if (detected != null && detected != "") {
				this.language = detected;
				//GLib.debug("File.detect_language: Detected language '%s' for file '%s'", 
				//	this.language, this.path);
			}
		}
		
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
		 * File buffer instance (nullable).
		 * 
		 * Created by buffer provider when needed. Each File object has at most one
		 * buffer instance. Buffer is created lazily when first accessed. Buffer can
		 * be null if not yet created or after cleanup. Buffer type depends on
		 * BufferProvider implementation (GTK vs non-GTK).
		 * 
		 * == Key Points ==
		 * 
		 *  * Each File object has at most one buffer instance
		 *  * Buffer is created lazily when needed
		 *  * Buffer can be null if not yet created or after cleanup
		 *  * Buffer type depends on BufferProvider implementation (GTK vs non-GTK)
		 * 
		 * == Usage ==
		 * 
		 * Always check for null before using buffer methods:
		 * {{{
		 * if (file.buffer == null) {
		 *     file.manager.buffer_provider.create_buffer(file);
		 * }
		 * var contents = yield file.buffer.read_async();
		 * }}}
		 */
		public FileBuffer? buffer { get; set; default = null; }
		
		/**
		 * Emitted when file content changes.
		 */
		public signal void changed();
		
		/**
		 * Gets file contents, optionally limited to first N lines.
		 * 
		 * Convenience method that delegates to file.buffer.get_text(). Requires
		 * file.buffer to be non-null. Ensure buffer is created before use.
		 * 
		 * == Important ==
		 * 
		 * This method requires file.buffer to be non-null. Ensure buffer is created
		 * before use:
		 * {{{
		 * if (file.buffer == null) {
		 *     file.manager.buffer_provider.create_buffer(file);
		 * }
		 * var contents = file.get_contents();
		 * }}}
		 * 
		 * Buffer must be loaded first (via read_async() or automatic loading).
		 * 
		 * @param max_lines Maximum number of lines to return (0 = all lines)
		 * @return File contents, or empty string if not available
		 */
		public string get_contents(int max_lines = 0)
		{
			if (this.buffer == null) {
				return "";
			}
			return this.buffer.get_text(0, max_lines > 0 ? max_lines - 1 : -1);
		}
		
		/**
		 * Gets the total number of lines in the file.
		 * 
		 * Convenience method that delegates to file.buffer.get_line_count().
		 * Requires file.buffer to be non-null. Ensure buffer is created before use.
		 * 
		 * @return Line count, or 0 if not available
		 */
		public int get_line_count()
		{
			if (this.buffer == null) {
				return 0;
			}
			return this.buffer.get_line_count();
		}
		
		/**
		 * Gets the currently selected text (only valid for active file).
		 * 
		 * Convenience method that delegates to file.buffer.get_selection().
		 * Updates cursor position and saves to database. Requires file.buffer to be
		 * non-null. Only works with GTK buffers (DummyFileBuffer returns empty string).
		 * 
		 * == Process ==
		 * 
		 *  1. Gets selection from buffer (updates cursor position)
		 *  2. Updates cursor_line and cursor_offset properties
		 *  3. Saves to database (if manager.db is available)
		 * 
		 * @return Selected text, or empty string if nothing is selected
		 */
		public string get_selected_code()
		{
			if (this.buffer == null) {
				return "";
			}
			
			int cursor_line, cursor_offset;
			var selected = this.buffer.get_selection(out cursor_line, out cursor_offset);
			
			// Update cursor position from buffer
			this.cursor_line = cursor_line;
			this.cursor_offset = cursor_offset;
			
			// Save to database
			if (this.manager.db != null) {
				this.saveToDB(this.manager.db, null, false);
				this.manager.db.is_dirty = true;
			}
			
			return selected;
		}
		
		/**
		 * Gets the content of a specific line.
		 * 
		 * Convenience method that delegates to file.buffer.get_line(). Requires
		 * file.buffer to be non-null. Ensure buffer is created before use.
		 * 
		 * == Line Numbering ==
		 * 
		 * Uses 0-based line numbers (internal format). For user-facing APIs,
		 * convert from 1-based to 0-based.
		 * 
		 * @param line Line number (0-based)
		 * @return Line content, or empty string if not available
		 */
		public string get_line_content(int line)
		{
			if (this.buffer == null) {
				return "";
			}
			return this.buffer.get_line(line);
		}
		
		/**
		 * Gets the current cursor position (line number).
		 * 
		 * Convenience method that delegates to file.buffer.get_cursor(). Updates
		 * cursor_line and cursor_offset properties and saves to database. Requires
		 * file.buffer to be non-null. Only works with GTK buffers (DummyFileBuffer
		 * returns 0,0).
		 * 
		 * == Process ==
		 * 
		 *  1. Gets cursor position from buffer
		 *  2. Updates cursor_line and cursor_offset properties
		 *  3. Saves to database (if manager.db is available)
		 * 
		 * @return Line number (0-based), or -1 if not available
		 */
		public int get_cursor_position()
		{
			if (this.buffer == null) {
				return -1;
			}
			
			int line, offset;
			this.buffer.get_cursor(out line, out offset);
			
			this.cursor_line = line;
			this.cursor_offset = offset;
			
			// Save to database
			if (this.manager.db != null) {
				this.saveToDB(this.manager.db, null, false);
				this.manager.db.is_dirty = true;
			}
			
			return this.cursor_line;
		}
		
		/**
		 * Check if the file has been modified on disk and differs from the buffer.
		 * 
		 * Compares the file's modification time on disk with the buffer's last read timestamp.
		 * If the file was modified, also checks if the content actually differs from the buffer.
		 * Automatically reloads the file if it changed and the buffer has no unsaved changes.
		 * 
		 * This should be called when the window gains focus to detect external file changes.
		 * 
		 * @return FileUpdateStatus indicating what action should be taken:
		 *         - NO_CHANGE: File hasn't changed on disk (or was auto-reloaded)
		 *         - CHANGED_HAS_UNSAVED: File changed, buffer has unsaved changes - needs warning
		 */
		public async FileUpdateStatus check_updated()
		{
			// Check if buffer exists
			if (this.buffer == null) {
				return FileUpdateStatus.NO_CHANGE;
			}
			
			// Get file modification time on disk
			var disk_mtime = this.mtime_on_disk();
			if (disk_mtime == 0) {
				// File doesn't exist on disk
				return FileUpdateStatus.NO_CHANGE;
			}
			
			// Check last_read_timestamp
			var last_read = this.buffer.last_read_timestamp;
			
			// If file was not modified since last read, nothing to check
			if (disk_mtime <= last_read) {
				return FileUpdateStatus.NO_CHANGE;
			}
			
			// File was modified since last read, check if content differs
			try {
				// Read current buffer content
				var buffer_content = this.buffer.get_text(0, -1);
				
				// Read file from disk
				var file_obj = GLib.File.new_for_path(this.path);
				if (!file_obj.query_exists()) {
					return FileUpdateStatus.NO_CHANGE;
				}
				
				uint8[] file_data;
				string? etag;
				yield file_obj.load_contents_async(null, out file_data, out etag);
				var disk_content = (string)file_data;
				
				// Compare content
				if (buffer_content == disk_content) {
					// Content matches, no change
					return FileUpdateStatus.NO_CHANGE;
				}
				
				// File has changed on disk and differs from buffer
				// Check if buffer has unsaved changes
				if (this.buffer.is_modified) {
					// Buffer has unsaved changes - needs warning
					return FileUpdateStatus.CHANGED_HAS_UNSAVED;
				}
				
				// Buffer not modified - auto-reload
				yield this.buffer.read_async();
				return FileUpdateStatus.NO_CHANGE;
			} catch (GLib.Error e) {
				GLib.warning("Failed to check file changes for %s: %s", this.path, e.message);
				return FileUpdateStatus.NO_CHANGE;
			}
			
			return FileUpdateStatus.NO_CHANGE;
		}
	}
}
