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
	 * JSON-RPC over stdin/stdout (newline-delimited). Uses bubblewrap when
	 * available; otherwise requires allow_unsandboxed in mcp.json (Flatpak, Windows).
	 *
	 * == Overlay writes (known gap) ==
	 *
	 * Sandboxed stdio MCP is spawned inside a bwrap overlay with project write
	 * roots (default {@code allow_writes} → {@code project}). Unlike the
	 * {@code run_command} tool, this path does ''not'' run
	 * {@code overlay.scan.run()} or apply changes to the live project index.
	 *
	 *  * {@link OLLMbwrap.RunSeccomp} only adds syscall ''evidence'' strings to tool output
	 *  * File creates/edits/deletes inside the overlay are ''not'' merged to disk
	 *  * On {@link disconnect}, overlay upper-layer changes are ''probably lost''
	 *
	 * ''TODO:'' After disconnect (or per tool call), run overlay scan +
	 * {@code FileVerification} report-back — same pipeline as {@code run_command}
	 * / {@code libocbwrap} — so MCP filesystem changes persist and update the
	 * project index (RPC-backed once on {@code ollmfilesd}).
	 */
	public class Stdio : Base
	{
		private OLLMmcp.Config config;
		private unowned OLLMfiles.ProjectManager project_manager;
		private OLLMbwrap.RunSeccomp? run_seccomp;
		private GLib.Subprocess? process;
		private DataInputStream? stdout_reader;
		private DataOutputStream? stdin_writer;
		private uint next_id = 1;

		public Stdio(OLLMmcp.Config config, OLLMfiles.ProjectManager project_manager)
		{
			this.config = config;
			this.project_manager = project_manager;
		}

		public override async void connect() throws Error
		{
			string[] argv = this.build_spawn_argv();
			var launcher = new GLib.SubprocessLauncher(
				GLib.SubprocessFlags.STDIN_PIPE | GLib.SubprocessFlags.STDOUT_PIPE
			);
			foreach (var entry in this.config.env.entries) {
				launcher.setenv(entry.key, entry.value, true);
			}
			if (this.run_seccomp != null) {
				this.run_seccomp.wire_launcher(launcher);
			}
			try {
				this.process = launcher.spawnv(argv);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to start MCP process: " + e.message);
			}
			if (this.run_seccomp != null) {
				this.run_seccomp.finish_handshake();
			}

			InputStream? stdout_pipe = this.process.get_stdout_pipe();
			OutputStream? stdin_pipe = this.process.get_stdin_pipe();
			if (stdout_pipe == null || stdin_pipe == null) {
				this.disconnect();
				throw new GLib.IOError.FAILED("Failed to get MCP process pipes");
			}

			this.stdout_reader = new DataInputStream(stdout_pipe);
			this.stdin_writer = new DataOutputStream(stdin_pipe);

			yield this.init();
		}

		/**
		 * Tear down the MCP subprocess.
		 *
		 * ''TODO:'' Run {@code bubble.overlay.scan.run()} (and cleanup) here so
		 * overlay writes are applied before exit — see class docblock.
		 */
		public override void disconnect()
		{
			if (this.process != null) {
				this.process.force_exit();
				this.process = null;
			}
			this.stdout_reader = null;
			this.stdin_writer = null;
			if (this.run_seccomp != null) {
				this.run_seccomp.detach_sources();
				this.run_seccomp = null;
			}
		}

		public override async Gee.ArrayList<OLLMmcp.Factory> tools() throws Error
		{
			var response = yield this.jrequest(new OLLMmcp.JsonRpcRequest() {
				id = (int) this.next_id++,
				method = "tools/list"
			});
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
			foreach (var f in list_result.tools) {
				factories.add(f);
			}
			return factories;
		}

		public override async string call(string name, Json.Object arguments) throws Error
		{
			var call_params = new OLLMmcp.CallToolParams() {
				name = name,
				arguments = arguments
			};
			var response = yield this.jrequest(new OLLMmcp.JsonRpcRequest() {
				id = (int) this.next_id++,
				method = "tools/call",
				params_tools_call = call_params
			});
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
			string text = call_result.text_content();
			if (this.run_seccomp == null) {
				return text;
			}
			this.run_seccomp.finish_evidence_formatting();
			if (this.run_seccomp.network != "") {
				text += "\n\n" + this.run_seccomp.network.replace(
					"run_command",
					"mcp.json (server \"" + this.config.id + "\")"
				);
			}
			if (this.run_seccomp.fs != "") {
				text += "\n\n" + this.run_seccomp.fs;
			}
			return text;
		}

		private string[] build_spawn_argv() throws Error
		{
			if (GLib.Environment.get_variable("FLATPAK_ID") != null) {
				if (!this.config.allow_unsandboxed) {
					throw new GLib.IOError.FAILED(
						"MCP server '" + this.config.id
						+ "': stdio disabled inside sandbox; set allow_unsandboxed true in mcp.json"
					);
				}
				return this.build_direct_argv();
			}
			if (!OLLMbwrap.Bubble.can_wrap()) {
#if G_OS_WIN32
				if (!this.config.allow_unsandboxed) {
					throw new GLib.IOError.FAILED(
						"MCP server '" + this.config.id
						+ "': sandboxing is unavailable; set allow_unsandboxed true in mcp.json"
					);
				}
				return this.build_direct_argv();
#else
				throw new GLib.IOError.FAILED(
					"MCP server '" + this.config.id
					+ "': bubblewrap required for stdio MCP on host"
				);
#endif
			}
			OLLMfiles.Folder? project = this.project_manager.active_project;
			string[] write_array = {};
			if (project != null && this.config.allow_writes.size == 0) {
				write_array += "project";
			}
			if (this.config.allow_writes.size > 0) {
				foreach (var entry in this.config.allow_writes) {
					write_array += entry;
				}
			}
			var project_path = "";
			var write_roots = new Gee.HashMap<string, string>();
			if (project != null) {
				project_path = project.path;
				foreach (var folder in project.build_roots()) {
					write_roots.set(folder.path, folder.path);
				}
			}
			var bubble = new OLLMbwrap.Bubble(new OLLMbwrap.NoOpFileVerification()) {
				project_path = project_path,
				allow_network = this.config.network,
				write_tokens = write_array,
				write_roots = write_roots
			};
			this.run_seccomp = new OLLMbwrap.RunSeccomp(bubble);
			// TODO: scan + apply overlay changes on disconnect — see class docblock.
			string[] args = bubble.build_bubble_args("", "");
			args += this.config.command;
			foreach (var a in this.config.args) {
				args += a;
			}
			return args;
		}

		private string[] build_direct_argv()
		{
			string[] argv = {};
			argv += this.config.command;
			foreach (var a in this.config.args) {
				argv += a;
			}
			return argv;
		}

		private async void init() throws Error
		{
			yield this.jrequest(new OLLMmcp.JsonRpcRequest() {
				id = (int) this.next_id++,
				method = "initialize",
				params_initialize = new OLLMmcp.InitializeParams()
			});

			var notif = new OLLMmcp.InitializedNotification();
			yield this.write(Json.to_string(Json.gobject_serialize(notif), false));
		}

		private async Json.Node? jrequest(OLLMmcp.JsonRpcRequest req) throws Error
		{
			yield this.write(Json.to_string(Json.gobject_serialize(req), false));

			var response = yield this.read_jresponse();
			this.check_jerr(response);
			return response;
		}

		private async Json.Node? read_jresponse() throws Error
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

		private void check_jerr(Json.Node? response) throws Error
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

		private async void write(string body) throws Error
		{
			string line = body + "\n";
			uint8[] buf = (uint8[]) line.to_utf8();
			yield this.stdin_writer.write_async(buf, GLib.Priority.DEFAULT, null);
		}
	}
}
