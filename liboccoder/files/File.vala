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
		}
		/**
		 * Programming language (optional, for files).
		 */
		public string? language { get; set; default = null; }
		
		/**
		 * Whether file is currently open in editor.
		 */
		public bool is_open { get; set; default = false; }
		
		/**
		 * Whether this is the currently active/viewed file.
		 */
		public bool is_active { get; set; default = false; }
		
		/**
		 * Filename of last approved copy (default: empty string).
		 */
		public string last_approved_copy_path { get; set; default = ""; }
		
		/**
		 * Emitted when file content changes.
		 */
		public signal void changed();
		
		/**
		 * Read file contents.
		 * 
		 * @return File contents as string
		 * @throws Error if file cannot be read
		 */
		public string read() throws Error
		{
			string contents;
			GLib.FileUtils.get_contents(this.path, out contents);
			return contents;
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
