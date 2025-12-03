namespace VectorSearch
{
	public class CodeIndexer : Object
	{
		private Database vector_db;
		private CodeImport analyzer;
		private Gee.HashMap<string, CodeElement> element_registry;
		private Gee.ArrayList<CodeFile> analyzed_files;
		
		public CodeIndexer(
		OLLMchat.OLLMchat.Client analyzer_client,
		OLLMchat.OLLMchat.Client vector_db_client
	)
		{
			this.vector_db = new Database(vector_db_client);
			this.analyzer = new CodeImport(analyzer_client);
			this.element_registry = new Gee.HashMap<string, CodeElement>();
			this.analyzed_files = new Gee.ArrayList<CodeFile>();
		}
		
		public async void index_codebase(string[] file_paths, string[] languages) throws Error
		{
			if (file_paths.length != languages.length) {
				throw new Error.FAILED("File paths and languages arrays must have same length");
			}
			
			var documents_to_index = new Gee.ArrayList<string>();
			
			for (int i = 0; i < file_paths.length; i++) {
				print("Analyzing " + file_paths[i] + "...\n");
				
				try {
					var code_file = yield this.analyzer.analyze_file(file_paths[i], languages[i]);
					this.analyzed_files.add(code_file);
					
					foreach (var element in code_file.elements) {
						// Create searchable document for each element
						var search_document = this.create_search_document(element, code_file);
						documents_to_index.add(search_document);
						
						// Register element with unique ID
						var element_id = code_file.file_path + ":" + element.type + ":" + element.name + ":" + element.start_line.to_string();
						this.element_registry.set(element_id, element);
					}
					
					print("  Found " + code_file.elements.size.to_string() + " elements\n");
					
				} catch (Error e) {
					printerr("  Error analyzing " + file_paths[i] + ": " + e.message + "\n");
				}
			}
			
			// Index all documents
			if (documents_to_index.size > 0) {
				yield this.vector_db.add_documents(documents_to_index.to_array());
				print("Indexed " + documents_to_index.size.to_string() + " code elements\n");
			}
		}
		
		private string create_search_document(CodeElement element, CodeFile file)
		{
			var builder = new GLib.StringBuilder();
			
			builder.append(element.type + ": " + element.name + "\n");
			builder.append("File: " + file.file_path + "\n");
			builder.append("Lines: " + element.start_line.to_string() + "-" + element.end_line.to_string() + "\n");
			builder.append("Description: " + element.description + "\n");
			
			if (element.parameters != null && element.parameters.length > 0) {
				builder.append("Parameters: " + string.joinv(", ", element.parameters) + "\n");
			}
			
			if (element.return_type != null && element.return_type != "") {
				builder.append("Returns: " + element.return_type + "\n");
			}
			
			builder.append("Code:\n" + element.code_snippet);
			
			return builder.str;
		}
		
		public void save_index(string filename) throws Error
		{
			this.vector_db.save_index(filename);
			
			// Save analysis metadata
			var metadata_file = filename + ".metadata";
			var file = GLib.File.new_for_path(metadata_file);
			var dos = new GLib.DataOutputStream(file.create(GLib.FileCreateFlags.REPLACE));
			
			// Save analyzed files
			foreach (var code_file in this.analyzed_files) {
				var json = Json.gobject_to_data(code_file, null);
				dos.put_string(json + "\n");
			}
			
			// Save element registry
			var registry_file = filename + ".registry";
			var registry_file_obj = GLib.File.new_for_path(registry_file);
			var registry_dos = new GLib.DataOutputStream(registry_file_obj.create(GLib.FileCreateFlags.REPLACE));
			
			foreach (var entry in this.element_registry.entries) {
				var element_json = Json.gobject_to_data(entry.value, null);
				registry_dos.put_string(entry.key + "|" + element_json + "\n");
			}
		}
		
		public void load_index(string filename) throws Error
		{
			this.vector_db.load_index(filename);
			
			// Load analysis metadata
			var metadata_file = filename + ".metadata";
			var file = GLib.File.new_for_path(metadata_file);
			
			if (file.query_exists()) {
				this.analyzed_files.clear();
				string content;
				try {
					GLib.FileUtils.get_contents(metadata_file, out content);
					var lines = content.split("\n");
					foreach (var line in lines) {
						if (line != "") {
							var code_file = Json.gobject_from_data(typeof(CodeFile), line, -1) as CodeFile;
							if (code_file != null) {
								this.analyzed_files.add(code_file);
							}
						}
					}
				} catch (GLib.FileError e) {
					// If file read fails, analyzed_files list remains empty
				}
			}
			
			// Load element registry
			var registry_file = filename + ".registry";
			var registry_file_obj = GLib.File.new_for_path(registry_file);
			
			if (registry_file_obj.query_exists()) {
				this.element_registry.clear();
				string registry_content;
				try {
					GLib.FileUtils.get_contents(registry_file, out registry_content);
					var lines = registry_content.split("\n");
					foreach (var line in lines) {
						if (line != "") {
							var parts = line.split("|", 2);
							if (parts.length == 2) {
								var element = Json.gobject_from_data(typeof(CodeElement), parts[1], -1) as CodeElement;
								if (element != null) {
									this.element_registry.set(parts[0], element);
								}
							}
						}
					}
				} catch (GLib.FileError e) {
					// If file read fails, element_registry remains empty
				}
			}
		}
		
		public Database get_database()
		{
			return this.vector_db;
		}
	}
}

