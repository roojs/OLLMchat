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

namespace OLLMtools
{
	/**
	 * Result item from Google Custom Search API.
	 */
	public class ResultItem : Object, Json.Serializable
	{
		public string title { get; set; default = ""; }
		public string snippet { get; set; default = ""; }
		public string link { get; set; default = ""; }

		public ResultItem()
		{
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, GLib.Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new GLib.Value Json.Serializable.get_property(ParamSpec pspec)
		{
			GLib.Value val = GLib.Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		public override Json.Node serialize_property(string property_name, GLib.Value value, ParamSpec pspec)
		{
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out GLib.Value value, ParamSpec pspec, Json.Node property_node)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}

		public string to_markdown()
		{
			return "### [" + this.title + "](" + this.link + ")\n" + this.snippet + "\n";
		}
	}

	/**
	 * Search results container from Google Custom Search API.
	 */
	public class Result : Object, Json.Serializable
	{
		public int total_results { get; set; default = 0; }
		public Gee.ArrayList<ResultItem> items { get; set; default = new Gee.ArrayList<ResultItem>(); }

		public Result()
		{
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, GLib.Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new GLib.Value Json.Serializable.get_property(ParamSpec pspec)
		{
			GLib.Value val = GLib.Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		public override Json.Node serialize_property(string property_name, GLib.Value value, ParamSpec pspec)
		{
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out GLib.Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "items":
				// Handle "items" array deserialization
                    this.items.clear();
                    if (property_node.get_node_type() != Json.NodeType.ARRAY) {
                        value = GLib.Value(typeof(Gee.ArrayList));
                        value.set_object(this.items);
                        return true;
                    }
                    
                    var json_array = property_node.get_array();
                    for (uint i = 0; i < json_array.get_length(); i++) {
                        var element_node = json_array.get_element(i);
                        var item = Json.gobject_deserialize(typeof(ResultItem), element_node) as ResultItem;
                        if (item != null) {
                            this.items.add(item);
                        }
                    }
                    value = GLib.Value(typeof(Gee.ArrayList));
                    value.set_object(this.items);
                    return true;
                
                default:
                    return default_deserialize_property(property_name, out value, pspec, property_node);
            }
        }

		public string to_markdown()
		{
			var result = "**Total results:** " + this.total_results.to_string() + "\n\n";
			foreach (var item in this.items) {
				result += item.to_markdown();
			}
			return result;
		}
	}

	/**
	 * Request handler for performing Google web searches.
	 */
	public class GoogleSearchRequest : OLLMchat.Tool.RequestBase
	{
		// Parameter properties
		public string query { get; set; default = ""; }
		public int start { get; set; default = 1; }
		
		/**
		 * Default constructor.
		 */
		public GoogleSearchRequest()
		{
		}
		
		protected override bool build_perm_question()
		{
			// Validate required parameter
			if (this.query == "") {
				return false;
			}
			
			// Set permission properties
			this.permission_target_path = "https://www.googleapis.com/";
			this.permission_operation = OLLMchat.ChatPermission.Operation.READ;
			this.permission_question = "Search Google for: " + this.query + "?";
			
			return true;
		}
		
		protected override async string execute_request() throws Error
		{
			// Validate query
			if (this.query == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("Query parameter is required");
			}
			
			// Validate start parameter
			if (this.start < 1) {
				throw new GLib.IOError.INVALID_ARGUMENT("Start parameter must be >= 1");
			}
			
			// Ensure tool config exists (creates with empty values if needed)
			OLLMtools.GoogleSearchTool.setup_tool_config(this.tool.client.config);
			
			// Get tool config (guaranteed to exist after setup_tool_config)
			var tool_config = this.tool.client.config.tools.get("google_search") as OLLMtools.Tool.GoogleSearchToolConfig;
			
			if (tool_config.api_key == "" || tool_config.engine_id == "") {
				throw new GLib.IOError.FAILED(
					"Google Search config is missing api_key or engine_id. Please configure it in Settings > Tools."
				);
			}
			
			// Build API URL
			var url = "https://www.googleapis.com/customsearch/v1?key=%s&cx=%s&q=%s&start=%d".printf(
				GLib.Uri.escape_string(tool_config.api_key, "", true),
				GLib.Uri.escape_string(tool_config.engine_id, "", true),
				GLib.Uri.escape_string(this.query, "", true),
				this.start
			);
			
			// Send request message to UI
			this.send_ui("txt", "Google Search request for " + this.query, "");
			
			// Fetch search results
			GLib.Bytes content;
			Soup.Message? message = null;
			try {
				var session = new Soup.Session();
				message = new Soup.Message("GET", url);
				content = yield session.send_and_read_async(message, GLib.Priority.DEFAULT, null);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to fetch search results: " + e.message);
			}
			
			// Ensure message is valid before accessing properties
			if (message == null) {
				throw new GLib.IOError.FAILED("Failed to create HTTP message");
			}
			
			// Check HTTP status for errors
			if (message.status_code < 200 || message.status_code >= 400) {
				throw new GLib.IOError.FAILED("HTTP error: " + message.status_code.to_string());
			}
			
			// Parse JSON response
			var json_data = (string)content.get_data();
			var parser = new Json.Parser();
			try {
				parser.load_from_data(json_data, -1);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to parse JSON response: " + e.message);
			}
			
			var root_node = parser.get_root();
			if (root_node == null) {
				throw new GLib.IOError.FAILED("Empty JSON response");
			}
			
			// Check for API errors in response
			var root_object = root_node.get_object();
			if (root_object != null && root_object.has_member("error")) {
				var error_obj = root_object.get_object_member("error");
				if (error_obj != null) {
					var error_message = error_obj.has_member("message") 
						? error_obj.get_string_member("message") 
						: "Unknown API error";
					throw new GLib.IOError.FAILED("Google API error: " + error_message);
				}
			}
			
			// Deserialize search results (items array)
			var result = Json.gobject_deserialize(typeof(Result), root_node) as Result;
			if (result == null) {
				throw new GLib.IOError.FAILED("Failed to deserialize search results");
			}
			
			// Extract totalResults from searchInformation.totalResults
			if (root_object != null && root_object.has_member("searchInformation")) {
				var search_info = root_object.get_object_member("searchInformation");
				if (search_info != null && search_info.has_member("totalResults")) {
					var total_results_str = search_info.get_string_member("totalResults");
					if (total_results_str != null) {
						result.total_results = int.parse(total_results_str);
					}
				}
			}
			
			// Convert to markdown
			var markdown_result = result.to_markdown();
			
			// Send response message to UI
			this.send_ui("markdown", "Google Search reply", markdown_result);
			
			return markdown_result;
		}
	}
}

