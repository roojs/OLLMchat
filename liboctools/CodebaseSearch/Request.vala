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

namespace OLLMtools.CodebaseSearch
{
	/**
	 * Request handler for codebase search operations.
	 * 
	 * Handles codebase search requests from LLM function calls. Validates
	 * parameters, calls {@code vector.search} on {@code ollmfilesd}, and
	 * returns daemon-formatted markdown for LLM consumption.
	 * 
	 * Supports filtering by language and element_type, and validates
	 * element_type against a list of supported types. Results are formatted
	 * with code citations using the standard citation format (on the daemon).
	 */
	public class RequestCodebaseSearch : OLLMchat.Tool.RequestBase
	{
		// Parameter properties (from LLM function call)
		public string query { get; set; default = ""; }
		public string language { get; set; default = ""; }
		public string element_type { get; set; default = ""; }
		public string category { get; set; default = ""; }
		public int max_results { get; set; default = 10; }
		
		/**
		 * Valid element types that can be searched.
		 * Note: "namespace" is not included as namespace declarations are not indexed.
		 */
		private static string[] VALID_ELEMENT_TYPES = {
			"class",
			"struct",
			"interface",
			"enum_type",
			"enum",
			"function",
			"method",
			"constructor",
			"property",
			"field",
			"delegate",
			"signal",
			"constant",
			"file",
			"document",
			"section"
		};
		
		/**
		 * Valid document categories (for documentation elements only).
		 */
		private static string[] VALID_CATEGORIES = {
			"plan",
			"documentation",
			"rule",
			"configuration",
			"data",
			"license",
			"changelog",
			"other"
		};
		
		/**
		 * Get formatted list of valid element types for error messages.
		 * 
		 * @return Formatted string listing all valid element types
		 */
		private static string get_valid_element_types_list()
		{
			var list = new StringBuilder();
			for (var i = 0; i < VALID_ELEMENT_TYPES.length; i++) {
				if (i > 0) {
					list.append(", ");
				}
				list.append("\"" + VALID_ELEMENT_TYPES[i] + "\"");
			}
			return list.str;
		}
		
		/**
		 * Validate element type parameter.
		 * 
		 * @param element_type Element type to validate
		 * @throws GLib.IOError.INVALID_ARGUMENT if element type is invalid
		 */
		private static void validate_element_type(string element_type) throws GLib.IOError
		{
			if (element_type == null || element_type.strip() == "") {
				return; // Empty is valid (no filter)
			}
			
			var normalized = element_type.strip().down();
			foreach (var valid_type in VALID_ELEMENT_TYPES) {
				if (normalized == valid_type) {
					return; // Found valid type
				}
			}
			
			// Invalid type - throw error with list of supported types
			var valid_types_list = get_valid_element_types_list();
			throw new GLib.IOError.INVALID_ARGUMENT(
				"You requested element type \"%s\", however we only support these types: %s".printf(
					element_type,
					valid_types_list
				)
			);
		}
		
		/**
		 * Validate category parameter (documentation filter).
		 */
		private static void validate_category(string category) throws GLib.IOError
		{
			if (category == null || category.strip() == "") {
				return;
			}
			var normalized = category.strip().down();
			foreach (var valid in VALID_CATEGORIES) {
				if (normalized == valid) {
					return;
				}
			}
			throw new GLib.IOError.INVALID_ARGUMENT(
				"You requested category \"%s\"; valid values: plan, documentation, rule, configuration, data, license, changelog, other".printf(category)
			);
		}
		
		/**
		 * Default constructor.
		 */
		public RequestCodebaseSearch()
		{
		}
		
		/**
		 * Project manager from tool.
		 */
		private OLLMfiles.ProjectManager project_manager {
			get { return (this.tool as CodebaseSearchTool).project_manager; }
		}
		
		protected override bool build_perm_question()
		{
			// Codebase search is read-only and doesn't require permission prompts
			return false;
		}

		public override string to_summary ()
		{
			var request_message = "Query: " + this.query;
			if (this.language != "") {
				request_message += "\nLanguage: " + this.language;
			}
			if (this.element_type != "") {
				request_message += "\nElement Type: " + this.element_type;
			}
			if (this.category != "") {
				request_message += "\nCategory: " + this.category;
			}
			request_message += "\nMax Results: " + this.max_results.to_string ();
			return request_message;
		}
		
		protected override async string execute_request() throws Error
		{
			// Validate required parameter
			if (this.query == null || this.query.strip() == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("Query parameter is required");
			}
			
			// Validate element type and category if provided
			validate_element_type(this.element_type);
			validate_category(this.category);
			
			// Debug: Log input parameters
			GLib.debug("codebase_search input: query='%s', language='%s', element_type='%s', category='%s', max_results=%d",
				this.query,
				this.language != "" ? this.language : "none",
				this.element_type != "" ? this.element_type : "none",
				this.category != "" ? this.category : "none",
				this.max_results
			);
			
			// Send search query to UI (same format as commands)
			var request_message = this.to_summary ();
			this.agent.add_message(new OLLMchat.Message("ui", 
				OLLMchat.Message.fenced("text.oc-frame-info.collapsed Code search: %s".printf(this.query), request_message)));
			
			// Step 1: Get active project from ProjectManager
			var active_project = this.project_manager.active_project;
			if (active_project == null) {
				throw new GLib.IOError.FAILED("No active project. Please open a project first.");
			}
			
			// Step 2: vector.search on ollmfilesd (filter, FAISS, snippets — daemon-side)
			var response = yield this.project_manager.rpc.call(new OLLMrpc.Request() {
				method = "vector.search",
				param = new OLLMfilesd.VectorParams() {
					path = active_project.path,
					query = this.query,
					language = this.language,
					element_type = this.element_type,
					category = this.category,
					max_results = this.max_results,
					format = "tool"
				}
			});
			if (response.error != null) {
				throw new GLib.IOError.FAILED(response.error.message);
			}
			
			// Step 3: Return daemon-formatted markdown for LLM consumption
			var formatted = response.msg;
			
			// Debug: Log output
			GLib.debug("codebase_search output: query='%s'", this.query);
			
			// Send output as second message via message_created (same as commands)
			var result_title = "Results for %s".printf(this.query);
			this.agent.add_message(new OLLMchat.Message("ui", 
				OLLMchat.Message.fenced("markdown.oc-frame-success.collapsed " + result_title, formatted)));
			
			return formatted;
		}
	}
}
