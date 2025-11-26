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

namespace OLLMchat.Tools
{
	/**
	 * Tool for editing files by applying a list of edits (ranges with replacement text).
	 * 
	 * This tool applies edits to a file using a streaming approach to minimize memory usage.
	 * Supports two-step permission flow: first READ permission to generate diff, then WRITE permission with diff display.
	 */
	public class EditFile : Ollama.Tool
	{
		// Parameter properties
		public string file_path { get; set; default = ""; }
		public Gee.ArrayList<EditFileChange> edits { get; set; default = new Gee.ArrayList<EditFileChange>(); }
		
		public override string name { get { return "edit_file"; } }
		
		public override string description { get {
			return """
Apply a diff to a file.

The diff should be a list of edits, where each edit is an object with the following properties:
- 'range': The range of lines to edit, specified as [start, end].
- 'replacement': The replacement text.

The 'range' is inclusive of the start line and exclusive of the end line. Line numbers are 1-based.

If the 'range' is [n, n], the edit is an insertion before line n.
If the 'range' is [n, n+1], the edit is a replacement of line n.
If the 'range' is [n, m] where m > n+1, the edit is a replacement of lines n through m-1.

Edits should be non-overlapping and sorted in ascending order by start line.

You should always read the file before editing it to ensure you have the latest version. If you have not read the file before editing it, you may be editing an outdated version.

When applying a diff, ensure that the diff is correct and will not cause syntax errors or other issues. If you are unsure, you can ask the user for confirmation before applying the diff.""";
		} }
		
		public override string parameter_description { get {
			return """
@param file_path {string} [required] The path to the file to edit.
@param edits {array<edittype>} [required] List of edits to apply.
@type edittype {object} Detail of a specific edit operation.
@property edittype.range {array<integer>} Range of lines to edit, specified as [start, end]. The range is inclusive of the start line and exclusive of the end line. Line numbers are 1-based.
@property edittype.replacement {string} The replacement text.""";
		} }
		
		/**
		 * Signal emitted before applying edits to a file.
		 * Notification-only signal - use permission system to block operations.
		 */
		public signal void before_change(string file_path, Gee.ArrayList<EditFileChange> edits);
		
		/**
		 * Signal emitted after successfully applying edits to a file.
		 */
		public signal void after_change(string file_path, Gee.ArrayList<EditFileChange> edits);
		
		public EditFile(Ollama.Client client)
		{
			base(client);
		}
		
		protected override void readParams(Json.Object parameters)
		{
			// Read simple parameters first
			base.readParams(parameters);
			
			// Deserialize edits array
			if (parameters.has_member("edits")) {
				var edits_node = parameters.get_member("edits");
				var edits_array = edits_node.get_array();
				this.edits.clear();
				
				foreach (var edit_node in edits_array.get_elements()) {
					var edit = Json.gobject_deserialize(typeof(EditFileChange), edit_node) as EditFileChange;
					if (edit != null) {
						this.edits.add(edit);
					}
				}
			}
		}
		
		protected override bool prepare(Json.Object parameters)
		{
			// Read parameters (including edits array)
			this.readParams(parameters);
			
			if (this.file_path == "" || this.edits.size == 0) {
				return false;
			}
			
			// Build permission question for WRITE (will be used in second step)
			var normalized_path = this.normalize_file_path(this.file_path);
			var edit_count_text = this.edits.size == 1 ? "1 edit" : this.edits.size.to_string() + " edits";
			string question = "Write to file '" + normalized_path + "' (" + edit_count_text + ")?";
			
			// Set permission properties for WRITE operation
			this.permission_target_path = normalized_path;
			this.permission_operation = ChatPermission.Operation.WRITE;
			this.permission_question = question;
			
			return true;
		}
		
		/**
		 * Override execute() to handle permission flow:
		 * Request WRITE permission (which automatically includes READ) to generate diff and write file.
		 */
		public override async string execute(Json.Object parameters)
		{
			// Prepare parameters
			if (!this.prepare(parameters)) {
				return "ERROR: Invalid parameters";
			}
			
			var normalized_path = this.normalize_file_path(this.file_path);
			
			// Request WRITE permission (which includes READ automatically)
			// This allows us to read the file for diff generation and write the changes
			var edit_count_text = this.edits.size == 1 ? "1 edit" : this.edits.size.to_string() + " edits";
			this.permission_question = "Write to file '" + normalized_path + "' (" + edit_count_text + ")?";
			this.permission_target_path = normalized_path;
			this.permission_operation = ChatPermission.Operation.WRITE;
			
			if (!(yield this.client.permission_provider.request(this))) {
				return "ERROR: Permission denied: " + this.permission_question;
			}
			
			// Generate diff or new file contents (we now have READ permission via WRITE)
			// If file doesn't exist, generate new file contents instead of diff
			string? preview_content = null;
			var file_exists = GLib.FileUtils.test(normalized_path, GLib.FileTest.IS_REGULAR);
			if (file_exists) {
				try {
					preview_content = yield this.generate_diff(normalized_path);
				} catch (Error e) {
					return "ERROR: Failed to read file for diff: " + e.message;
				}
			} else {
				// File doesn't exist - generate new file contents
				preview_content = yield this.generate_new_file_contents();
			}
			
			// Execute the tool
			try {
				var result = this.execute_tool(parameters);
				// Emit after_change signal
				this.after_change(normalized_path, this.edits);
				return result;
			} catch (Error e) {
				return "ERROR: " + e.message;
			}
		}
		
		/**
		 * Generates new file contents for a file that doesn't exist yet.
		 * Combines all edit replacements in order.
		 */
		private async string generate_new_file_contents()
		{
			string content = "";
			foreach (var edit in this.edits) {
				if (content != "" && !content.has_suffix("\n")) {
					content += "\n";
				}
				content += edit.replacement;
			}
			return content;
		}
		
		/**
		 * Generates a unified diff showing the changes that will be made.
		 */
		private async string generate_diff(string file_path) throws Error
		{
			var file = GLib.File.new_for_path(file_path);
			if (!file.query_exists()) {
				throw new GLib.IOError.FAILED("File not found: " + file_path);
			}
			
			// Create HashMap of start line -> Edit
			var edits_by_start = new Gee.HashMap<int, EditFileChange>();
			foreach (var edit in this.edits) {
				edits_by_start.set(edit.start, edit);
			}
			
			// Read file line by line and collect old_lines
			var file_stream = file.read(null);
			var data_stream = new GLib.DataInputStream(file_stream);
			
			try {
				int current_line = 0;
				string? line;
				size_t length;
				EditFileChange? current_edit = null;
				
				while ((line = data_stream.read_line(out length, null)) != null) {
					current_line++;
					
					// Check if this is the start of an edit
					if (edits_by_start.has_key(current_line)) {
						current_edit = edits_by_start.get(current_line);
					}
					
					// If we're in an edit range, collect the line
					if (current_edit != null && current_line >= current_edit.start && current_line < current_edit.end) {
						current_edit.old_lines.add(line);
					}
					
					// If we've passed the end of the current edit, clear it
					if (current_edit != null && current_line >= current_edit.end) {
						current_edit = null;
					}
				}
				
				// Handle insertions at end of file (range [n, n] where n > file length)
				// No special handling needed - toDiff() will handle it
			} finally {
				try {
					data_stream.close(null);
				} catch (GLib.Error e) {
					// Ignore close errors
				}
			}
			
			// Generate diff header
			string diff = "--- " + file_path + " (original)\n" +
				 "+++ " + file_path + " (modified)\n";
			
			// Call toDiff on all edits
			foreach (var edit in this.edits) {
				diff += edit.toDiff();
			}
			
			return diff;
		}
		
		protected override string execute_tool(Json.Object parameters) throws Error
		{
			// Re-parse parameters
			this.prepare(parameters);
			
			var normalized_path = this.normalize_file_path(this.file_path);
			var file_exists = GLib.FileUtils.test(normalized_path, GLib.FileTest.IS_REGULAR);
			
			// If file doesn't exist, validate that edits can create a new file
			// For new files, edits should typically start at line 1
			if (!file_exists) {
				// Validate that edits are appropriate for a new file
				// All edits should be insertions (start == end) or start at line 1
				foreach (var edit in this.edits) {
					if (edit.start != edit.end && edit.start != 1) {
						throw new GLib.IOError.INVALID_ARGUMENT("Cannot create new file: edit starts at line " + edit.start.to_string() + " but file doesn't exist");
					}
				}
			} else {
				// File exists - validate edits normally
				this.validate_edits();
			}
			
			// Emit before_change signal (notification only - blocking handled by permission system)
			this.before_change(normalized_path, this.edits);
			
			// Check if permission status has changed (e.g., revoked by signal handler)
			if (!this.client.permission_provider.check_permission(this)) {
				throw new GLib.IOError.PERMISSION_DENIED("Permission denied or revoked");
			}
			
			// Log and notify that we're starting to write
			GLib.debug("EditFile.execute_tool: Starting to write file %s (%d edit%s)", 
				normalized_path, this.edits.size, this.edits.size == 1 ? "" : "s");
			this.client.tool_message("Writing to file " + normalized_path + "...");
			
			// Apply edits using streaming approach
			this.apply_edits(normalized_path);
			
			// Log and send status message after successful write
			GLib.debug("EditFile.execute_tool: Successfully wrote file %s (%d edit%s)", 
				normalized_path, this.edits.size, this.edits.size == 1 ? "" : "s");
			this.client.tool_message("Wrote file " + normalized_path);
			
			return "Successfully edited file: " + normalized_path;
		}
		
		/**
		 * Validates that all edits are valid, sorted, and non-overlapping.
		 */
		private void validate_edits() throws Error
		{
			// Validate each edit
			for (int i = 0; i < this.edits.size; i++) {
				var edit = this.edits[i];
				
				// Validate range
				if (edit.start < 1) {
					throw new GLib.IOError.INVALID_ARGUMENT(@"Edit $(i+1): start must be >= 1");
				}
				
				if (edit.end <= edit.start) {
					throw new GLib.IOError.INVALID_ARGUMENT(@"Edit $(i+1): end must be > start");
				}
				
				// Validate sorted order and non-overlapping (skip for first edit)
				if (i < 1) {
					continue;
				}
				
				var prev_edit = this.edits[i - 1];
				if (edit.start < prev_edit.start) {
					throw new GLib.IOError.INVALID_ARGUMENT(@"Edit $(i+1): edits must be sorted in ascending order by start");
				}
				
				// Validate non-overlapping
				if (prev_edit.end > edit.start) {
					throw new GLib.IOError.INVALID_ARGUMENT(@"Edit $(i+1): edits must be non-overlapping (edit $i ends at $(prev_edit.end), edit $(i+1) starts at $(edit.start))");
				}
			}
		}
		
		/**
		 * Applies edits to a file using a streaming approach.
		 * Handles both existing files and new file creation.
		 */
		private void apply_edits(string file_path) throws Error
		{
			var file_exists = GLib.FileUtils.test(file_path, GLib.FileTest.IS_REGULAR);
			
			if (!file_exists) {
				GLib.debug("EditFile.apply_edits: Creating new file %s", file_path);
				this.create_new_file(file_path);
				GLib.debug("EditFile.apply_edits: Successfully created new file %s", file_path);
				return;
			}
			
			GLib.debug("EditFile.apply_edits: Starting to apply edits to %s", file_path);
			
			// Create HashMap of start line -> Edit
			var edits_by_start = new Gee.HashMap<int, EditFileChange>();
			foreach (var edit in this.edits) {
				edits_by_start.set(edit.start, edit);
			}
			
			// Create temporary file for output in system temp directory
			var file_basename = GLib.Path.get_basename(file_path);
			var timestamp = GLib.get_real_time().to_string();
			var temp_file = GLib.File.new_for_path(GLib.Path.build_filename(
				GLib.Environment.get_tmp_dir(),
				"ollmchat-edit-" + file_basename + "-" + timestamp + ".tmp"
			));
			GLib.debug("EditFile.apply_edits: Created temporary file %s", temp_file.get_path());
			
			var temp_output = new GLib.DataOutputStream(
				temp_file.create(GLib.FileCreateFlags.NONE, null)
			);
			
			// Open input file
			var input_file = GLib.File.new_for_path(file_path);
			var input_data = new GLib.DataInputStream(input_file.read(null));
			
			GLib.debug("EditFile.apply_edits: Processing edits...");
			this.process_edits(input_data, temp_output, edits_by_start);
			
			input_data.close(null);
			temp_output.close(null);
			
			GLib.debug("EditFile.apply_edits: Replacing original file with temporary file");
			// Replace original file with temporary file
			var original_file = GLib.File.new_for_path(file_path);
			try {
				original_file.delete(null);
			} catch (GLib.Error e) {
				// Ignore if file doesn't exist
			}
			temp_file.move(original_file, GLib.FileCopyFlags.OVERWRITE, null, null);
			GLib.debug("EditFile.apply_edits: Successfully replaced file %s", file_path);
		}
		
		/**
		 * Creates a new file with the contents from edits.
		 */
		private void create_new_file(string file_path) throws Error
		{
			// Ensure parent directory exists
			var parent_dir = GLib.Path.get_dirname(file_path);
			var dir = GLib.File.new_for_path(parent_dir);
			if (!dir.query_exists()) {
				try {
					dir.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					throw new GLib.IOError.FAILED("Failed to create parent directory: " + e.message);
				}
			}
			
			// Create new file and write all edit replacements
			var output_file = GLib.File.new_for_path(file_path);
			var output_stream = new GLib.DataOutputStream(
				output_file.create(GLib.FileCreateFlags.NONE, null)
			);
			
			try {
				foreach (var edit in this.edits) {
					foreach (var new_line in edit.replacement.split("\n")) {
						output_stream.put_string(new_line);
						output_stream.put_byte('\n');
					}
				}
			} finally {
				try {
					output_stream.close(null);
				} catch (GLib.Error e) {
					// Ignore close errors
				}
			}
		}
		
		/**
		 * Processes the file line by line, applying edits.
		 */
		private void process_edits(
			GLib.DataInputStream input_data,
			GLib.DataOutputStream temp_output,
			Gee.HashMap<int, EditFileChange> edits_by_start) throws Error
		{
			int current_line = 0;
			string? line;
			size_t length;
			EditFileChange? current_edit = null;
			
			while ((line = input_data.read_line(out length, null)) != null) {
				current_line++;
				
				// Check if this is the start of an edit
				if (edits_by_start.has_key(current_line)) {
					current_edit = edits_by_start.get(current_line);
				}
				
				// If we're at the start of an edit, let Edit handle it
				if (current_edit != null && current_line == current_edit.start) {
					current_line = current_edit.apply_changes(
						temp_output, input_data, current_line);
					current_edit = null;
					continue;
				}
				
				// If we're in an edit range (being replaced), skip it
				if (current_edit != null &&
					 current_line >= current_edit.start &&
					  current_line < current_edit.end) {
					continue;
				}
				
				// If we've passed the end of the current edit, clear it
				if (current_edit != null && current_line >= current_edit.end) {
					current_edit = null;
				}
				
				// Write line as-is (not part of any edit)
				temp_output.put_string(line);
				temp_output.put_byte('\n');
			}
			
			// Handle insertions at end of file (range [n, n] where n > file length)
			foreach (var edit in this.edits) {
				edit.write_changes(temp_output, current_line);
			}
		}
	}
}


