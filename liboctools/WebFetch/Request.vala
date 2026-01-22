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
	 * Request handler for fetching web content with automatic format detection and conversion.
	 */
	public class Request : OLLMchat.Tool.RequestBase
	{
		// Parameter properties
		public string url { get; set; default = ""; }
		public string format { get; set; default = "markdown"; }
		
		/**
		 * Default constructor.
		 */
		public Request()
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
			if (this.extract_domain(this.url) == "") {
				throw new GLib.IOError.INVALID_ARGUMENT(
					"Invalid URL: unable to extract domain from '" + this.url + "'"
				);
			}
			
			// Validate format
			if (this.format != "markdown" && this.format != "raw" && this.format != "base64") {
				throw new GLib.IOError.INVALID_ARGUMENT("Format must be 'markdown', 'raw', or 'base64'");
			}
				
			// Send request message to UI
			this.send_ui(this.tool.name, "request", this.url);
			
			// Fetch URL with redirects disabled (redirects require approval)
			Bytes content;
			Soup.Message? message = null;
			try {
				// Note: libsoup 3.0 handles redirects automatically, but we check status codes
				// and handle redirects manually below to require approval
				var session = new Soup.Session();
				message = new Soup.Message("GET", this.url);
				content = yield session.send_and_read_async(message, GLib.Priority.DEFAULT, null);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to fetch URL: " + e.message);
			}
			
			// Ensure message is valid before accessing properties
			if (message == null) {
				throw new GLib.IOError.FAILED("Failed to create HTTP message");
			}
			
			// Handle non-redirect cases (redirects are handled below)
			// Check HTTP status for errors
			if (message.status_code < 200 || message.status_code >= 400) {
				throw new GLib.IOError.FAILED("HTTP error: " + message.status_code.to_string());
			}
			
			// Success case (200-299) - convert and return
			if (message.status_code < 300) {
				// Detect content type
				var content_type = this.detect_content_type(message.response_headers);
				
				// Convert content based on content type and format (updates this.format to actual format used)
				var result = this.convert_content(content, content_type);
				
				// Send response message to UI
				var response_title = this.tool.name + " - response (" + this.format + ")";
				this.send_ui(this.tool.name, response_title, result);
				
				return result;
			}
			
			// Handle redirect status codes (3xx range)
		
			var location = message.response_headers.get_one("Location");
			if (location == null || location == "") {
				throw new GLib.IOError.FAILED(
					"Redirect detected (status " + message.status_code.to_string() + 
					") but no Location header found"
				);
			}

			// Resolve relative redirect URLs to absolute URLs
			if (location.has_prefix("http://") || location.has_prefix("https://")) {
				throw new GLib.IOError.FAILED(
					"Redirect detected: " + this.url + " redirects to " + location + 
					". Please fetch the redirected URL directly if you want to access it."
				);
			}

			// Relative URL - resolve against base URL
			var base_uri = GLib.Uri.parse(this.url, GLib.UriFlags.NONE);
			if (base_uri == null) {
				throw new GLib.IOError.FAILED(
					"Redirect detected: " + this.url + " redirects to " + location + 
					" (unable to resolve relative URL)"
				);
			}

			var scheme = base_uri.get_scheme();
			var host = base_uri.get_host();
			var path = base_uri.get_path();
			if (path == null || path == "") {
				path = "/";
			}

			var redirect_url = scheme + "://" + host + location;
			if (!location.has_prefix("/")) {
				var base_dir = GLib.Path.get_dirname(path);
				redirect_url = scheme + "://" + host + 
					((base_dir == "." || base_dir == "") ? "/" : base_dir) + "/" + location;
			}
			throw new GLib.IOError.FAILED(
				"Redirect detected: " + this.url + " redirects to " + redirect_url + 
				". Please fetch the redirected URL directly if you want to access it."
			);
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
		 * Extract domain from URL and normalize to [[https://domain/]] format.
		 *
		 * @param url The URL to extract domain from
		 * @return Normalized domain string (e.g., "[[https://example.com/]]") or empty string on error
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
			GLib.HashTable<string, string>? params = null;
			var content_type = headers.get_content_type(out params);
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
		 * Convert content based on Content-Type and format property.
		 * Uses structured if/else for Content-Type matching (Vala doesn't support string switches).
		 * Updates this.format to reflect the actual format used.
		 * 
		 * @param content The content bytes
		 * @param content_type The detected Content-Type
		 * @return Converted content as string
		 */
		protected string convert_content(Bytes content, string content_type)
		{
			// Normalize content type to lowercase for comparison
			var normalized_type = content_type.down();
			
			// Content-Type starts with "image/" → always base64 (regardless of format parameter)
			if (normalized_type.has_prefix("image/")) {
				this.format = "base64";
				return this.convert_to_base64(content);
			}
			
			// Content-Type is "text/html" → handle based on format parameter
			// Note: base64 format is not supported for HTML (always convert to markdown or raw)
			if (normalized_type == "text/html") {
				switch (this.format) {
					case "raw":
						this.format = "raw";
						return (string)content.get_data();
					case "base64":
					case "markdown":
						 
					default:
						this.format = "markdown";
						return this.convert_html_to_markdown(content);
				}
			}
			
			// Content-Type starts with "text/" (non-HTML) → return raw text
			if (normalized_type.has_prefix("text/")) {
				this.format = "raw";
				return (string)content.get_data();
			}
			
			// Content-Type is "application/json" → return raw JSON
			if (normalized_type == "application/json") {
				this.format = "raw";
				return (string)content.get_data();
			}
			
			// Content-Type is anything else → base64
			this.format = "base64";
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
			return new Markdown.HtmlParser((string)html.get_data()).convert();
		}
	}
}

