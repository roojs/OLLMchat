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

namespace OLLMfilesd
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
	 * Daemon {@link File} — scan, disk I/O, and {@code File.*} RPC.
	 * Editor buffers and Gtk helpers live on {@code libocfiles/File.vala}.
	 */
	public class File : FileBase
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("File", typeof(File));
			FileParams.rpc_register();
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

		public signal void call_read(OLLMrpc.Request request);
		public signal void call_exists(OLLMrpc.Request request);
		public signal void call_fetch(OLLMrpc.Request request);
		public signal void call_write(OLLMrpc.Request request);
		public signal void call_apply_permissions(OLLMrpc.Request request);
		public signal void call_register(OLLMrpc.Request request);
		public signal void call_delete(OLLMrpc.Request request);
		public signal void call_changed_check(OLLMrpc.Request request);

		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			if (prop.name == "buffer") {
				return;
			}
			base.bin_write_prop(ctx, prop);
		}

		public override void bin_read_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			if (prop.name == "buffer") {
				return;
			}
			base.bin_read_prop(ctx, prop, type_byte);
		}

		construct
		{
			this.call_read.connect((request) => {
				var path = ((FileParams) request.param).path;
				uint8[] data;
				string etag;
				try {
					GLib.File.new_for_path(path).load_contents(
						null,
						out data,
						out etag
					);
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error(
							OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
							e.message
						)
					});
					return;
				}
				var row = new File(this.manager);
				var indexed = this.manager.get_file_from_active_project(path);
				if (indexed != null) {
					row.copy_from(indexed, {
						"manager",
						"buffer",
						"parent"
					});
					row.last_modified = indexed.mtime_on_disk();
				} else {
					row.path = path;
					row.id = -1;
				}
				var result = new Gee.ArrayList<GLib.Object>();
				result.add(row);
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					result = result,
					msg = row.is_text ? (string) data : GLib.Base64.encode(
						data[0:data.length > 0 ? data.length - 1 : 0]
					),
					msg_encode = row.is_text ? 0 : 1
				});
			});
			this.call_exists.connect((request) => {
				var file_type = GLib.FileType.UNKNOWN;
				try {
					file_type = GLib.File.new_for_path(
						((FileParams) request.param).path
					).query_file_type(
						GLib.FileQueryInfoFlags.NONE,
						null
					);
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = ((int) GLib.FileType.UNKNOWN).to_string()
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = ((int) file_type).to_string()
				});
			});
			this.call_fetch.connect((request) => {
				var p = (FileParams) request.param;
				var project = this.manager.project_root(p.project_path);
				if (project == null) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = "project not found"
					});
					return;
				}
				var project_file = project.project_files.child_map.get(p.path);
				if (project_file == null) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = "file not found"
					});
					return;
				}
				var source = project_file.file;
				var row = new File(this.manager) {
					last_modified = source.mtime_on_disk()
				};
				row.copy_from(
					source,
					{"manager", "buffer", "parent", "last-modified"}
				);
				var result = new Gee.ArrayList<GLib.Object>();
				result.add(row);
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					result = result
				});
			});
			this.call_write.connect((request) => {
				var p = (FileParams) request.param;
				this.write.begin(
					p,
					request,
					(obj, res) => {
						this.write.end(res);
					}
				);
			});
			this.call_apply_permissions.connect((request) => {
				var p = (FileParams) request.param;
				if (Posix.chmod(
					p.path,
					(Posix.mode_t) (p.unix_mode & 0777)
				) != 0) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error(
							OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
							GLib.strerror(Posix.errno)
						)
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
			});
			this.call_register.connect((request) => {
				var p = (FileParams) request.param;
				var existing = this.manager.get_file_from_active_project(p.path);
				if (existing != null && existing.id != -1) {
					var row = new File(this.manager);
					row.copy_from(existing, {"manager", "buffer", "parent"});
					row.last_modified = existing.mtime_on_disk();
					var result = new Gee.ArrayList<GLib.Object>();
					result.add(row);
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						result = result
					});
					return;
				}
				var fake = new File(this.manager) {
					path = p.path,
					id = -1
				};
				fake.to_real.begin((obj, res) => {
					try {
						fake.to_real.end(res);
					} catch (GLib.Error e) {
						request.reply(new OLLMrpc.Response() {
							id = request.id,
							error = new OLLMrpc.Error(
								OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
								e.message
							)
						});
						return;
					}
					var row = new File(this.manager);
					row.copy_from(fake, {"manager", "buffer", "parent"});
					row.last_modified = fake.mtime_on_disk();
					var result = new Gee.ArrayList<GLib.Object>();
					result.add(row);
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						result = result
					});
				});
			});
			this.call_delete.connect((request) => {
				var file = this.manager.get_file_from_active_project(
					((FileParams) request.param).path
				);
				this.manager.delete_manager.remove.begin(
					file,
					new GLib.DateTime.now_local(),
					(obj, res) => {
						this.manager.delete_manager.remove.end(res);
						this.manager.delete_manager.cleanup.begin();
					}
				);
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
			});
			this.call_changed_check.connect((request) => {
				var p = (FileParams) request.param;
				var file = this.manager.get_file_from_active_project(p.path);
				var status = FileUpdateStatus.NO_CHANGE;
				if (file.mtime_on_disk() > p.last_known_mtime
					&& p.buffer_dirty) {
					status = FileUpdateStatus.CHANGED_HAS_UNSAVED;
				}
				request.reply(new OLLMrpc.Response() {
					msg = ((int) status).to_string()
				});
			});
		}

		private async void write(
			FileParams p,
			OLLMrpc.Request request
		) {
			try {
				switch (p.base_type) {
					case "d": {
						var folder = this.manager.get_folder_at_path(p.path);
						if (folder == null) {
							folder = new Folder(this.manager) {
								path = p.path,
								id = -1
							};
						}
						if (folder.id < 0) {
							yield folder.to_real();
						}
						yield folder.realize(p);
						break;
					}
					case "fa": {
						var alias = this.manager.file_cache.get(
							p.path
						) as FileAlias;
						if (alias == null) {
							alias = new FileAlias(this.manager) {
								path = p.path,
								id = -1
							};
						}
						if (alias.id < 0) {
							yield alias.to_real(p.target);
						}
						yield alias.realize(p);
						break;
					}
					default: {
						var file = this.manager.get_file_from_active_project(
							p.path
						);
						if (file == null) {
							file = new File(this.manager) {
								path = p.path,
								id = -1
							};
						}
						if (file.id < 0) {
							yield file.to_real();
						}
						yield file.realize(p);
						break;
					}
				}
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						e.message
					)
				});
				return;
			}
			request.reply(new OLLMrpc.Response() { msg = "ok" });
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
			if (this.language == "") {
				this.detect_language();
			}
			// Treat as text if we have a code language (e.g. .php → application/x-php, not text/*)
			if (!this.is_text && this.language != "") {
				this.is_text = true;
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
		
		public override string to_summary(Gee.HashMap<int, OLLMvector2.SQT.VectorMetadata> keymap, string indent)
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
		
		/** In-process buffer for {@code rpc_write} / {@code revert} disk paths. */
		public FileBuffer? buffer { get; set; default = null; }
		
		/**
		 * Approve this file and all its FileHistory items.
		 * 
		 * Sets is_need_approval = false and updates all FileHistory records
		 * for this file to status = 1 (approved).
		 */
		public void approve()
		{
			// Approve file
			this.is_need_approval = false;
			this.last_change_type = "";
			this.saveToDB(this.manager.db, null, false);
			
			// Approve all FileHistory items for this file using query wrapper
			var db = this.manager.db;
			var history_records = new Gee.ArrayList<FileHistory>();
			try {
				FileHistory.query(db).select(
					"WHERE filebase_id = %lld".printf(this.id),
					history_records
				);
			} catch (GLib.Error e) {
				GLib.warning("Failed to query FileHistory for approval: %s", e.message);
				return;
			}
			
			// Update each FileHistory record to approved status
			foreach (var history in history_records) {
				history.status = 1;
				try {
					FileHistory.query(db).updateById(history);
				} catch (GLib.Error e) {
					GLib.warning("Failed to update FileHistory status: %s", e.message);
				}
			}
		}
		
		/**
		 * Whether this file is a documentation file (plain text or markdown, not code).
		 * 
		 * Uses is_text and language (from BufferProvider.detect_language()).
		 * Returns true for markdown, plain text, and unknown text; false for code and structured formats.
		 */
		public bool is_documentation()
		{
			if (!this.is_text) {
				return false;
			}
			
			var lang = this.language;
			if (lang == null || lang == "") {
				return true;
			}
			
			var lang_lower = lang.down();
			
			switch (lang_lower) {
				case "markdown":
				case "txt":
				case "text":
				case "plaintext":
					return true;
				default:
					// Code languages (vala, python, c, etc.) and structured formats (html, xml, json, yaml, css, etc.)
					return false;
			}
		}
		
		/**
		 * Revert this file to previous version from FileHistory backup.
		 * 
		 * Finds the most recent FileHistory record with a backup for this file
		 * and restores the file from that backup. Before restoring, creates a new
		 * FileHistory record with change_type="revert" to backup the rejected content
		 * (flagged as approved). Updates the original FileHistory status to rejected (-1)
		 * and sets is_need_approval = true.
		 * 
		 * @throws Error if backup file doesn't exist or restore fails
		 */
		public async void revert() throws Error
		{
			// Get FileHistory records for this file
			var db = this.manager.db;
			var history_records = new Gee.ArrayList<FileHistory>();
			try {
				yield FileHistory.query(db).select_async(
					"WHERE filebase_id = %lld AND backup_path != '' ORDER BY timestamp DESC LIMIT 1".printf(this.id),
					history_records
				);
			} catch (GLib.Error e) {
				throw new GLib.IOError.NOT_FOUND("Failed to query FileHistory for revert: %s".printf(e.message));
			}
			
			if (history_records.size == 0) {
				throw new GLib.IOError.NOT_FOUND("No backup found for file: %s".printf(this.path));
			}
			
			// Get the most recent FileHistory record with backup
			var history = history_records[0];
			
			// Check if backup exists
			if (history.backup_path == "" || !GLib.FileUtils.test(history.backup_path, GLib.FileTest.EXISTS)) {
				throw new GLib.IOError.NOT_FOUND("Backup file does not exist: %s".printf(history.backup_path));
			}
			
			// Check change type - cannot revert "added" files (no backup)
			if (history.change_type == "added") {
				throw new GLib.IOError.INVALID_ARGUMENT("Cannot revert added files (no backup exists)");
			}
			
			// Before restoring, backup the current content (the rejected content)
			// Create a new FileHistory record with change_type="revert" to backup the rejected content
			var now = new GLib.DateTime.now_local();
			var revert_history = new FileHistory(
				db,
				this,
				"revert",
				now
			);
			
			// Set status to approved (1) for the revert record
			revert_history.status = 1;
			
			// Commit the revert history record (creates backup of current content)
			yield revert_history.commit();
			
			// Copy backup file back to original path
			var backup_file = GLib.File.new_for_path(history.backup_path);
			var target_file = GLib.File.new_for_path(history.path);
			
			// Create parent directory if it doesn't exist (for deleted files)
			var parent_dir = target_file.get_parent();
			if (parent_dir != null && !parent_dir.query_exists()) {
				parent_dir.make_directory_with_parents(null);
			}
			
			// Copy backup to original location (overwrites existing file)
			backup_file.copy(
				target_file,
				GLib.FileCopyFlags.OVERWRITE,
				null,
				null
			);
			
			// Update File object metadata
			this.last_modified = now.to_unix();
		
			// Save File object to database
			this.saveToDB(db, null, false);
			
			// Reload buffer if it exists (file content changed on disk)
			if (this.buffer != null) {
				try {
					yield this.buffer.read_async();
				} catch (GLib.Error e) {
					GLib.warning("Failed to reload buffer after revert for %s: %s", this.path, e.message);
				}
			}
			
			// Update FileHistory status to rejected (-1) using query wrapper
			history.status = -1;
			try {
				FileHistory.query(db).updateById(history);
			} catch (GLib.Error e) {
				GLib.warning("Failed to update FileHistory status: %s", e.message);
			}
			
			this.last_change_type = "";
			this.is_need_approval = false;
			this.saveToDB(db, null, false);
		}

		/**
		 * Promote fake file ({@code id == -1}) to indexed row (DB + parent chain).
		 * Does not touch the filesystem — call {@link realize} after.
		 */
		public async void to_real() throws Error
		{
			if (this.id != -1) {
				return;
			}
			if (this.manager.active_project == null) {
				return;
			}
			var found_base_folder = this.manager.active_project.project_files.find_container_of(
				GLib.Path.get_dirname(this.path)
			);
			if (found_base_folder == null) {
				return;
			}
			var parent_folder = yield found_base_folder.make_children(this.path);
			if (parent_folder == null) {
				throw new GLib.IOError.FAILED(
					"Could not create parent folder for "
					+ this.path
				);
			}
			this.parent = parent_folder;
			this.parent_id = parent_folder.id;
			this.id = 0;
			this.detect_language();
			if (this.language != "") {
				this.is_text = true;
			}
			parent_folder.children.append(this);
			this.manager.buffer_provider.create_buffer(this);
			if (this.manager.db != null) {
				this.saveToDB(this.manager.db, null, false);
			}
			if (this.manager.db == null) {
				this.manager.file_cache.set(this.path, this);
			}
			this.manager.active_project.project_files.update_from(
				this.manager.active_project
			);
			this.manager.active_project.project_files.new_file_added(this);
		}

		/**
		 * Apply {@link FileParams} on disk for an indexed file (write bytes + mode).
		 */
		public async void realize(FileParams p) throws Error
		{
			if (this.buffer == null) {
				this.manager.buffer_provider.create_buffer(this);
			}
			yield this.buffer.write_real(p.content);
			if (p.unix_mode == 0) {
				return;
			}
			if (Posix.chmod(
				this.path,
				(Posix.mode_t) (p.unix_mode & 0777)
			) != 0) {
				throw new GLib.IOError.FAILED(GLib.strerror(Posix.errno));
			}
		}
		
	}
}
