namespace VectorSearch
{
	public class CodeImport : Object
	{
		private OLLMchat.OLLMchat.Client ollama;
		
		public CodeImport(OLLMchat.OLLMchat.Client ollama)
		{
			this.ollama = ollama;
		}
		
		public async CodeFile analyze_file(string file_path, string language) throws Error
		{
			string content;
			try {
				GLib.FileUtils.get_contents(file_path, out content);
			} catch (GLib.FileError e) {
				throw new Error.FAILED("File not found: " + file_path);
			}
			
			return yield this.analyze_code_content(content, file_path, language);
		}
		
		public async CodeFile analyze_code_content(string code, string file_path, string language) throws Error
		{
			var analysis_prompt = """Analyze the following %s code and provide a structured summary. For each class, function, method, and significant code block, include:

1. Class/Method/Function name
2. Starting line number
3. Ending line number
4. Purpose and functionality description
5. Key parameters and return values
6. Dependencies and relationships

Format the response as JSON:
{
    "file_path": "string",
    "language": "string",
    "summary": "overall file summary",
    "elements": [
        {
            "type": "class|function|method|struct|interface",
            "name": "element_name",
            "start_line": number,
            "end_line": number,
            "description": "detailed description",
            "parameters": ["param1", "param2"],
            "return_type": "return_type",
            "dependencies": ["dep1", "dep2"]
        }
    ]
}

Code:
%s""".printf(language, code);
			
			this.ollama.format = "json";
			var response = yield this.ollama.generate(analysis_prompt);
			
			if (response.content == "") {
				throw new Error.FAILED("Empty response from Ollama");
			}
			
			// Extract JSON from response - might be wrapped in {"response": "..."} or direct JSON
			string json_content = response.content;
			var parser = new Json.Parser();
			try {
				parser.load_from_data(json_content, -1);
				var root_node = parser.get_root();
				if (root_node != null && root_node.get_node_type() == Json.NodeType.OBJECT) {
					var response_obj = root_node.get_object();
					if (response_obj.has_member("response")) {
						json_content = response_obj.get_string_member("response");
					}
				}
			} catch (Error e) {
				// If parsing fails, assume json_content is already the JSON we need
			}
			
			// Deserialize the JSON response directly into CodeFile
			var code_file = Json.gobject_from_data(typeof(CodeFile), json_content, -1) as CodeFile;
			if (code_file == null) {
				throw new Error.FAILED("Failed to deserialize code analysis response");
			}
			
			// Set additional fields
			code_file.file_path = file_path;
			code_file.language = language;
			code_file.raw_code = code;
			
			// Extract code snippets for each element
			foreach (var element in code_file.elements) {
				element.code_snippet = this.extract_code_snippet(code, element.start_line, element.end_line);
			}
			
			return code_file;
		}
		
		private string extract_code_snippet(string code, int start_line, int end_line)
		{
			var lines = code.split("\n");
			var snippet = new GLib.StringBuilder();
			
			for (int i = start_line - 1; i < end_line && i < lines.length; i++) {
				snippet.append(lines[i]);
				snippet.append("\n");
			}
			
			return snippet.str;
		}
	}
}

