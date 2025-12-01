namespace VectorSearch
{
	public class CodeSearch : Object
	{
		private Database vector_db;
		
		public CodeSearch(Database vector_db)
		{
			this.vector_db = vector_db;
		}
		
		public async CodeSearchResult[] search_code(string query, int max_results = 10) throws Error
		{
			var vector_results = yield this.vector_db.search(query, max_results);
			var search_results = new Gee.ArrayList<CodeSearchResult>();
			
			foreach (var vector_result in vector_results) {
				// Parse the document to extract element information
				var element_info = this.parse_element_from_document(vector_result.document_text);
				
				var search_result = new CodeSearchResult();
				search_result.element = element_info;
				search_result.similarity_score = vector_result.search_result.similarity_score;
				search_result.rank = vector_result.search_result.rank;
				search_result.relevant_snippet = this.extract_relevant_snippet(
					vector_result.document_text, query
				);
				
				search_results.add(search_result);
			}
			
			return search_results.to_array();
		}
		
		public async CodeSearchResult[] search_by_functionality(string description) throws Error
		{
			var query = "Find code that: " + description;
			return yield this.search_code(query);
		}
		
		public async CodeSearchResult[] search_by_pattern(string pattern_type) throws Error
		{
			var queries = new Gee.HashMap<string, string>();
			queries.set("factory", "factory pattern creation instantiation design");
			queries.set("singleton", "singleton pattern unique instance global");
			queries.set("observer", "observer pattern subscription event listener");
			queries.set("decorator", "decorator pattern wrapper enhancement");
			queries.set("adapter", "adapter pattern interface conversion wrapper");
			
			if (queries.has_key(pattern_type)) {
				return yield this.search_code(queries.get(pattern_type));
			}
			
			return yield this.search_code(pattern_type);
		}
		
		private CodeElement parse_element_from_document(string document)
		{
			var lines = document.split("\n");
			var element = new CodeElement();
			var code_snippet_lines = new Gee.ArrayList<string>();
			bool in_code_section = false;
			
			foreach (var line in lines) {
				if (line.has_prefix("File: ")) {
					// File path is in the document but not stored in CodeElement
					// (CodeElement doesn't have a file_path property)
				} else if (line.has_prefix("Lines: ")) {
					// Extract line numbers
					var line_range = line.substring(7).split("-");
					if (line_range.length == 2) {
						element.start_line = int.parse(line_range[0]);
						element.end_line = int.parse(line_range[1]);
					}
				} else if (line.has_prefix("Description: ")) {
					element.description = line.substring(13);
				} else if (line.has_prefix("Parameters: ")) {
					var params_str = line.substring(12);
					if (params_str != "") {
						element.parameters = params_str.split(", ");
					}
				} else if (line.has_prefix("Returns: ")) {
					element.return_type = line.substring(9);
				} else if (line == "Code:") {
					in_code_section = true;
				} else if (in_code_section) {
					code_snippet_lines.add(line);
				} else if (line.contains(": ")) {
					// First line is usually "type: name"
					var parts = line.split(": ", 2);
					if (parts.length == 2) {
						element.type = parts[0];
						element.name = parts[1];
					}
				}
			}
			
			if (code_snippet_lines.size > 0) {
				element.code_snippet = string.joinv("\n", code_snippet_lines.to_array());
			}
			
			return element;
		}
		
		private string extract_relevant_snippet(string document, string query)
		{
			var lines = document.split("\n");
			var relevant_lines = new Gee.ArrayList<string>();
			
			var query_terms = query.down().split(" ");
			
			foreach (var line in lines) {
				var line_lower = line.down();
				foreach (var term in query_terms) {
					if (term.length > 3 && line_lower.contains(term)) {
						relevant_lines.add(line);
						break;
					}
				}
				
				if (relevant_lines.size >= 3) {
					break;
				}
			}
			
			return string.joinv("\n", relevant_lines.to_array());
		}
		
	}
}
