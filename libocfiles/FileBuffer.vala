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
	 * Interface for file buffer operations.
	 * 
	 * Provides a unified interface for accessing file contents, whether
	 * using GTK buffers (for GUI contexts) or in-memory buffers (for tools/CLI).
	 */
	public interface FileBuffer : Object
	{
		/**
		 * Reference to the file this buffer represents.
		 */
		public abstract File file { get; set; }
		
		/**
		 * Read file contents asynchronously.
		 * 
		 * For GTK buffers: Checks file modification time and reloads if needed.
		 * For dummy buffers: Always reads from disk.
		 * 
		 * @return File contents as string
		 * @throws Error if file cannot be read
		 */
		public abstract async string read_async() throws Error;
		
		/**
		 * Internal method: Read file from disk and update last_viewed timestamp.
		 * 
		 * Shared implementation for reading file contents. Updates file.last_viewed.
		 * 
		 * @return File contents as string
		 * @throws Error if file cannot be read
		 */
		protected async string read_async_real() throws Error
		{
			var file_obj = GLib.File.new_for_path(this.file.path);
			if (!file_obj.query_exists()) {
				throw new GLib.FileError.NOENT("File not found: " + this.file.path);
			}
			
			uint8[] data;
			string etag;
			yield file_obj.load_contents_async(null, out data, out etag);
			
			// Update last_viewed timestamp
			this.file.last_viewed = new GLib.DateTime.now_local().to_unix();
			
			return (string)data;
		}
		
		/**
		 * Get text from buffer, optionally limited to a line range.
		 * 
		 * @param start_line Starting line number (0-based, inclusive)
		 * @param end_line Ending line number (0-based, inclusive), or -1 for all lines
		 * @return The buffer text, or empty string if not available
		 */
		public abstract string get_text(int start_line = 0, int end_line = -1);
		
		/**
		 * Get the total number of lines in the buffer.
		 * 
		 * @return Line count, or 0 if not available
		 */
		public abstract int get_line_count();
		
		/**
		 * Get the content of a specific line.
		 * 
		 * @param line Line number (0-based)
		 * @return Line content, or empty string if not available
		 */
		public abstract string get_line(int line);
		
		/**
		 * Get the current cursor position.
		 * 
		 * @param line Output parameter for cursor line number
		 * @param offset Output parameter for cursor character offset
		 */
		public abstract void get_cursor(out int line, out int offset);
		
		/**
		 * Get the currently selected text and cursor position.
		 * 
		 * @param cursor_line Output parameter for cursor line number
		 * @param cursor_offset Output parameter for cursor character offset
		 * @return Selected text, or empty string if nothing is selected
		 */
		public abstract string get_selection(out int cursor_line, out int cursor_offset);
		
		/**
		 * Whether the buffer has been loaded with file content.
		 * 
		 * Returns true if the buffer has been loaded from the file,
		 * false if it needs to be loaded.
		 */
		public abstract bool is_loaded { get; set; }
		
		/**
		 * Write contents to buffer and file.
		 * 
		 * Updates buffer contents and writes to file on disk.
		 * For files in database, creates backup before writing.
		 * 
		 * @param contents Contents to write
		 * @throws Error if file cannot be written
		 */
		public abstract async void write(string contents) throws Error;
		
		/**
		 * Sync buffer contents to file on disk asynchronously.
		 * 
		 * Gets the current buffer contents and writes them to the file.
		 * For GTK buffers: Also marks the buffer as not modified.
		 * For dummy buffers: Not supported - use write() instead.
		 * Creates backup if needed, writes to disk, and updates file metadata.
		 * 
		 * @throws Error if file cannot be written or method is not supported
		 */
		public abstract async void sync_to_file() throws Error;
		
		/**
		 * Write contents to file on disk (sync buffer to file).
		 * 
		 * Creates backup if needed, writes to disk, and updates file metadata.
		 * This is used when the buffer already has the contents and we just need
		 * to sync it to the file. Unlike write(), this does not update the buffer contents.
		 * 
		 * @param contents Contents to write
		 * @throws Error if file cannot be written
		 */
		public async void write_real(string contents) throws Error
		{
			// Create backup if needed
			yield this.create_backup_if_needed();
			
			// Write to file
			yield this.write_to_disk(contents);
			
			// Update file metadata
			this.update_file_metadata_after_write();
		}
		
		/**
		 * Internal method: Create backup if file is in database.
		 * 
		 * Backup path: ~/.cache/ollmchat/edited/{id}-{date YY-MM-DD}-{basename}
		 * Only creates backup if doesn't exist for today.
		 */
		protected async void create_backup_if_needed()
		{
			// Only create backup if file is in database (id > 0)
			if (this.file.id <= 0) {
				return;
			}
			
			try {
				var cache_dir = GLib.Path.build_filename(
					GLib.Environment.get_home_dir(),
					".cache",
					"ollmchat",
					"edited"
				);
				
				// Create cache directory if it doesn't exist
				var cache_dir_file = GLib.File.new_for_path(cache_dir);
				if (!cache_dir_file.query_exists()) {
					cache_dir_file.make_directory_with_parents(null);
				}
				
				// Generate backup filename with date
				var basename = GLib.Path.get_basename(this.file.path);
				var backup_path = GLib.Path.build_filename(
					cache_dir,
					"%lld-%s-%s".printf(
						this.file.id,
						new GLib.DateTime.now_local().format("%y-%m-%d"),
						basename
					)
				);
				
				// Check if backup already exists for today
				var backup_file = GLib.File.new_for_path(backup_path);
				if (backup_file.query_exists()) {
					// Backup already exists for today, skip
					return;
				}
				
				// Copy current file to backup location asynchronously
				var source_file = GLib.File.new_for_path(this.file.path);
				if (!source_file.query_exists()) {
					return;
				}
				
				// Open source file for reading asynchronously
				var input_stream = yield source_file.read_async(GLib.Priority.DEFAULT, null);
				
				// Open destination file for writing asynchronously (replace existing)
				var output_stream = yield backup_file.replace_async(
					null,
					false,
					GLib.FileCreateFlags.NONE,
					GLib.Priority.DEFAULT,
					null
				);
				
				// Copy data from input to output stream asynchronously
				yield output_stream.splice_async(
					input_stream,
					GLib.OutputStreamSpliceFlags.CLOSE_SOURCE | GLib.OutputStreamSpliceFlags.CLOSE_TARGET,
					GLib.Priority.DEFAULT,
					null
				);
				
				// Update file's last_approved_copy_path
				this.file.last_approved_copy_path = backup_path;
				
				// Save file to database
				if (this.file.manager.db != null) {
					this.file.saveToDB(this.file.manager.db, null, false);
				}
				
				// Cleanup old backup files (runs at most once per day)
				ProjectManager.cleanup_old_backups.begin();
			} catch (GLib.Error e) {
				GLib.warning("FileBuffer.create_backup_if_needed: Failed to create backup for %s: %s", 
					this.file.path, e.message);
			}
		}
		
		/**
		 * Internal method: Write contents to file on disk.
		 * 
		 * @param contents Contents to write
		 * @throws Error if file cannot be written
		 */
		protected async void write_to_disk(string contents) throws Error
		{
			var dirname = GLib.Path.get_dirname(this.file.path);
			var dir_file = GLib.File.new_for_path(dirname);
			if (!dir_file.query_exists()) {
				dir_file.make_directory_with_parents(null);
			}
			
			var file_obj = GLib.File.new_for_path(this.file.path);
			var output_stream = yield file_obj.replace_async(
				null,
				false,
				GLib.FileCreateFlags.NONE,
				GLib.Priority.DEFAULT,
				null
			);
			
			// Write contents asynchronously
			uint8[] data = contents.data;
			size_t bytes_written;
			yield output_stream.write_all_async(data, GLib.Priority.DEFAULT, null, out bytes_written);
			
			// Close stream asynchronously
			yield output_stream.close_async(GLib.Priority.DEFAULT, null);
		}
		
		/**
		 * Internal method: Update file metadata after writing.
		 * 
		 * Updates last_modified, saves to database, updates last_viewed, and emits changed signal.
		 */
		protected void update_file_metadata_after_write()
		{
			// Update last_modified from filesystem after writing
			this.file.last_modified = this.file.mtime_on_disk();
			
			// Save to database with sync to disk
			if (this.file.manager.db != null) {
				this.file.saveToDB(this.file.manager.db, null, true);
			}
			
			// Update last_viewed timestamp
			this.file.last_viewed = new GLib.DateTime.now_local().to_unix();
			
			this.file.changed();
		}
	}
}

