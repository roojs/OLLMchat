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
			this.icon_name = "application-octet-stream"; // Default for unknown/binary files
		 
			// Set icon_name from content type if available
			if (content_type != null && content_type != "") {
				var icon_name = GLib.ContentType.get_generic_icon_name(content_type);
				this.icon_name = (icon_name != null && icon_name != "") ? icon_name : this.icon_name;
			}  
			
			// Detect language from filename if not already set
			if (this.language == null || this.language == "") {
				this.detect_language();
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
				GLib.debug("File.detect_language: Detected language '%s' for file '%s'", 
					this.language, this.path);
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
			return this.manager.buffer_provider.get_buffer_text(this, 0, max_lines > 0 ? max_lines - 1 : -1);
		}
		
		/**
		 * Gets the total number of lines in the file.
		 * 
		 * @return Line count, or 0 if not available
		 */
		public int get_line_count()
		{
			return this.manager.buffer_provider.get_buffer_line_count(this);
		}
		
		/**
		 * Gets the currently selected text (only valid for active file).
		 * Updates cursor position and saves to database.
		 * 
		 * @return Selected text, or empty string if nothing is selected
		 */
		public string get_selected_code()
		{
			int cursor_line, cursor_offset;
			var selected = this.manager.buffer_provider.get_buffer_selection(this, out cursor_line, out cursor_offset);
			
			// Update cursor position from provider
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
		 * @param line Line number (0-based)
		 * @return Line content, or empty string if not available
		 */
		public string get_line_content(int line)
		{
			return this.manager.buffer_provider.get_buffer_line(this, line);
		}
		
		/**
		 * Gets the current cursor position (line number).
		 * Updates cursor_line and cursor_offset properties and saves to database.
		 * 
		 * @return Line number (0-based), or -1 if not available
		 */
		public int get_cursor_position()
		{
			int line, offset;
			this.manager.buffer_provider.get_buffer_cursor(this, out line, out offset);
			
			this.cursor_line = line;
			this.cursor_offset = offset;
			
			// Save to database
			if (this.manager.db != null) {
				this.saveToDB(this.manager.db, null, false);
				this.manager.db.is_dirty = true;
			}
			
			return this.cursor_line;
		}
	}
}
