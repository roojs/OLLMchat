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
		private const string USER_AGENT =
			"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36";

		/** Beyond this many newline-separated lines, tool output is capped for the LLM and UI. */
		private const int TOOL_BODY_MAX_LINES = 200;

		// Parameter properties
		public string url { get; set; default = ""; }
		/** Requested output: "markdown", "raw", or "base64". */
		public string format { get; set; default = "markdown"; }
		/** Actual result type after conversion: "markdown", "html", "json", "text", or "base64". Set by convert_content. */
		private string result_format = "text";

		/**
		 * GET built from {@link url} by {@link build_perm_question}.
		 *
		 * The permission target is this message's host, and it is
		 * the only message ever sent, so the host the user approved
		 * is the host contacted. Null until bound, or when the URL
		 * is not http(s) with a host.
		 */
		private Soup.Message? message = null;

		/**
		 * {@link url} as it was when {@link message} was built.
		 */
		private string message_url = "";
		
		/**
		 * Default constructor.
		 */
		public Request()
		{
		}

		public override string to_summary ()
		{
			return this.url;
		}
		
		public override bool build_perm_question()
		{
			// Bind once: if the URL changes while the user is being
			// asked, the answer still applies to this message only.
			if (this.message != null) {
				return true;
			}
			this.message_url = this.url;
			this.message = new Soup.Message("GET", this.url);
			if (this.message == null) {
				return false;
			}
			var uri = this.message.get_uri();
			if (uri.get_scheme() != "http" && uri.get_scheme() != "https") {
				this.message = null;
				return false;
			}
			this.message.flags = Soup.MessageFlags.NO_REDIRECT;
			this.message.request_headers.replace("User-Agent", USER_AGENT);
			var port = uri.get_port() != -1 ? uri.get_port() : (uri.get_scheme() == "https" ? 443 : 80);
			this.permission_target_path = "web_fetch#" + uri.get_scheme() + "#" +
				uri.get_host().down() + "#" + port.to_string();
			this.permission_operation = OLLMchat.ChatPermission.Operation.READ;
			this.permission_question = "Fetch URL: " + this.message_url + "?";
			return true;
		}
		
		protected override async string execute_request() throws Error
		{
			// Validate URL
			if (this.url == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("URL parameter is required");
			}
			
			if (this.message == null) {
				throw new GLib.IOError.INVALID_ARGUMENT("Invalid URL (http or https with a host required): '" +
					this.url + "'");
			}
			
			if (this.url != this.message_url) {
				throw new GLib.IOError.PERMISSION_DENIED("URL changed after permission was asked; nothing was fetched");
			}
			
			// Validate format
			if (this.format != "markdown" && this.format != "raw" && this.format != "base64") {
				throw new GLib.IOError.INVALID_ARGUMENT("Format must be 'markdown', 'raw', or 'base64'");
			}
				
			// Send request message to UI
			this.agent.add_message(new OLLMchat.Message("ui", 
				OLLMchat.Message.fenced("text.oc-frame-info.collapsed request", this.to_summary ())));
			
			// NO_REDIRECT is set on the message: following a redirect
			// would reach a host the user did not approve.
			Bytes content;
			try {
				content = yield ((Tool) this.tool).soup.send_and_read_async(
					this.message, GLib.Priority.DEFAULT, null);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to fetch URL: " + e.message);
			}
			
			// Handle non-redirect cases (redirects are handled below)
			// Check HTTP status for errors
			if (this.message.status_code < 200 || this.message.status_code >= 400) {
				throw new GLib.IOError.FAILED("HTTP error: " + this.message.status_code.to_string());
			}
			
			// Success case (200-299) - convert and return
			if (this.message.status_code < 300) {
				// Detect content type
				var content_type = this.detect_content_type(this.message.response_headers);
				
				// Convert content based on content type and format (updates this.format to actual format used)
				var result = this.convert_content(content, content_type);
				result = result.replace("\r\n", "\n");
				var parts = result.split("\n");
				if (parts.length > TOOL_BODY_MAX_LINES) {
					result = string.joinv("\n", parts[0:TOOL_BODY_MAX_LINES]) +
						"\n\n[Truncated: response had " + parts.length.to_string() +
						" lines; showing the first " + TOOL_BODY_MAX_LINES.to_string() +
						" lines only. Do not pull large page slices here (e.g. curl piped " +
						"to head or wide ranges); that still floods context. For a targeted " +
						"follow-up via bash, use a narrow pipeline — for example " +
						"curl -sL '" + this.url + "' | grep -E 'YourPattern' — so only matching " +
						"lines are returned. That bash call must include \"network\": true " +
						"(curl needs outbound network; the user may need to approve).]\n";
				}

				// Send response message to UI using result_format (markdown, html, json, text, base64)
				var response_title = this.tool.name + " - response (" + this.result_format + ")";
				var type_prefix = this.result_format == "base64" ? "text" : this.result_format;
				this.agent.add_message(new OLLMchat.Message("ui", 
					OLLMchat.Message.fenced(type_prefix + ".oc-frame-success.collapsed " + response_title, result)));
				
				return result;
			}
			
			// Handle redirect status codes (3xx range)
		
			var location = this.message.response_headers.get_one("Location");
			if (location == null || location == "") {
				throw new GLib.IOError.FAILED(
					"Redirect detected (status " + this.message.status_code.to_string() + 
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
		 * Sends only the message bound by {@link build_perm_question}
		 * for this same URL; any other URL is refused unsent.
		 * 
		 * @param url The URL to fetch
		 * @return The response body as Bytes
		 */
		protected async Bytes fetch_url(string url) throws Error
		{
			if (this.message == null || url != this.message_url) {
				throw new GLib.IOError.PERMISSION_DENIED("URL was not approved for fetching: " + url);
			}
			var bytes = yield ((Tool) this.tool).soup.send_and_read_async(
				this.message, GLib.Priority.DEFAULT, null);
			
			if (this.message.status_code < 200 || this.message.status_code >= 300) {
				throw new GLib.IOError.FAILED("HTTP error: " + this.message.status_code.to_string());
			}
			
			return bytes;
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
		 * Sets this.result_format to the actual result type: markdown, html, json, text, or base64.
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
				this.result_format = "base64";
				return this.convert_to_base64(content);
			}
			
			// Content-Type is "text/html" → handle based on format parameter
			if (normalized_type == "text/html") {
				switch (this.format) {
					case "raw":
						this.result_format = "html";
						return (string)content.get_data();
					case "base64":
					case "markdown":
					default:
						this.result_format = "markdown";
						return this.convert_html_to_markdown(content);
				}
			}
			
			// Content-Type starts with "text/" (non-HTML) → return raw text
			if (normalized_type.has_prefix("text/")) {
				this.result_format = "text";
				return (string)content.get_data();
			}
			
			// Content-Type is "application/json" → return raw JSON
			if (normalized_type == "application/json") {
				this.result_format = "json";
				return (string)content.get_data();
			}
			
			// Content-Type is anything else → base64
			this.result_format = "base64";
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

