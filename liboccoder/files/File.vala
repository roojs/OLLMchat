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
			Folder parent,
			GLib.FileInfo info,
			string path)
		{
			base(parent.manager);
			this.path = path;
			this.parent = parent;
			this.parent_id = parent.id;
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
		 * Last scroll position (stored in database, optional, default: 0.0).
		 */
		public double scroll_position { get; set; default = 0.0; }
		
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
			
			this.changed();
		}
	}
}
