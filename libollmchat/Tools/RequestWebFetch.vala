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
	 * Request handler for fetching web content with automatic format detection and conversion.
	 */
	public class RequestWebFetch : OLLMchat.Tool.RequestBase
	{
		// Parameter properties
		public string url { get; set; default = ""; }
		public string format { get; set; default = "markdown"; }
		
		/**
		 * Default constructor.
		 */
		public RequestWebFetch()
		{
		}
		
		protected override bool build_perm_question()
		{
			// Validate required parameter
			if (this.url == "") {
				return false;
			}
			
			// Extract and normalize domain
			var domain = this.extract_domain(this.url);
			if (domain == "") {
				return false;
			}
			
			// Set permission properties
			this.permission_target_path = domain;
			this.permission_operation = OLLMchat.ChatPermission.Operation.READ;
			this.permission_question = "Fetch URL: " + this.url + "?";
			
			return true;
		}
		
		protected override async string execute_request() throws Error
		{
			// Validate URL
			if (this.url == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("URL parameter is required");
			}
			
			// Validate that we can extract domain (URL must be valid)
			var domain = this.extract_domain(this.url);
			if (domain == "") {
				throw new GLib.IOError.INVALID_ARGUMENT(
					"Invalid URL: unable to extract domain from '" + this.url + "'"
				);
			}
			
			// Validate format
			if (this.format != "markdown" && this.format != "raw" && this.format != "base64") {
				throw new GLib.IOError.INVALID_ARGUMENT("Format must be 'markdown', 'raw', or 'base64'");
			}
			
			// Fetch URL with redirects disabled (redirects require approval)
			Bytes content;
			Soup.Message message;
			try {
				var session = new Soup.Session();
				// Disable automatic redirect following - redirects must go through approval
				session.set_property("max-redirects", 0);
				message = new Soup.Message("GET", this.url);
				content = yield session.send_and_read_async(message, GLib.Priority.DEFAULT, null);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to fetch URL: " + e.message);
			}
			
			// Check for redirect status codes (3xx range)
			if (message.status_code > 299 && message.status_code < 400) {
				var location = message.response_headers.get_one("Location");
				if (location != null && location != "") {
					// Resolve relative redirect URLs
					var redirect_url = GLib.Uri.resolve(
						GLib.UriFlags.NONE,
						this.url,
						location
					);
					throw new GLib.IOError.FAILED(
						"Redirect detected: " + this.url + " redirects to " + redirect_url + 
						". Please fetch the redirected URL directly if you want to access it."
					);
				}
				throw new GLib.IOError.FAILED(
					"Redirect detected (status " + message.status_code.to_string() + 
					") but no Location header found"
				);
			}
			
			// Check HTTP status for other errors
			if (message.status_code < 200 || message.status_code >= 300) {
				throw new GLib.IOError.FAILED("HTTP error: " + message.status_code.to_string());
			}
			
			// Detect content type
			var content_type = this.detect_content_type(message.response_headers);
			
			// Convert content based on content type and format
			return this.convert_content(content, content_type, this.format);
		}
		
		/**
		 * Core HTTP fetching logic (GET only).
		 * 
		 * @param url The URL to fetch
		 * @return The response body as Bytes
		 */
		protected async Bytes fetch_url(string url) throws Error
		{
			var session = new Soup.Session();
			var message = new Soup.Message("GET", url);
			var bytes = yield session.send_and_read_async(message, GLib.Priority.DEFAULT, null);
			
			if (message.status_code < 200 || message.status_code >= 300) {
				throw new GLib.IOError.FAILED("HTTP error: " + message.status_code.to_string());
			}
			
			return bytes;
		}
		
		/**
		 * Extract domain from URL and normalize to https://{domain}/ format.
		 * 
		 * @param url The URL to extract domain from
		 * @return Normalized domain string (e.g., "https://example.com/") or empty string on error
		 */
		protected string extract_domain(string url)
		{
			try {
				var uri = GLib.Uri.parse(url, GLib.UriFlags.NONE);
				if (uri == null) {
					return "";
				}
				
				var host = uri.get_host();
				
				if (host == null || host == "") {
					return "";
				}
				
				// Normalize to https://{domain}/ format (even if original was http)
				return "https://" + host + "/";
			} catch (GLib.Error e) {
				return "";
			}
		}
		
		/**
		 * Extract Content-Type from response headers.
		 * 
		 * @param headers The response headers
		 * @return Content-Type string or "application/octet-stream" if not found
		 */
		protected string detect_content_type(Soup.MessageHeaders headers)
		{
			var content_type = headers.get_content_type();
			if (content_type != null) {
				return content_type;
			}
			
			// Try to get from Content-Type header directly
			var content_type_header = headers.get_one("Content-Type");
			if (content_type_header != null) {
				// Extract just the MIME type (before semicolon)
				var parts = content_type_header.split(";");
				if (parts.length > 0) {
					return parts[0].strip();
				}
			}
			
			return "application/octet-stream";
		}
		
		/**
		 * Convert content based on Content-Type and format parameter.
		 * Uses structured if/else for Content-Type matching (Vala doesn't support string switches).
		 * 
		 * @param content The content bytes
		 * @param content_type The detected Content-Type
		 * @param format The requested format ("markdown", "raw", or "base64")
		 * @return Converted content as string
		 */
		protected string convert_content(Bytes content, string content_type, string format)
		{
			// Normalize content type to lowercase for comparison
			var normalized_type = content_type.down();
			
			// Content-Type starts with "image/" → always base64 (regardless of format parameter)
			if (normalized_type.has_prefix("image/")) {
				return this.convert_to_base64(content);
			}
			
			// Content-Type is "text/html" → handle based on format parameter
			// Note: base64 format is not supported for HTML (always convert to markdown or raw)
			if (normalized_type == "text/html") {
				switch (format) {
					case "markdown":
						return this.convert_html_to_markdown(content);
					case "raw":
						return (string)content.get_data();
					case "base64":
						// Base64 not supported for HTML - convert to markdown instead
						return this.convert_html_to_markdown(content);
					default:
						return this.convert_html_to_markdown(content);
				}
			}
			
			// Content-Type starts with "text/" (non-HTML) → return raw text
			if (normalized_type.has_prefix("text/")) {
				return (string)content.get_data();
			}
			
			// Content-Type is "application/json" → return raw JSON
			if (normalized_type == "application/json") {
				return (string)content.get_data();
			}
			
			// Content-Type is anything else → base64
			return this.convert_to_base64(content);
		}
		
		/**
		 * Convert content to base64 encoding.
		 * 
		 * @param content The content bytes
		 * @return Base64-encoded string
		 */
		protected string convert_to_base64(Bytes content)
		{
			return GLib.Base64.encode(content.get_data());
		}
		
		/**
		 * Convert HTML content to markdown format.
		 * 
		 * @param html The HTML content as Bytes
		 * @return Markdown string
		 */
		protected string convert_html_to_markdown(Bytes html)
		{
			var html_string = (string)html.get_data();
			var parser = new Markdown.HtmlParser(html_string);
			return parser.convert();
		}
	}
}

