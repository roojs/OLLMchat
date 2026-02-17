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

namespace OLLMtools.WebFetch
{
	/**
	 * Tool for fetching web content with automatic format detection and conversion.
	 * 
	 * This tool fetches content from URLs and returns it in various formats.
	 * HTML content can be converted to markdown, and binary content is automatically
	 * converted to base64. The tool automatically detects content types and applies
	 * appropriate conversions.
	 */
	public class Tool : OLLMchat.Tool.BaseTool, OLLMchat.Tool.WrapInterface
	{
		public override string name { get { return "web_fetch"; } }
		
		public override Type config_class() { return typeof(OLLMchat.Settings.BaseToolConfig); }
		public override string title { get { return "Web Fetch URL Tool"; } }
		public override string example_call {
			get { return "{\"name\": \"web_fetch\", \"arguments\": {\"url\": \"https://example.com\"}}"; }
		}
		public override string description { get {
			return """
Fetch content from a URL and return it in the specified format.

This tool automatically detects the content type and applies appropriate conversions:
- HTML content can be converted to markdown or returned as raw HTML
- Text content is returned as raw text
- Binary content (images, PDFs, etc.) is automatically converted to base64
- JSON content is returned as raw JSON

The tool requires permission to access the domain of the URL being fetched.""";
		} }
		
		public override string parameter_description { get {
			return """
@param url {string} [required] The URL to fetch.
@param format {string} [optional] The output format: "markdown", "raw", or "base64". Default is "markdown". Note: Binary content (images, PDFs, etc.) is always returned as base64 regardless of the format parameter.""";
		} }
		
		/**
		 * ProjectManager instance for accessing project context.
		 * Optional - set to null if not available.
		 */
		public OLLMfiles.ProjectManager? project_manager { get; set; default = null; }
		
	public Tool(OLLMfiles.ProjectManager? project_manager = null)
	{
		base();
		this.project_manager = project_manager;
	}
		
		public OLLMchat.Tool.BaseTool clone()
		{
			return new Tool(this.project_manager);
		}
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(Request), parameters_node) as OLLMchat.Tool.RequestBase;
		}
		
		/**
		 * Implements WrapInterface.deserialize_wrapped() for wrapped tool execution.
		 * 
		 * For WebFetch, no special handling is needed - simply calls the regular
		 * deserialize() method since wrapped tools can pass parameters directly.
		 * 
		 * @param parameters_node The parameters as a Json.Node
		 * @param command_template The command template (not used for WebFetch)
		 * @return A Request instance or null if deserialization fails
		 */
		public OLLMchat.Tool.RequestBase? deserialize_wrapped(Json.Node parameters_node, string command_template)
		{
			// No special handling needed - just call regular deserialize
			return this.deserialize(parameters_node);
		}
	}
}

