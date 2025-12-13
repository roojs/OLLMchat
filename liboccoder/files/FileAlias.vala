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
	 * Wrapper class for File objects that are aliases/symlinks.
	 * 
	 * Note: Alias files are not used in the editor. Properties return null/empty/default values
	 * and methods throw errors. The alias maintains its own path and parent (where the alias exists)
	 * for filesystem tracking purposes only.
	 */
	public class FileAlias : File
	{
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 * Note: points_to and points_to_id must be set after construction (by database loader or when target is known)
		 */
		public FileAlias(OLLMcoder.ProjectManager manager)
		{
			base(manager);
			this.base_type = "fa";
			// is_alias is now computed (returns true for FileAlias)
			// points_to and points_to_id must be set after construction
		}
		
		/**
		 * Programming language - alias files not used in editor.
		 */
		public override string? language {
			get { return null; }
			set { GLib.error("FileAlias.language should not be set - alias files are not used in editor"); }
		}
		
		/**
		 * Text buffer - alias files not used in editor.
		 */
		public override GtkSource.Buffer? text_buffer {
			get { return null; }
			set { GLib.error("FileAlias.text_buffer should not be set - alias files are not used in editor"); }
		}
		
		/**
		 * Cursor line - alias files not used in editor.
		 */
		public override int cursor_line {
			get { return 0; }
			set { GLib.error("FileAlias.cursor_line should not be set - alias files are not used in editor"); }
		}
		
		/**
		 * Cursor offset - alias files not used in editor.
		 */
		public override int cursor_offset {
			get { return 0; }
			set { GLib.error("FileAlias.cursor_offset should not be set - alias files are not used in editor"); }
		}
		
		/**
		 * Scroll position - alias files not used in editor.
		 */
		public override double scroll_position {
			get { return 0.0; }
			set { GLib.error("FileAlias.scroll_position should not be set - alias files are not used in editor"); }
		}
		
		/**
		 * Last viewed - alias files not used in editor.
		 */
		public override int64 last_viewed {
			get { return 0; }
			set { GLib.error("FileAlias.last_viewed should not be set - alias files are not used in editor"); }
		}
		
		/**
		 * Needs approval - alias files not used in editor.
		 */
		public override bool needs_approval {
			get { return true; }
			set { GLib.error("FileAlias.needs_approval should not be set - alias files are not used in editor"); }
		}
		
		/**
		 * Is unsaved - alias files not used in editor.
		 */
		public override bool is_unsaved {
			get { return false; }
			set { GLib.error("FileAlias.is_unsaved should not be set - alias files are not used in editor"); }
		}
		
		/**
		 * Last approved copy path - alias files not used in editor.
		 */
		public override string last_approved_copy_path {
			get { return ""; }
			set { GLib.error("FileAlias.last_approved_copy_path should not be set - alias files are not used in editor"); }
		}
		
		/**
		 * Write file contents - alias files not used in editor.
		 */
		public override void write(string contents) throws Error
		{
			GLib.error("FileAlias.write() should not be called - alias files are not used in editor");
		}
		
		/**
		 * Read file contents asynchronously - alias files not used in editor.
		 */
		public override async string read_async() throws Error
		{
			GLib.error("FileAlias.read_async() should not be called - alias files are not used in editor");
		}
	}
}
