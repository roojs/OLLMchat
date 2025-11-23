namespace OLLMchat.Tools
{
	/**
	 * Represents a single edit operation with range and replacement.
	 */
	public class Edit : Object, Json.Serializable
	{
		public int start { get; set; default = -1; }
		public int end { get; set; default = -1; }
		public string replacement { get; set; default = ""; }
		public Gee.ArrayList<string> old_lines { get; set; default = new Gee.ArrayList<string>(); }
		
		public unowned ParamSpec? find_property(string name) { 
			return this.get_class().find_property(name); 
		}
		public new void Json.Serializable.set_property(ParamSpec pspec, Value value) {
			 base.set_property(pspec.get_name(), value); 
		}
		public new Value Json.Serializable.get_property(ParamSpec pspec) {
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}
		
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name == "range") {
				var array = property_node.get_array();
				this.start = (int)array.get_int_element(0);
				this.end = (int)array.get_int_element(1);
				value = Value(pspec.value_type);
				return true;
			}
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
		
		public string toDiff()
		{
			string diff = "";
			foreach (var old_line in this.old_lines) {
				diff += "- " + old_line + "\n";
			}
			foreach (var new_line in this.replacement.split("\n")) {
				diff += "+ " + new_line + "\n";
			}
			return diff;
		}
		
		/**
		 * Writes the replacement text to the output stream and skips old lines in the input stream.
		 * 
		 * @param output_stream The output stream to write replacement to
		 * @param input_stream The input stream to skip old lines from
		 * @param current_line Reference to current line number (will be updated)
		 * @throws Error if I/O operations fail
		 */
		public void apply_to_streams(GLib.DataOutputStream output_stream, GLib.DataInputStream input_stream, ref int current_line) throws Error
		{
			// Write replacement lines
			foreach (var new_line in this.replacement.split("\n")) {
				output_stream.put_string(new_line);
				output_stream.put_byte('\n');
			}
			
			// Skip old lines in input stream until end of edit range (exclusive)
			string? line;
			size_t length;
			while (current_line < this.end - 1) {
				line = input_stream.read_line(out length, null);
				if (line == null) {
					break;
				}
				current_line++;
			}
		}
	}
	
	/**
	 * Tool for editing files by applying a list of edits (ranges with replacement text).
	 * 
	 * This tool applies edits to a file using a streaming approach to minimize memory usage.
	 * Supports two-step permission flow: first READ permission to generate diff, then WRITE permission with diff display.
	 */
	public class EditFileTool : Ollama.Tool
	{
		// Parameter properties
		public string file_path { get; set; default = ""; }
		public Gee.ArrayList<Edit> edits { get; set; default = new Gee.ArrayList<Edit>(); }
		
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
@param edits {array} [required] List of edits to apply. Each edit has 'range' [start, end] and 'replacement' text.""";
		} }
		
		/**
		 * Signal emitted before applying edits to a file.
		 * Handlers can return false to block the change.
		 */
		public signal bool before_change(string file_path, Gee.ArrayList<Edit> edits);
		
		/**
		 * Signal emitted after successfully applying edits to a file.
		 */
		public signal void after_change(string file_path, Gee.ArrayList<Edit> edits);
		
		public EditFileTool(Ollama.Client client)
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
					var edit = Json.gobject_deserialize(typeof(Edit), edit_node) as Edit;
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
			string question = @"Edit file '$(normalized_path)' with $(this.edits.size) edit$(this.edits.size == 1 ? "" : "s")?";
			
			// Set permission properties for WRITE operation
			this.permission_target_path = normalized_path;
			this.permission_operation = ChatPermission.Operation.WRITE;
			this.permission_question = question;
			
			return true;
		}
		
		/**
		 * Override execute() to handle two-step permission flow:
		 * 1. Request READ permission to generate diff
		 * 2. Request WRITE permission with diff display
		 */
		public override async string execute(Json.Object parameters)
		{
			// Prepare parameters
			if (!this.prepare(parameters)) {
				return "ERROR: Invalid parameters";
			}
			
			var normalized_path = this.normalize_file_path(this.file_path);
			
			// Step 1: Request READ permission (request() checks storage first)
			var read_tool = new ReadFileTool(this.client) {
				file_path = this.file_path,
				read_entire_file = true,
				permission_target_path = normalized_path,
				permission_operation = ChatPermission.Operation.READ,
				permission_question = @"Read file '$(normalized_path)' to preview changes?"
			};
			
			if (!(yield this.client.permission_provider.request(read_tool))) {
				return "ERROR: Permission denied: Read access required to preview changes";
			}
			
			// Read file and generate diff
			string? diff_content = null;
			try {
				diff_content = yield this.generate_diff(normalized_path);
			} catch (Error e) {
				return "ERROR: Failed to read file for diff: " + e.message;
			}
			
			// Step 2: Request WRITE permission with diff
			// TODO: Pass diff_content to permission provider for display
			// For now, the permission widget will need to be updated separately
			this.permission_question = @"Edit file '$(normalized_path)' with $(this.edits.size) edit$(this.edits.size == 1 ? "" : "s")?";
			this.permission_target_path = normalized_path;
			this.permission_operation = ChatPermission.Operation.WRITE;
			
			if (!(yield this.client.permission_provider.request(this))) {
				return "ERROR: Permission denied: " + this.permission_question;
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
		 * Generates a unified diff showing the changes that will be made.
		 */
		private async string generate_diff(string file_path) throws Error
		{
			var file = GLib.File.new_for_path(file_path);
			if (!file.query_exists()) {
				throw new GLib.IOError.FAILED(@"File not found: $file_path");
			}
			
			// Create HashMap of start line -> Edit
			var edits_by_start = new Gee.HashMap<int, Edit>();
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
				Edit? current_edit = null;
				
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
			string diff = @"--- $file_path (original)\n" +
				 @"+++ $file_path (modified)\n";
			
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
			
			if (!GLib.FileUtils.test(normalized_path, GLib.FileTest.IS_REGULAR)) {
				throw new GLib.IOError.FAILED(@"File not found or is not a regular file: $normalized_path");
			}
			
			// Validate edits
			this.validate_edits();
			
			// Emit before_change signal
			if (!this.before_change(normalized_path, this.edits)) {
				throw new GLib.IOError.PERMISSION_DENIED("File edit blocked by signal handler");
			}
			
			// Apply edits using streaming approach
			this.apply_edits_streaming(normalized_path);
			
			// Send status message
			this.client.tool_message(@"Edited file $normalized_path ($(this.edits.size) edit$(this.edits.size == 1 ? "" : "s"))");
			
			return @"Successfully edited file: $normalized_path";
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
				
				// Validate sorted order
				if (i > 0) {
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
		}
		
		/**
		 * Applies edits to a file using a streaming approach.
		 */
		private void apply_edits_streaming(string file_path) throws Error
		{
			// Create HashMap of start line -> Edit
			var edits_by_start = new Gee.HashMap<int, Edit>();
			foreach (var edit in this.edits) {
				edits_by_start.set(edit.start, edit);
			}
			
			// Create temporary file for output in system temp directory
			var file_basename = GLib.Path.get_basename(file_path);
			var timestamp = GLib.get_real_time().to_string();
			var temp_file = GLib.File.new_for_path(GLib.Path.build_filename(
				GLib.Environment.get_tmp_dir(),
				@"ollmchat-edit-$(file_basename)-$(timestamp).tmp"
			));
			var temp_output = new GLib.DataOutputStream(
				temp_file.create(GLib.FileCreateFlags.NONE, null)
			);
			
			// Open input file
			var input_file = GLib.File.new_for_path(file_path);
			var input_data = new GLib.DataInputStream(input_file.read(null));
			
			try {
				int current_line = 0;
				string? line;
				size_t length;
				Edit? current_edit = null;
				
				while ((line = input_data.read_line(out length, null)) != null) {
					current_line++;
					
					// Check if this is the start of an edit
					if (edits_by_start.has_key(current_line)) {
						current_edit = edits_by_start.get(current_line);
					}
					
					// If we're at the start of an edit, let Edit handle it
					if (current_edit != null && current_line == current_edit.start) {
						current_edit.apply_to_streams(temp_output, input_data, ref current_line);
						current_edit = null;
						continue;
					}
					
					// If we're in an edit range (being replaced), skip it
					if (current_edit != null && current_line >= current_edit.start && current_line < current_edit.end) {
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
					if (edit.start == edit.end && edit.start > current_line) {
						// For insertions, we don't need to skip input lines (already at end)
						foreach (var new_line in edit.replacement.split("\n")) {
							temp_output.put_string(new_line);
							temp_output.put_byte('\n');
						}
					}
				}
				
			} finally {
				try {
					input_data.close(null);
					temp_output.close(null);
				} catch (GLib.Error e) {
					// Ignore close errors
				}
			}
			
			// Replace original file with temporary file
			var original_file = GLib.File.new_for_path(file_path);
			try {
				original_file.delete(null);
			} catch (GLib.Error e) {
				// Ignore if file doesn't exist
			}
			temp_file.move(original_file, GLib.FileCopyFlags.OVERWRITE, null, null);
		}
	}
}


