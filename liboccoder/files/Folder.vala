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
	 * Represents a folder/directory in the project.
	 * 
	 * Folders maintain a list of their children and a hashmap for quick lookup by filename.
	 * Emits signals when children are added/removed.
	 */
	public class Folder : FileBase
	{
		/**
		 * ListStore of children (files and subfolders).
		 */
		public Gee.ListStore<FileBase> children { get; private set; }
		
		/**
		 * Hashmap of [name in dir] => file object.
		 */
		public Gee.HashMap<string, FileBase> child_map { get; private set; }
		
		/**
		 * Emitted when a child is added.
		 */
		public signal void child_added(FileBase child);
		
		/**
		 * Emitted when a child is removed.
		 */
		public signal void child_removed(FileBase child);
		
		/**
		 * Constructor.
		 */
		public Folder()
		{
			this.children = new Gee.ListStore<FileBase>();
			this.child_map = new Gee.HashMap<string, FileBase>();
		}
		
		/**
		 * Load children from filesystem.
		 * 
		 * @throws Error if directory cannot be read
		 */
		public async void read_dir() throws Error
		{
			var dir = GLib.File.new_for_path(this.path);
			if (!dir.query_exists()) {
				throw new GLib.IOError.NOT_FOUND("Directory does not exist: " + this.path);
			}
			
			if (!dir.query_file_type(GLib.FileQueryInfoFlags.NONE, null) == GLib.FileType.DIRECTORY) {
				throw new GLib.IOError.NOT_DIRECTORY("Path is not a directory: " + this.path);
			}
			
			var enumerator = yield dir.enumerate_children_async(
				GLib.FileAttribute.STANDARD_NAME + "," + GLib.FileAttribute.FILE_TYPE,
				GLib.FileQueryInfoFlags.NONE,
				GLib.Priority.DEFAULT,
				null
			);
			
			var info_list = yield enumerator.next_files_async(100, GLib.Priority.DEFAULT, null);
			
			foreach (var info in info_list) {
				var name = info.get_name();
				var file_type = info.get_file_type();
				var child_path = GLib.Path.build_filename(this.path, name);
				
				// Check if child already exists in map
				if (this.child_map.has_key(name)) {
					continue;
				}
				
				FileBase child;
				if (file_type == GLib.FileType.DIRECTORY) {
					child = new Folder();
					child.path = child_path;
					child.parent = this;
					child.parent_id = this.id;
					if (this.manager != null) {
						child.manager = this.manager;
					}
				} else {
					child = new File();
					child.path = child_path;
					child.parent = this;
					child.parent_id = this.id;
					if (this.manager != null) {
						child.manager = this.manager;
					}
				}
				
				this.children.append(child);
				this.child_map[name] = child;
				this.child_added(child);
			}
			
			enumerator.close_async(GLib.Priority.DEFAULT, null);
		}
	}
}
