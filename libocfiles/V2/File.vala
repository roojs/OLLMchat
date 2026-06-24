/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
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
	 * Constructors: {@link File}(manager) for RPC-hydrated rows; {@link File.new_fake}
	 * for paths not yet in the DB ({@code id == -1}) until {@link register}.
	 *
	 * Client {@link File} — buffers and Gtk helpers stay local; disk/DB via RPC.
	 *
	 * == Content Access ==
	 * 
	 * All content access methods delegate to file.buffer. Ensure buffer is created before use:
	 * {{{
	 * if (file.buffer == null) {
	 *     file.manager.buffer_provider.create_buffer(file);
	 * }
	 * if (!(yield file.read())) {
	 *     // not found on daemon
	 * }
	 * var contents = file.buffer.get_text();
	 * }}}
	 */
	public class File : FileBase, Copyable
	{
		public static void rpc_register()
		{
			OLLMrpc.register("File", typeof(File));
		}

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
		 * Named constructor: create a {@link File} from {@link GLib.FileInfo} during scan.
		 *
		 * Removed — use {@link read} or {@link register}.
		 */
		
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
						GLib.FileAttribute.STANDARD_CONTENT_TYPE + "," +
						GLib.FileAttribute.TIME_MODIFIED,
						GLib.FileQueryInfoFlags.NONE,
						null
					);
					var content_type = file_info.get_content_type();
					this.is_text = content_type != null && content_type != "" && content_type.has_prefix("text/");
					if (!this.is_text && this.language != "") {
						this.is_text = true;
					}
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
			if (detected != "") {
				this.language = detected;
				//GLib.debug("File.detect_language: Detected language '%s' for file '%s'", 
				//	this.language, this.path);
			}
		}
		
		/**
		 * Last cursor line number (per-window; agent config — not on daemon).
		 */
		public int cursor_line { get; set; default = 0; }
		
		/**
		 * Last cursor character offset (per-window; agent config).
		 */
		public int cursor_offset { get; set; default = 0; }
		
		/**
		 * Last scroll position (per-window; agent config).
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
		 * Whether the file needs approval.
		 * true = needs approval, false = approved.
		 */
		public bool is_need_approval { get; set; default = false; }
		
		/**
		 * Whether the file has unsaved changes.
		 */
		public bool is_unsaved { get; set; default = false; }
		
		private string _icon_name = "";
		/**
		 * Icon name for binding in lists.
		 * Returns icon_name if set, otherwise derives from file content type.
		 */
		public override string to_summary(Gee.HashMap<int, OLLMfiles.SQT.VectorMetadata> keymap, string indent)
		{
			var type = "file";
			var description = "";
			if (keymap.has_key((int)this.id)) {
				var vm = keymap.get((int)this.id);
				if (vm.category != "" && vm.category != "other") {
					type = vm.category;
				}
				description = vm.description != "" ? ": " + vm.description : "";
			}
			if (type == "file" && this.language != "") {
				type = this.language;
			}
			return indent + "- (" + type + ") " + GLib.Path.get_basename(this.path) + description;
		}
		
		public override string icon_name {
			get {
				if (this._icon_name != "") {
					return this._icon_name;
				}
				if (this.path == "") {
					return "text-x-generic";
				}
				var content_type = GLib.ContentType.guess(this.path, null, null);
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
				this._icon_name = value;
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
					this.display_basename + (this.is_need_approval ? " ✗" : "") 
					+ (this.is_unsaved ? " ●" : "");
				return this._display_with_indicators; // X mark (✗) when needs approval (is_need_approval)
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
		 * if (!(yield file.read())) {
		 *     // not found on daemon
		 * }
		 * var contents = file.buffer.get_text();
		 * }}}
		 */
		public FileBuffer? buffer { get; set; default = null; }
		
		/**
		 * Emitted when file content changes.
		 */
		public signal void changed();

		// --- Daemon RPC ---

		/**
		 * Daemon disk probe ({@code File.exists}).
		 *
		 * Distinct from index membership ({@link Folder.fetch_file}) and content
		 * load ({@link read}). Callers use this for create-vs-modify and validate;
		 * **🚫** do not probe existence via {@link read}.
		 *
		 * Wire: {@code response.msg} is {@code ((int) GLib.FileType)} as decimal
		 * ({@link GLib.FileType.UNKNOWN} = path absent or RPC error).
		 *
		 * @return File type on daemon disk; {@link GLib.FileType.UNKNOWN} when absent
		 */
		public async GLib.FileType exists()
		{
			if (this.path.length == 0) {
				return GLib.FileType.UNKNOWN;
			}

			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "File.exists",
				param = new OLLMfilesd.FileParams() { path = this.path }
			});
			if (response.error != null || response.msg == "") {
				return GLib.FileType.UNKNOWN;
			}
			int type_code;
			if (!int.try_parse(response.msg, out type_code)) {
				return GLib.FileType.UNKNOWN;
			}
			return (GLib.FileType) type_code;
		}

		/**
		 * Load filebase + content from daemon ({@code File.read}).
		 *
		 * Wire: {@code result} is the {@link File} row (indexed id when in project,
		 * else {@code id == -1}); {@code response.msg} is file content;
		 * {@code response.msg_encode}: {@code 0} when {@code result.is_text},
		 * {@code 1} = base64 otherwise. Populates {@link buffer} from decoded
		 * {@code msg} — **🚫** no local disk read on thin client.
		 *
		 * Whether the path may be read (project vs permission-granted) is a
		 * tool/client decision; the daemon reads {@code params.path} on disk.
		 */
		public async bool read()
		{
			if (this.path.length == 0) {
				return false;
			}

			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "File.read",
				param = new OLLMfilesd.FileParams() { path = this.path }
			});
			if (response.error != null) {
				return false;
			}

			// Reply: {@link File} row via {@code result_type} + {@link rpc_register}.
			var row = response.result as File;
			if (row != null) {
				this.copy_from(row, {
					"buffer",
					"parent",
					"cursor-line",
					"cursor-offset",
					"scroll-position",
					"is-unsaved",
				});
			}

			if (this.buffer == null) {
				this.manager.buffer_provider.create_buffer(this);
			}
			try {
				yield this.buffer.clear();
				if (response.msg != "") {
					var replacement = response.msg;
					if (response.msg_encode == 1) {
						replacement = (string) GLib.Base64.decode(
							response.msg
						);
					}
					yield this.buffer.apply_edit(new FileChange(this) {
						start = 1,
						end = 1,
						replacement = replacement
					});
				}
				this.buffer.is_modified = false;
				this.buffer.last_read_timestamp = GLib.get_monotonic_time();
			} catch (GLib.Error e) {
				GLib.warning(
					"buffer load failed %s: %s",
					this.path,
					e.message
				);
				return false;
			}
			return true;
		}

		/**
		 * Write content to daemon ({@code File.write}); scan/index on server.
		 * Uses {@link buffer} text when {@code content} is empty.
		 *
		 * @return false when RPC fails or path is empty
		 */
		public async bool write(string content = "")
		{
			if (this.path.length == 0) {
				return false;
			}
			if (content == "" && this.buffer != null) {
				content = this.buffer.get_text();
			}

			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "File.write",
				param = new OLLMfilesd.FileParams() {
					path = this.path,
					content = content
				}
			});
			if (response.error != null) {
				return false;
			}
			if (this.buffer != null) {
				this.buffer.is_modified = false;
			}
			return true;
		}

		/**
		 * Check disk change vs buffer ({@code File.changed.check}).
		 */
		public async FileUpdateStatus check_changed()
		{
			if (this.path.length == 0) {
				return FileUpdateStatus.NO_CHANGE;
			}

			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "File.changed.check",
				param = new OLLMfilesd.FileParams() {
					path = this.path,
					buffer_dirty = this.buffer != null && this.buffer.is_modified,
					last_known_mtime = this.last_modified
				}
			});
			if (response.error != null) {
				return FileUpdateStatus.NO_CHANGE;
			}
			int status_code;
			if (int.try_parse(response.msg, out status_code)) {
				return (FileUpdateStatus) status_code;
			}
			return FileUpdateStatus.NO_CHANGE;
		}

		/**
		 * Register fake file ({@code id == -1}) on daemon ({@code File.register}).
		 *
		 * On success, {@link Copyable.copy_from} merges {@code response.result} onto
		 * this instance (same object for buffer/UI).
		 */
		public async bool register()
		{
			if (this.path.length == 0) {
				return false;
			}
			if (this.id != -1) {
				return true;
			}

			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "File.register",
				param = new OLLMfilesd.FileParams() { path = this.path }
			});
			if (response.error != null) {
				return false;
			}

			var real_file = response.result as File;
			if (real_file != null) {
				this.copy_from(real_file, {
					"buffer",
					"parent",
					"cursor-line",
					"cursor-offset",
					"scroll-position",
					"is-unsaved",
				});
				this.manager.file_cache.set(this.path, this);
			}
			return true;
		}

		/**
		 * Delete file on daemon ({@code File.delete}).
		 */
		public async bool delete()
		{
			if (this.path.length == 0) {
				return false;
			}

			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "File.delete",
				param = new OLLMfilesd.FileParams() { path = this.path }
			});
			return response.error == null;
		}
		
		/**
		 * Gets file contents: either a head slice (first ''N'' lines) or a 1-based line range.
		 * 
		 * Convenience method that delegates to ''file.buffer.get_text()''. Requires
		 * ''file.buffer'' to be non-null. Ensure buffer is created before use.
		 * 
		 * == Important ==
		 * 
		 * This method requires ''file.buffer'' to be non-null. Ensure buffer is created
		 * before use:
		 * {{{
		 *         if (file.buffer == null) {
		 *                 file.manager.buffer_provider.create_buffer(file);
		 *         }
		 *         var all = file.contents();
		 * }}}
		 * Buffer must be loaded first (via {@link read} or after edits).
		 * 
		 * == Two modes (second parameter) ==
		 * 
		 *  * ''end_line == -1'' (default) — ''start_or_count'' is how many lines to take
		 *    from the **start** of the file:
		 *    ''-1'' or ''0'' (or any value less than or equal to zero) means the **whole** file;
		 *    ''N > 0'' means the first ''N'' lines (e.g. ''contents(2)'' is the first two lines).
		 *  * ''end_line != -1'' — ''start_or_count'' and ''end_line'' are
		 *    **1-based inclusive** line numbers (e.g. ''contents(2, 5)'' is lines 2 through 5).
		 *    The lower and upper lines are ''int.min'' / ''int.max'' so the pair may be passed
		 *    in either order. Further bounds and clamping are handled by ''buffer.get_text()''.
		 * 
		 * @param start_or_count Head mode: line count from the top; ''-1'' or ''0'' =
		 *   entire file. Range mode: first line number, **1-based inclusive** (unchanged).
		 * @param end_line ''-1'' = head mode; else end line (1-based inclusive)
		 * @return File contents, or empty string if not available
		 */
		public string contents(int start_or_count = -1, int end_line = -1)
		{
			if (this.buffer == null) {
				return "";
			}
			if (end_line == -1) {
				return this.buffer.get_text(0, start_or_count > 0 ? start_or_count - 1 : -1);
			}
			// Range: start ''0'' or ''-1'' → first line (0-based start ''0'').
			return this.buffer.get_text(int.max(1, start_or_count) - 1, end_line - 1);
		}
		
		/**
		 * Gets the total number of lines in the file.
		 * 
		 * Convenience method that delegates to file.buffer.get_line_count().
		 * Requires file.buffer to be non-null. Ensure buffer is created before use.
		 * 
		 * @return Line count, or 0 if not available
		 */
		public int line_count()
		{
			if (this.buffer == null) {
				return 0;
			}
			return this.buffer.get_line_count();
		}
		
		/**
		 * Gets the currently selected text (only valid for active file).
		 *
		 * Delegates to {@link buffer}. Updates {@link cursor_line} / {@link cursor_offset}
		 * in memory only.
		 */
		public string get_selected_code()
		{
			if (this.buffer == null) {
				return "";
			}
			
			int cursor_line, cursor_offset;
			var selected = this.buffer.get_selection(out cursor_line, out cursor_offset);
			
			this.cursor_line = cursor_line;
			this.cursor_offset = cursor_offset;
			
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
		 * Delegates to {@link buffer}. Updates {@link cursor_line} / {@link cursor_offset}
		 * in memory only.
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
			
			return this.cursor_line;
		}

		/**
		 * Check if the file has been modified on disk and differs from the buffer.
		 *
		 * Removed — use {@link check_changed}.
		 */

		/**
		 * Approve this file and all its FileHistory items.
		 *
		 * Removed — {@code FileHistory.approve} RPC.
		 */

		/**
		 * Whether this file is a documentation file (plain text or markdown, not code).
		 *
		 * Removed — daemon {@code Indexer} only.
		 */

		/**
		 * Revert this file to previous version from FileHistory backup.
		 *
		 * Removed — {@code FileHistory.revert} RPC.
		 */

	}
}
