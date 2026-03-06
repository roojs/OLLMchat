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

namespace OLLMmcp.Client
{
	/**
	 * MCP client over stdio: starts the server as a subprocess and talks
	 * JSON-RPC over stdin/stdout (newline-delimited). Uses bwrap when
	 * available (not in Flatpak); otherwise spawns the process directly.
	 */
	public class Stdio : Base
	{
		private OLLMmcp.Config config;
		private GLib.Subprocess? process;
		private DataInputStream? stdout_reader;
		private DataOutputStream? stdin_writer;
		private uint next_id = 1;

		public Stdio(OLLMmcp.Config config)
		{
			this.config = config;
		}

		public override async void connect() throws Error
		{
			string[] argv = this.build_argv();
			try {
				this.process = new GLib.Subprocess.newv(
					argv,
					GLib.SubprocessFlags.STDIN_PIPE | GLib.SubprocessFlags.STDOUT_PIPE
				);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to start MCP process: " + e.message);
			}

			InputStream? stdout_pipe = this.process.get_stdout_pipe();
			OutputStream? stdin_pipe = this.process.get_stdin_pipe();
			if (stdout_pipe == null || stdin_pipe == null) {
				this.disconnect();
				throw new GLib.IOError.FAILED("Failed to get MCP process pipes");
			}

			this.stdout_reader = new DataInputStream(stdout_pipe);
			this.stdin_writer = new DataOutputStream(stdin_pipe);

			yield this.send_initialize();
		}

		public override void disconnect()
		{
			if (this.process != null) {
				this.process.send_signal(GLib.SubprocessSignal.TERM);
				this.process = null;
			}
			this.stdout_reader = null;
			this.stdin_writer = null;
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

		private static bool can_use_bwrap()
		{
			if (GLib.Environment.get_variable("FLATPAK_ID") != null) {
				return false;
			}
			if (GLib.Environment.find_program_in_path("bwrap") == null) {
				return false;
			}
			return true;
		}

		private string[] build_argv()
		{
			if (!Stdio.can_use_bwrap()) {
				return this.build_argv_raw();
			}
			return this.build_argv_bwrap();
		}

		private string[] build_argv_raw()
		{
			string[] argv = {};
			argv += this.config.command;
			foreach (var a in this.config.args) {
				argv += a;
			}
			return argv;
		}

		private string[] build_argv_bwrap()
		{
			var bwrap_path = GLib.Environment.find_program_in_path("bwrap");
			if (bwrap_path == null) {
				return this.build_argv_raw();
			}
			string[] args = {};
			args += bwrap_path;
			args += "--unshare-user";
			args += "--ro-bind";
			args += "/";
			args += "/";
			args += "--tmpfs";
			args += "/tmp";
			args += "--ro-bind";
			args += "/dev";
			args += "/dev";
			args += "--dev-bind";
			args += "/dev/null";
			args += "/dev/null";
			if (!this.config.network) {
				args += "--unshare-net";
			}
			args += "--";
			args += this.config.command;
			foreach (var a in this.config.args) {
				args += a;
			}
			return args;
		}

		private async void send_initialize() throws Error
		{
			var init_params = new OLLMmcp.InitializeParams.with_client("ollmchat", "1.0");
			string body = OLLMmcp.McpJson.build_request_body(this.next_id++, "initialize", init_params.to_params_json());
			yield this.write_line(body);

			var response = yield this.read_json_rpc_response();
			this.check_json_rpc_error(response);

			yield this.write_line(OLLMmcp.McpJson.initialized_notification_body());
		}

		private async Json.Node? jrequest(string method, string? params_json = null) throws Error
		{
			string body = OLLMmcp.McpJson.build_request_body(this.next_id++, method, params_json);
			yield this.write_line(body);

			var response = yield this.read_json_rpc_response();
			this.check_json_rpc_error(response);
			return response;
		}

		private async Json.Node? read_json_rpc_response() throws Error
		{
			string? line = yield this.stdout_reader.read_line_async(GLib.Priority.DEFAULT, null);
			if (line == null || line.strip() == "") {
				throw new GLib.IOError.FAILED("Empty or missing JSON-RPC response");
			}

			var parser = new Json.Parser();
			try {
				parser.load_from_data(line.strip(), -1);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Invalid JSON-RPC response: " + e.message);
			}

			Json.Node? root = parser.get_root();
			if (root == null) {
				throw new GLib.IOError.FAILED("No JSON root in response");
			}
			return root;
		}

		private void check_json_rpc_error(Json.Node? response) throws Error
		{
			Json.Object? obj = response != null ? response.get_object() : null;
			if (obj == null || !obj.has_member("error")) {
				return;
			}
			var err_node = obj.get_member("error");
			var err = Json.gobject_deserialize(typeof(OLLMmcp.McpJsonRpcError), err_node) as OLLMmcp.McpJsonRpcError;
			string msg = err != null && err.message != "" ? err.message : "JSON-RPC error";
			throw new GLib.IOError.FAILED("MCP error: " + msg);
		}

		private async void write_line(string body) throws Error
		{
			string line = body + "\n";
			uint8[] buf = (uint8[]) line.to_utf8();
			yield this.stdin_writer.write_async(buf, GLib.Priority.DEFAULT, null);
		}
	}
}
