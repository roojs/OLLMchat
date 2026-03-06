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
 * along with this library; if not, see <https://www.gnu.org/licenses/>.
 */

/*
 * Class and properties defined in this file (tree of what is used):
 *
 *   OLLMmcp.Client
 *   └── Http : Client.Base
 *       ├── config          OLLMmcp.Config
 *       ├── session        Soup.Session?
 *       ├── base_url       string (from config.url)
 *       ├── next_id        uint (JSON-RPC request id)
 *       ├── connect()      → initialize + initialized; uses InitializeParams
 *       ├── disconnect()   → clears session
 *       ├── tools()   → jrequest("tools/list") → ToolsListResult → Factory.from_descriptor → Gee.ArrayList<Factory>
 *       ├── call()    → jrequest("tools/call") → CallToolResult.text_content()
 *       └── jrequest(method, params_json?)  → build_request_body, POST, parse; on error uses McpJsonRpcError
 */

namespace OLLMmcp.Client
{
	/**
	 * MCP client over HTTP: connects to an already-running MCP server at a URL.
	 * JSON-RPC via HTTP POST; no process lifecycle.
	 */
	public class Http : Base
	{
		private OLLMmcp.Config config;
		private Soup.Session? session;
		private string base_url;
		private uint next_id = 1;

		public Http(OLLMmcp.Config config)
		{
			this.config = config;
			this.base_url = this.config.url;
		}

		public override async void connect() throws Error
		{
			this.session = new Soup.Session();

			var init_params = new OLLMmcp.InitializeParams.with_client("ollmchat", "1.0");
			yield this.jrequest("initialize", init_params.to_params_json());

			string body = OLLMmcp.McpJson.initialized_notification_body();
			var msg = new Soup.Message("POST", this.base_url);
			msg.set_request_body_from_bytes("application/json", new GLib.Bytes((uint8[]) body.to_utf8()));
			try {
				yield this.session.send_async(msg, GLib.Priority.DEFAULT, null);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("MCP HTTP initialized: " + e.message);
			}
		}

		public override void disconnect()
		{
			this.session = null;
		}

		public override async Gee.ArrayList<OLLMmcp.Factory> tools() throws Error
		{
			var response = yield this.jrequest("tools/list", "{}");
			Json.Node? result_node = null;
			if (response != null) {
				var root = response.get_object();
				if (root != null && root.has_member("result")) {
					result_node = root.get_member("result");
				}
			}
			if (result_node == null) {
				return new Gee.ArrayList<OLLMmcp.Factory>();
			}
			var list_result = Json.gobject_deserialize(typeof(OLLMmcp.ToolsListResult), result_node) as OLLMmcp.ToolsListResult;
			if (list_result == null) {
				return new Gee.ArrayList<OLLMmcp.Factory>();
			}
			var factories = new Gee.ArrayList<OLLMmcp.Factory>();
			foreach (var d in list_result.tools) {
				factories.add(OLLMmcp.Factory.from_descriptor(d));
			}
			return factories;
		}

		public override async string call(string name, Json.Object arguments) throws Error
		{
			var call_params = OLLMmcp.CallToolParams.with_arguments(name, arguments);
			var response = yield this.jrequest("tools/call", call_params.to_params_json());
			Json.Node? result_node = null;
			if (response != null) {
				var root = response.get_object();
				if (root != null && root.has_member("result")) {
					result_node = root.get_member("result");
				}
			}
			if (result_node == null) {
				return "";
			}
			var call_result = Json.gobject_deserialize(typeof(OLLMmcp.CallToolResult), result_node) as OLLMmcp.CallToolResult;
			if (call_result == null) {
				return "";
			}
			return call_result.text_content();
		}

		private async Json.Node? jrequest(string method, string? params_json = null) throws Error
		{
			if (this.session == null) {
				throw new GLib.IOError.FAILED("MCP HTTP client not connected");
			}

			string body = OLLMmcp.McpJson.build_request_body(this.next_id++, method, params_json);
			var message = new Soup.Message("POST", this.base_url);
			message.set_request_body_from_bytes("application/json", new GLib.Bytes((uint8[]) body.to_utf8()));

			GLib.Bytes? bytes;
			try {
				bytes = yield this.session.send_and_read_async(message, GLib.Priority.DEFAULT, null);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("MCP HTTP request failed: " + e.message);
			}

			if (bytes == null || bytes.get_size() == 0) {
				throw new GLib.IOError.FAILED("Empty MCP HTTP response");
			}

			if (message.status_code != 200) {
				throw new GLib.IOError.FAILED(
					"MCP HTTP " + message.status_code.to_string() + ": " + (string) bytes.get_data()
				);
			}

			string data = (string) bytes.get_data();
			var parser = new Json.Parser();
			try {
				parser.load_from_data(data, -1);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Invalid MCP JSON response: " + e.message);
			}

			Json.Node? root = parser.get_root();
			if (root == null) {
				throw new GLib.IOError.FAILED("No JSON root in MCP response");
			}

			var root_obj = root.get_object();
			if (root_obj != null && root_obj.has_member("error")) {
				var err_node = root_obj.get_member("error");
				var err = Json.gobject_deserialize(typeof(OLLMmcp.McpJsonRpcError), err_node) as OLLMmcp.McpJsonRpcError;
				string msg = err != null && err.message != "" ? err.message : "JSON-RPC error";
				throw new GLib.IOError.FAILED("MCP error: " + msg);
			}

			return root;
		}
	}
}
