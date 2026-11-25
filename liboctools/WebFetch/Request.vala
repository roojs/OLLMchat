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
		 * Default constructor.
		 */
		public Request()
		{
		}

		public override string to_summary ()
		{
			return this.url;
		}
		
		/**
		 * Asks before every fetch, keyed by the URL origin.
		 *
		 * Hostnames use a READ permission that may be remembered per
		 * origin; execute_request() then refuses a connection to a
		 * loopback, link-local or private address. IP literals and
		 * localhost skip that check, so they need a one-time EXECUTE
		 * approval that is never remembered.
		 *
		 * @return false when the URL is not an http(s) URL with a host
		 */
		public override bool build_perm_question()
		{
			GLib.Uri uri;
			try {
				uri = GLib.Uri.parse(this.url, (GLib.UriFlags) Soup.HTTP_URI_FLAGS);
			} catch (GLib.Error e) {
				return false;
			}
			if ((uri.get_scheme() != "http" && uri.get_scheme() != "https") ||
					uri.get_host() == null || uri.get_host() == "") {
				return false;
			}
			this.permission_target_path = GLib.Uri.join(GLib.UriFlags.NONE,
				uri.get_scheme(), null, uri.get_host(), uri.get_port(), "/", null, null);
			if (uri.get_host().down() != "localhost" && new GLib.InetAddress.from_string(uri.get_host()) == null) {
				this.permission_operation = OLLMchat.ChatPermission.Operation.READ;
				this.permission_question = "Fetch URL from " + this.permission_target_path + ": " + this.url + "?";
				return true;
			}
			this.one_time_only = true;
			this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
			this.permission_question = "Fetch URL from " + this.permission_target_path +
				" (an IP address or localhost; this can reach services on this computer " +
				"or your local network): " + this.url + "?";
			return true;
		}
		
		protected override async string execute_request() throws Error
		{
			// Validate URL
			if (this.url == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("URL parameter is required");
			}
			
			if (this.permission_target_path == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("Invalid URL: '" + this.url + "' is not an http or https URL with a host");
			}
			
			// Fetch exactly the origin that build_perm_question() put to the user
			var uri = GLib.Uri.parse(this.url, (GLib.UriFlags) Soup.HTTP_URI_FLAGS);
			if (GLib.Uri.join(GLib.UriFlags.NONE, uri.get_scheme(), null, uri.get_host(),
					uri.get_port(), "/", null, null) != this.permission_target_path) {
				throw new GLib.IOError.PERMISSION_DENIED("URL changed after permission was granted: " + this.url);
			}
			
			// Validate format
			if (this.format != "markdown" && this.format != "raw" && this.format != "base64") {
				throw new GLib.IOError.INVALID_ARGUMENT("Format must be 'markdown', 'raw', or 'base64'");
			}
				
			// Send request message to UI
			this.agent.add_message(new OLLMchat.Message("ui", 
				OLLMchat.Message.fenced("text.oc-frame-info.collapsed request", this.to_summary ())));
			
			// Redirects are not followed: a redirect target has not been approved,
			// so it is reported below and the model must fetch it as a new request.
			var refused = "";
			var message = new Soup.Message.from_uri("GET", uri);
			message.add_flags(Soup.MessageFlags.NO_REDIRECT);
			message.request_headers.replace("User-Agent", USER_AGENT);
			// Checked on the connected socket, before TLS or any request bytes,
			// so a second DNS answer cannot swap in a different address.
			message.network_event.connect((event, connection) => {
				if (event != GLib.SocketClientEvent.CONNECTED ||
						this.permission_operation == OLLMchat.ChatPermission.Operation.EXECUTE) {
					return;
				}
				GLib.SocketAddress peer;
				try {
					peer = ((GLib.SocketConnection) connection).get_remote_address();
				} catch (GLib.Error e) {
					// Unknown peer is refused as the unspecified address
					GLib.warning("Could not read the address of %s: %s", uri.get_host(), e.message);
					peer = new GLib.InetSocketAddress(new GLib.InetAddress.any(GLib.SocketFamily.IPV4), 0);
				}
				// A proxy resolves the host itself; this address is the proxy's
				if (peer is GLib.ProxyAddress) {
					return;
				}
				var addr = ((GLib.InetSocketAddress) peer).address;
				// IPv4-mapped (::ffff:a.b.c.d) and compatible forms reach the IPv4 host
				if (addr.family == GLib.SocketFamily.IPV6 && addr.to_string().contains(".")) {
					addr = new GLib.InetAddress.from_string(
						addr.to_string().substring(addr.to_string().last_index_of(":") + 1));
				}
				unowned var b = addr.to_bytes();
				if (!addr.is_any && !addr.is_loopback && !addr.is_link_local &&
						!addr.is_site_local && !addr.is_multicast &&
						(addr.family != GLib.SocketFamily.IPV4 ||
							(b[0] != 0 && (b[0] != 100 || (b[1] & 0xc0) != 64))) &&
						(addr.family != GLib.SocketFamily.IPV6 || (b[0] & 0xfe) != 0xfc)) {
					return;
				}
				refused = "Refused to fetch " + this.url + ": " + uri.get_host() +
					" is a loopback, link-local or private network address. " +
					"Fetch the IP address or localhost directly so the user is asked.";
				try {
					connection.close();
				} catch (GLib.Error e) {
					GLib.warning("Could not close refused connection: %s", e.message);
				}
			});
			Bytes content;
			try {
				content = yield ((Tool) this.tool).soup.send_and_read_async(
					message, GLib.Priority.DEFAULT, null);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to fetch URL: " + (refused != "" ? refused : e.message));
			}
			if (refused != "") {
				throw new GLib.IOError.PERMISSION_DENIED(refused);
			}
			
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

