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

namespace OLLMchat.ChatPermission
{
	/**
	 * Operation types for permission requests.
	 * Can be combined using bitwise OR (e.g., READ | WRITE).
	 */
	[Flags]
	public enum Operation
	{
		READ = 1 << 0,      // "r" - read operation (bit 0)
		WRITE = 1 << 1,     // "w" - write operation (bit 1)
		EXECUTE = 1 << 2    // "x" - execute operation (bit 2)
	}
	
	/**
	 * Permission check result.
	 */
	public enum PermissionResult
	{
		YES,   // Permission granted (r, w, or x)
		NO,    // Permission denied (-)
		ASK    // Unknown - need to ask user (?)
	}
	
	/**
	 * Permission response from user.
	 * Combines allow/deny decision with storage type.
	 */
	public enum PermissionResponse
	{
		DENY_ONCE,      // deny_once - one-time deny, not persisted
		DENY_SESSION,   // deny_session - session deny, cleared on exit
		DENY_ALWAYS,    // deny_always - permanent deny, persisted to file
		ALLOW_ONCE,     // allow_once - one-time allow, not persisted
		ALLOW_SESSION,  // allow_session - session allow, cleared on exit
		ALLOW_ALWAYS    // allow_always - permanent allow, persisted to file
	}
	
	/**
	 * Abstract base class for requesting permission to execute tool operations.
	 * 
	 * Subclasses can provide different approval mechanisms:
	 * - User prompts/dialogs
	 * - Automatic approval based on rules
	 * - Logging-only implementations for testing
	 * 
	 * Includes permission storage system with two layers:
	 * - Global (permanent): Stored in tool.permissions.json (only if config_file is set)
	 * - Session (temporary): Stored in memory for current session
	 */
	public abstract class Provider : Object
	{
		/**
		 * Path to the permissions JSON file (config_file).
		 * If empty, ALWAYS responses are treated as SESSION.
		 */
		public string config_file { get; set; default = ""; }
		
		/**
		 * Base path for relative path normalization.
		 * If set, paths will be normalized relative to this base path.
		 * If empty, no normalization is performed.
		 */
		public string relative_path { get; set; default = ""; }
		
		/**
		 * Session storage for temporary permissions (allow_session/deny_session).
		 * Key: full path, Value: permission string (rwx, r--, ---, etc.)
		 */
		protected static  Gee.HashMap<string, string> session {
			 get; private set; default = new Gee.HashMap<string, string>(); }
		
		/**
		 * Global permissions loaded from tool.permissions.json.
		 * Key: full path, Value: permission string
		 */
		protected static Gee.HashMap<string, string> global { 
			get; private set; default = new Gee.HashMap<string, string>(); }
		
		/**
		 * Constructor.
		 * 
		 * @param directory Directory where permission files are stored (empty string by default)
		 */
		protected Provider(string directory = "")
		{
			if (directory == "") {
				return;
			}
			
			this.config_file = GLib.Path.build_filename(directory, "tool.permissions.json");
			
			var file = GLib.File.new_for_path(this.config_file);
			if (!file.query_exists()) {
				return; // No permissions file yet
			}
			
			try {
				var parser = new Json.Parser();
				parser.load_from_file(this.config_file);
				var obj = parser.get_root().get_object();
				
				foreach (var key in obj.get_members()) {
					Provider.global.set(key, obj.get_string_member(key));
				}
			} catch (GLib.Error e) {
				GLib.warning("Failed to load permissions: %s", e.message);
			}
		}
		
		/**
		 * Requests permission to execute a tool operation.
		 * 
		 * This method checks permission storage layers in order:
		 * 1. Session (temporary)
		 * 2. Global (permanent)
		 * 3. If not found, calls request_user() to ask user
		 * 
		 * @param tool The Tool instance requesting permission
		 * @return true if permission is granted, false otherwise
		 */
		public async bool request(OLLMchat.Tool.Interface tool)
		{
			// Normalize path
			var normalized_path = this.normalize_path(tool.permission_target_path);
			
			GLib.debug("Provider.request: Tool '%s' requesting permission for '%s' (operation: %s)",
				tool.name, normalized_path, tool.permission_operation.to_string());
			
			// Check session permissions
			if (Provider.session.has_key(normalized_path)) {
				var result = this.check(Provider.session.get(normalized_path), tool.permission_operation);
				GLib.debug("Provider.request: Found session permission for '%s': %s", normalized_path, result.to_string());
				if (result == PermissionResult.YES || result == PermissionResult.NO) {
					return result == PermissionResult.YES;
				}
			}
			
			// Check global permissions
			if (Provider.global.has_key(normalized_path)) {
				var result = this.check(Provider.global.get(normalized_path), tool.permission_operation);
				GLib.debug("Provider.request: Found global permission for '%s': %s", normalized_path, result.to_string());
				if (result == PermissionResult.YES || result == PermissionResult.NO) {
					return result == PermissionResult.YES;
				}
			}
			
			// No stored permission found - ask user
			GLib.debug("Provider.request: No stored permission found, asking user: '%s'", tool.permission_question);
			var response = yield this.request_user(tool);
			GLib.debug("Provider.request: User responded with: %s", response.to_string());
			this.handle_response(normalized_path, tool.permission_operation, response);
			
			return (response == PermissionResponse.ALLOW_ONCE || 
			        response == PermissionResponse.ALLOW_SESSION || 
			        response == PermissionResponse.ALLOW_ALWAYS);
		}
		
		/**
		 * Abstract method for requesting permission from user.
		 * Subclasses implement this to show UI dialogs, prompts, etc.
		 * 
		 * @param tool The Tool instance requesting permission
		 * @return PermissionResponse enum indicating user's choice
		 */
		protected abstract async PermissionResponse request_user(OLLMchat.Tool.Interface tool);
		
		/**
		 * Checks if permission is currently granted for a tool operation.
		 * This is a synchronous check that only looks at stored permissions,
		 * it does not ask the user.
		 * 
		 * @param tool The Tool instance to check permissions for
		 * @return true if permission is granted, false if denied or unknown
		 */
		public bool check_permission(OLLMchat.Tool.Interface tool)
		{
			// Normalize path
			var normalized_path = this.normalize_path(tool.permission_target_path);
			
			// Check session permissions
			if (Provider.session.has_key(normalized_path)) {
				var result = this.check(Provider.session.get(normalized_path), tool.permission_operation);
				if (result == PermissionResult.YES || result == PermissionResult.NO) {
					return result == PermissionResult.YES;
				}
			}
			
			// Check global permissions
			if (Provider.global.has_key(normalized_path)) {
				var result = this.check(Provider.global.get(normalized_path), tool.permission_operation);
				if (result == PermissionResult.YES || result == PermissionResult.NO) {
					return result == PermissionResult.YES;
				}
			}
			
			// No stored permission found - return false (not granted)
			return false;
		}
		
		/**
		 * Checks if a permission string allows the requested operation(s).
		 * 
		 * @param perm Permission string (e.g., "rwx", "r--", "---", "???")
		 * @param operation Operation type(s) (can be combined with |, e.g., READ | WRITE)
		 * @return PermissionResult.YES if all operations allowed, PermissionResult.NO if any denied, PermissionResult.ASK if unknown
		 */
		protected PermissionResult check(string perm, Operation operation)
		{
			if (perm == "???") {
				return PermissionResult.ASK; // Unknown - need to ask user
			}
			
			// Check each operation bit
			if ((operation & Operation.READ) != 0) {
				var result = this.check_single(perm, 0);
				if (result == PermissionResult.NO || result == PermissionResult.ASK) {
					return result;
				}
			}
			
			if ((operation & Operation.WRITE) != 0) {
				var result = this.check_single(perm, 1);
				if (result == PermissionResult.NO || result == PermissionResult.ASK) {
					return result;
				}
			}
			
			if ((operation & Operation.EXECUTE) != 0) {
				var result = this.check_single(perm, 2);
				if (result == PermissionResult.NO || result == PermissionResult.ASK) {
					return result;
				}
			}
			
			return PermissionResult.YES;
		}
		
		/**
		 * Checks a single permission character at the given index.
		 */
		private PermissionResult check_single(string perm, int index)
		{
			if (perm.length <= index) {
				return PermissionResult.ASK;
			}
			
			switch (perm[index]) {
				case '-':
					return PermissionResult.NO;
				case 'r':
				case 'w':
				case 'x':
					return PermissionResult.YES;
				case '?':
					return PermissionResult.ASK;
				default:
					return PermissionResult.NO;
			}
		}
		
		/**
		 * Normalizes a path for consistent storage and lookup.
		 * If relative_path is set, converts relative paths to absolute using that base path.
		 * Always resolves symlinks regardless of relative_path setting.
		 * 
		 * @param path The path to normalize
		 * @param depth Current recursion depth (prevents infinite loops from symlink cycles)
		 * @return Normalized path with symlinks resolved
		 */
		protected string normalize_path(string path, int depth = 0)
		{
			// Prevent infinite recursion from symlink cycles
			if (depth > 10) {
				GLib.warning("Symlink resolution depth exceeded for %s, returning current path", path);
				return path;
			}
			
			// Convert to absolute path if relative and relative_path is set
			string normalized = path;
			if (!GLib.Path.is_absolute(path) && this.relative_path != "") {
				normalized = GLib.Path.build_filename(this.relative_path, path);
			}
			
			// Early return if not a symlink
			if (!GLib.FileUtils.test(normalized, GLib.FileTest.IS_SYMLINK)) {
				return normalized;
			}
			
			// Resolve symlinks using GLib.FileUtils methods
			try {
				// Read the symlink target
				string? link_target = GLib.FileUtils.read_link(normalized);
				if (link_target == null) {
					return normalized;
				}
				normalized = link_target;
				// If target is relative, make it absolute
				if (!GLib.Path.is_absolute(link_target)) {
					string dir = GLib.Path.get_dirname(normalized);
					normalized = GLib.Path.build_filename(dir, link_target);
				} 
				
				// Recursively resolve if the target is also a symlink
				return this.normalize_path(normalized, depth + 1);
			} catch (GLib.FileError e) {
				// If read_link fails, return the normalized path
				GLib.debug("Failed to read symlink for %s: %s", normalized, e.message);
				return normalized;
			}
		}
		
		/**
		 * Handles user's permission response and updates storage accordingly.
		 * 
		 * If config_file is empty, ALWAYS responses are treated as SESSION.
		 * When WRITE permission is granted, READ permission is automatically granted as well.
		 * 
		 * @param target_path The normalized target path
		 * @param operation The operation type(s) (can be combined with |, e.g., READ | WRITE)
		 * @param response The user's response enum
		 */
		protected void handle_response(string target_path, Operation operation, PermissionResponse response)
		{
			bool allowed = (response == PermissionResponse.ALLOW_ONCE || 
			                response == PermissionResponse.ALLOW_SESSION || 
			                response == PermissionResponse.ALLOW_ALWAYS);
			
			// If config_file is empty, treat ALWAYS as SESSION
			if ((response == PermissionResponse.DENY_ALWAYS 
				|| response == PermissionResponse.ALLOW_ALWAYS) && this.config_file == "") {
				response = allowed ? PermissionResponse.ALLOW_SESSION : PermissionResponse.DENY_SESSION;
			}
			
			// If WRITE is granted, automatically grant READ as well
			if (allowed && (operation & Operation.WRITE) != 0) {
				operation |= Operation.READ;
			}
			
			var new_perm = this.update_string(
				Provider.global.has_key(target_path) ? Provider.global.get(target_path) : "???",
				operation,
				allowed
			);
			
			switch (response) {
				case PermissionResponse.DENY_ONCE:
				case PermissionResponse.ALLOW_ONCE:
					// One-time permissions - don't store (not used)
					break;
					
				case PermissionResponse.DENY_SESSION:
				case PermissionResponse.ALLOW_SESSION:
					// Store in session
					Provider.session.set(target_path, new_perm);
					break;
					
				case PermissionResponse.DENY_ALWAYS:
				case PermissionResponse.ALLOW_ALWAYS:
					// Store in global and persist to file (only if config_file is set)
					Provider.global.set(target_path, new_perm);
					this.save();
					break;
			}
		}
		static char[] op_chars = {'r', 'w', 'x'};
		/**
		 * Updates a permission string with new operation permission(s).
		 * 
		 * @param current Current permission string (e.g., "rw-", "???")
		 * @param operation Operation type(s) (can be combined with |, e.g., READ | WRITE)
		 * @param allowed Whether the operation(s) are allowed
		 * @return Updated permission string
		 */
		protected string update_string(string current, Operation operation, bool allowed)
		{
			// Ensure we have a 3-character string
			if (current.length != 3) {
				current = "???";
			}
			
			var chars = current.to_utf8();
			
			// Update each operation bit
			if ((operation & Operation.READ) != 0) {
				chars[0] = allowed ? Provider.op_chars[0] : '-';
			}
			
			if ((operation & Operation.WRITE) != 0) {
				chars[1] = allowed ? Provider.op_chars[1] : '-';
			}
			
			if ((operation & Operation.EXECUTE) != 0) {
				chars[2] = allowed ? Provider.op_chars[2] : '-';
			}
			
			return (string)chars;
		}
		
		/**
		 * Loads permissions from config_file.
		 * Only loads if config_file is set.
		 */
		protected void load()
		{
			if (this.config_file == "") {
				return; // No config file configured
			}
			
			var file = GLib.File.new_for_path(this.config_file);
			if (!file.query_exists()) {
				return; // No permissions file yet
			}
			
			try {
				var parser = new Json.Parser();
				parser.load_from_file(this.config_file);
				var obj = parser.get_root().get_object();
				
				foreach (var key in obj.get_members()) {
					Provider.global.set(key, obj.get_string_member(key));
				}
			} catch (GLib.Error e) {
				GLib.warning("Failed to load permissions: %s", e.message);
			}
		}
		
		/**
		 * Saves permissions to config_file.
		 * Only saves if config_file is set.
		 */
		protected void save()
		{
			if (this.config_file == "") {
				return; // No config file configured
			}
			
			// Ensure directory exists
			var dir_path = GLib.Path.get_dirname(this.config_file);
			var dir = GLib.File.new_for_path(dir_path);
			if (!dir.query_exists()) {
				try {
					dir.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					GLib.warning("Failed to create permissions directory: %s", e.message);
					return;
				}
			}
			
			try {
				var generator = new Json.Generator();
				generator.pretty = true;
				generator.indent = 4;
				
				var obj = new Json.Object();
				foreach (var entry in Provider.global.entries) {
					obj.set_string_member(entry.key, entry.value);
				}
				
				var node = new Json.Node(Json.NodeType.OBJECT);
				node.set_object(obj);
				generator.set_root(node);
				generator.to_file(this.config_file);
			} catch (GLib.Error e) {
				GLib.warning("Failed to save permissions: %s", e.message);
			}
		}
	}
}

