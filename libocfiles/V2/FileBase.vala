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
	 * Abstract base class providing common properties and methods for files and folders.
	 * 
	 * FileBase is the foundation of the file system hierarchy:
	 * 
	 *  * File: Represents individual files
	 *  * Folder: Represents directories (can also be projects when is_project = true)
	 *  * FileAlias: Represents symlinks/aliases to files or folders
	 * 
	 * Client row — {@code filebase} wire fields + Gtk display helpers.
	 * DB, scan, and {@code saveToDB} live on the daemon ({@code ollmfilesd/FileBase.vala}).
	 *
	 * == ID Semantics ==
	 *
	 *  * id = 0: new row (not yet registered)
	 *  * id > 0: real filebase id from daemon
	 *  * id < 0: fake file ({@link File.new_fake}) until {@link File.to_real}
	 */
	public abstract class FileBase : Object, OLLMrpc.Bin.Serializable
	{
		/**
		 * Database ID.
		 * 
		 * Semantics: 0 = new file (will be inserted), >0 = existing file (will be updated),
		 * <0 = fake file (not in database, skips DB operations).
		 */
		public int64 id { get; set; default = 0; }
		
		/**
		 * File/folder path.
		 */
		public string path { get; set; default = ""; }
		
		/**
		 * Parent folder ID for database storage.
		 */
		public int64 parent_id { get; set; default = 0; }
		
		/**
		 * Reference to parent folder (nullable for root folders/projects).
		 */
		public Folder? parent { get; set; default = null; }
		
		/**
		 * Whether this is an alias/symlink.
		 * Computed property: Returns true if this is a FileAlias.
		 */
		public bool is_alias {
			get {
				return (this is FileAlias);
			}
		}
		
		/**
		 * Reference to the FileBase object this alias points to (nullable, only set when is_alias = true).
		 * This is the actual object reference, loaded from database via points_to_id.
		 */
		public FileBase? points_to { get; set; default = null; }
		
		/**
		 * The ID of the FileBase object this alias points to (foreign key reference).
		 */
		public int64 points_to_id { get; set; default = 0; }
		
		/**
		 * The path of the FileBase object this alias points to (for database queries).
		 * This is stored in the database to enable efficient path-based lookups.
		 */
		public string target_path { get; set; default = ""; }
		
		/**
		 * Reference to ProjectManager.
		 * 
		 */
		public ProjectManager manager { get; set; }
		
		/**
		 * Icon name for binding in lists.
		 * Returns icon_name if set, otherwise a default based on type.
		 */
		public virtual string icon_name {
			get { return "folder"; }
			set {}
		}
 		
		/**
		 * Display name for binding in lists.
		 */
		public string display_name { get; set; default = ""; }
		
		/**
		 * Basename derived from path (for property binding).
		 */
		public string path_basename {
			owned get { return GLib.Path.get_basename(this.path); }
		}
		
		/**
		 * Display text with status indicators.
		 * Base implementation just returns display_name.
		 */
		public virtual string display_with_indicators {
			get { return this.display_name; 	}
		}
		
		/**
		 * Tooltip text for binding in lists.
		 */
		public string tooltip { get; set; default = ""; }
		
		/**
		 * Base type identifier for serialization and database storage.
		 * 
		 * Type identifiers: "f" = File, "d" = Folder/Directory, "fa" = FileAlias (file alias),
		 * "da" = FileAlias (folder alias). Projects are folders with is_project = true
		 * (no separate "p" type).
		 */
		public string base_type { get; set; default = ""; }
		
		/**
		 * Whether this is the currently active/viewed item.
		 */
		public bool is_active { get; set; default = false; }
		
		/**
		 * Programming language (optional, for files).
		 */
		public string language { get; set; default = ""; }
		
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
		 * Whether the file needs approval.
		 */
		public bool is_need_approval { get; set; default = false; }
		
		/**
		 * The most recent change type from FileHistory ("added", "modified", "deleted", or "").
		 * Set when is_need_approval is set to true.
		 */
		public string last_change_type { get; set; default = ""; }
		
		/**
		 * Whether the file has unsaved changes.
		 */
		public bool is_unsaved { get; set; default = false; }
		
		/**
		 * Whether this folder represents a project (stored in database, default: false).
		 */
		public bool is_project { get; set; default = false; }
		
		/**
		 * Unix timestamp of last view (stored in database, default: 0).
		 */
		public int64 last_viewed { get; set; default = 0; }
		
		/**
		 * Unix timestamp of last modification (stored in database, default: 0).
		 */
		public int64 last_modified { get; set; default = 0; }
		
		/**
		 * Whether this file is ignored by git (stored in database, default: false).
		 */
		public bool is_ignored { get; set; default = false; }
		
		/**
		 * Whether this file is a text file (stored in database, default: false).
		 */
		public bool is_text { get; set; default = false; }
		
		/**
		 * Whether this folder is a git repository (stored in database, default: -1).
		 * -1 = not checked, 0 = checked and not a repo, 1 = it is a repo.
		 */
		public int is_repo { get; set; default = -1; }
		
		/**
		 * Unix timestamp of last vector scan (stored in database, default: 0).
		 * For files: timestamp when vector scan completed (after successful vectorization).
		 * For folders: timestamp when vector scan started (to prevent re-recursion during same scan).
		 */
		public int64 last_vector_scan { get; set; default = 0; }
		
		/**
		 * Reference to FileHistory record where this file was deleted.
		 * 
		 * If delete_id = 0, the file is not deleted.
		 * If delete_id > 0, the file is deleted and delete_id points to file_history.id
		 * where change_type="deleted".
		 * 
		 * Deleted files are flagged rather than immediately removed from database,
		 * allowing for cleanup operations and UI updates. Files with delete_id > 0
		 * should be excluded from UI lists and scanning operations.
		 * 
		 * Provides direct link to deletion information (timestamp, agent, etc.)
		 * via the FileHistory record.
		 */
		public int64 delete_id { get; set; default = 0; }
		
		/**
		 * Get modification time on disk (Unix timestamp).
		 *
		 * Removed — daemon scan only ({@code ollmfilesd/FileBase.vala}).
		 */

		/**
		 * Initialize database table for filebase objects.
		 *
		 * Removed — daemon only ({@code FileBase.init_db} on {@code ollmfilesd}).
		 */

		/**
		 * Create a query object for filebase table with typemap configured.
		 *
		 * Removed — daemon only ({@code FileBase.query} on {@code ollmfilesd}).
		 */

		/**
		 * Compare this FileBase with another to determine if they represent the same item.
		 *
		 * Removed — daemon {@code read_dir} scan only.
		 */

		/**
		 * Copy database-preserved fields from this object to another.
		 *
		 * Removed — daemon scan only. Client uses {@link Copyable.copy_from} from RPC.
		 */

		/**
		 * Save filebase object to SQLite database.
		 *
		 * Removed — daemon only. Client rows updated via RPC + {@link Copyable}.
		 */

		/**
		 * Remove filebase object from SQLite database.
		 *
		 * Removed — use {@link File.delete} RPC.
		 */

		/**
		 * Get target info for a given path.
		 *
		 * Removed — daemon alias scan only.
		 */

		/**
		 * Display text for approval list with visual indicators.
		 * 
		 * Returns formatted text for display in approvals list:
		 * - "+ filename" for new files
		 * - "<s>filename</s>" (Pango markup strikethrough) for deleted files
		 * - "filename" for modified files
		 */
		public string display_approval_text {
			owned get {
				switch (this.last_change_type) {
					case "added":
						return "+ " + this.path_basename;
					case "deleted":
						return "<s>" + this.path_basename + "</s>";
					default:
						// Modified or no change type
						return this.path_basename;
				}
			}
		}
		
		/**
		 * Tooltip text for approval list with full path and change type.
		 * 
		 * Returns tooltip text with full path and change type:
		 * - "Added /path/to/file" for new files
		 * - "Modified /path/to/file" for modified files
		 * - "Deleted /path/to/file" for deleted files
		 */
		public string display_approval_tooltip {
			owned get {
				switch (this.last_change_type) {
					case "added":
						return "Added " + this.path;
					case "deleted":
						return "Deleted " + this.path;
					case "modified":
						return "Modified " + this.path;
					default:
						// No change type or unknown
						return this.path;
				}
			}
		}

		/**
		 * Constructor.
		 *
		 * @param manager The ProjectManager instance (required)
		 */
		protected FileBase(ProjectManager manager)
		{
			Object(manager: manager);
		}

		/**
		 * Returns one or more lines for the project summary list.
		 *
		 * @param indent Leading indent for this line; Folder passes indent + "  " to children.
		 */
		public abstract string to_summary(
			Gee.HashMap<int, OLLMfiles.SQT.VectorMetadata> keymap, string indent);

		public virtual void bin_write_prop (
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "manager":
				case "parent":
					return;
				default:
					this.bin_default_write_prop (ctx, prop);
					return;
			}
		}

		public virtual void bin_read_prop (
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			switch (prop.name) {
				case "manager":
				case "parent":
					return;
				default:
					this.bin_default_read_prop (ctx, prop, type_byte);
					return;
			}
		}
		
	}
}
