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

namespace OLLMchat.Call
{
	/**
	 * API call to get the version of the Ollama server.
	 *
	 * Retrieves the version string from the server to verify connectivity.
	 * Used during bootstrap to test the connection.
	 */
	public class Version : Base
	{
		public Version(Client client)
		{
			base(client);
			this.url_endpoint = "version";
			this.http_method = "GET";
		}

		/**
		 * Executes the version API call and returns the version string.
		 *
		 * @return Version string from the server (e.g., "0.12.6")
		 * @throws Error if the request fails or response is invalid
		 */
		public async string exec_version() throws Error
		{
			var bytes = yield this.send_request(false);
			var root = this.parse_response(bytes);

			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllamaError.FAILED("Invalid JSON response");
			}

			var root_obj = root.get_object();
			if (!root_obj.has_member("version")) {
				throw new OllamaError.FAILED("Response missing 'version' field");
			}

			return root_obj.get_string_member("version");
		}
	}
}
