/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMrpc.Transport
{
	/**
	 * HTTP JSON RPC server ({@link Soup.Server}).
	 *
	 * POST to {@link rpc_path} with auto-JSON {@link OLLMrpc.Request} body
	 * (method in the body). Exact paths from {@link OLLMrpc.Http.routes}
	 * dispatch by verb+path. Replies are auto-JSON
	 * {@link OLLMrpc.Response}. Same {@link OLLMrpc.Request.dispatch}
	 * path as socket RPC. Runs on the process main loop — no fork or
	 * thread pool inside the library.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var http = new OLLMrpc.Transport.HttpServer(8080);
	 * http.start();
	 * }}}
	 */
	public class HttpServer : Listen
	{
		/**
		 * Bound TCP port. After {@link start} with port ''0'', updated to the
		 * ephemeral port Soup chose.
		 */
		public uint port { get; private set; default = 8080; }

		/**
		 * Path for POST body-method RPC (Hello / stream).
		 *
		 * Default ''/rpc''. Typed {@link OLLMrpc.Http.routes} paths are separate.
		 */
		public string rpc_path { get; set; default = "/rpc"; }

		private Soup.Server soup = new Soup.Server("server-header", null);
		private bool listening = false;
		private Bin.Json json = new Bin.Json(Bin.Mode.AUTO);

		public HttpServer(uint port = 8080)
		{
			GLib.Object();
			this.port = port;
		}

		public override bool start()
		{
			if (this.listening) {
				return true;
			}
			this.soup.add_handler(this.rpc_path, this.on_rpc);
			this.soup.add_handler(null, this.on_route);
			try {
				this.soup.listen_local(this.port, 0);
			} catch (GLib.Error e) {
				GLib.warning("failed to start HTTP server on port %u: %s",
					this.port, e.message);
				return false;
			}
			var uris = this.soup.get_uris();
			if (uris != null && uris.data != null) {
				this.port = (uint) uris.data.get_port();
			}
			this.listening = true;
			return true;
		}

		public override void stop()
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			this.soup.disconnect();
			this.soup = new Soup.Server("server-header", null);
		}

		private void on_route(
			Soup.Server server,
			Soup.ServerMessage msg,
			string path,
			GLib.HashTable<string, string>? query
		) {
			if (path == this.rpc_path) {
				return;
			}
			var verb = msg.get_method();
			if (OLLMrpc.Http.by_verb == null || !OLLMrpc.Http.by_verb.has_key(verb)) {
				msg.set_status(404, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY, "not found".data);
				return;
			}
			var paths = OLLMrpc.Http.by_verb.get(verb);
			var path_id = "";
			var lookup = path;
			if (!paths.has_key(path)) {
				var slash = path.last_index_of_char('/');
				if (slash <= 0) {
					msg.set_status(404, null);
					msg.set_response("text/plain", Soup.MemoryUse.COPY, "not found".data);
					return;
				}
				lookup = path.substring(0, slash);
				path_id = path.substring(slash + 1);
			}
			if (!paths.has_key(lookup)) {
				msg.set_status(404, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY, "not found".data);
				return;
			}
			var route = paths.get(lookup);
			if (path_id != "" && !route.variable) {
				msg.set_status(404, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY, "not found".data);
				return;
			}
			var reply = new HttpReply(this.soup, msg) {
				live_handles = this.live_handles
			};
			var request = new Request() {
				method = route.wire_name + "." + route.method,
				connection = reply
			};
			var have_body = false;
			var body = (GLib.Object) null;
			if (route.request_type != typeof(void)) {
				var bytes = msg.get_request_body().flatten();
				if (bytes.get_size() > 0) {
					var parser = new Json.Parser();
					try {
						parser.load_from_data((string) bytes.get_data(), (ssize_t) bytes.get_size());
					} catch (GLib.Error e) {
						reply.write(new Response() {
							error = new OLLMrpc.Error(
								(int) OLLMrpc.RpcErrorCode.PARSE_ERROR,
								"invalid JSON: " + e.message
							)
						});
						msg.set_status(400, null);
						return;
					}
					var root = parser.get_root();
					if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
						reply.write(new Response() {
							error = new OLLMrpc.Error(
								(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
								"JSON root must be an object"
							)
						});
						msg.set_status(400, null);
						return;
					}
					var mem = new GLib.MemoryOutputStream.resizable();
					var encode_ctx = new Bin.Stream(null, new GLib.DataOutputStream(mem));
					try {
						this.json.json_to_bin(root.get_object(), encode_ctx, route.request_type);
						encode_ctx.out_stream.close();
					} catch (GLib.Error e) {
						reply.write(new Response() {
							error = new OLLMrpc.Error(
								(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
								"request decode failed: " + e.message
							)
						});
						msg.set_status(400, null);
						return;
					}
					var read_ctx = new Bin.Stream(
						new GLib.DataInputStream(
							new GLib.MemoryInputStream.from_bytes(mem.steal_as_bytes())
						),
						null
					);
					read_ctx.mode = this.json.mode;
					Bin.Serializable parsed;
					try {
						parsed = read_ctx.parse();
					} catch (GLib.Error e) {
						reply.write(new Response() {
							error = new OLLMrpc.Error(
								(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
								"request parse failed: " + e.message
							)
						});
						msg.set_status(400, null);
						return;
					}
					body = parsed;
					have_body = true;
				}
			}
			if (route.variable && have_body) {
				request.args = OLLMrpc.args("so", path_id, body);
			} else if (route.variable) {
				request.args = OLLMrpc.args("s", path_id);
			} else if (have_body) {
				request.args = OLLMrpc.args("o", body);
			}
			if (!request.dispatch()) {
				msg.set_status(404, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY,
					("no handler for '" + request.method + "'").data);
			}
			if (reply.streaming && !reply.finished) {
				reply.paused = true;
				this.soup.pause_message(msg);
			}
		}

		private void on_rpc(
			Soup.Server server, 
			Soup.ServerMessage msg, 
			string path, 
			GLib.HashTable<string, string>? query
		) {
			var reply = new HttpReply(this.soup, msg) {
				live_handles = this.live_handles
			};
			if (msg.get_method() != "POST") {
				reply.write(new Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"POST required, got " + msg.get_method()
					)
				});
				msg.set_status(405, null);
				return;
			}
			var bytes = msg.get_request_body().flatten();
			var parser = new Json.Parser();
			try {
				parser.load_from_data((string) bytes.get_data(), (ssize_t) bytes.get_size());
			} catch (GLib.Error e) {
				reply.write(new Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.PARSE_ERROR,
						"invalid JSON: " + e.message
					)
				});
				msg.set_status(400, null);
				return;
			}
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				reply.write(new Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"JSON root must be an object"
					)
				});
				msg.set_status(400, null);
				return;
			}
			var mem = new GLib.MemoryOutputStream.resizable();
			var encode_ctx = new Bin.Stream(null, new GLib.DataOutputStream(mem));
			try {
				this.json.json_to_bin(root.get_object(), encode_ctx, typeof(Request));
				encode_ctx.out_stream.close();
			} catch (GLib.Error e) {
				reply.write(new Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"request decode failed: " + e.message
					)
				});
				msg.set_status(400, null);
				return;
			}
			var read_ctx = new Bin.Stream(
				new GLib.DataInputStream(
					new GLib.MemoryInputStream.from_bytes(mem.steal_as_bytes())
				),
				null
			);
			read_ctx.mode = this.json.mode;
			Bin.Serializable parsed;
			try {
				parsed = read_ctx.parse();
			} catch (GLib.Error e) {
				reply.write(new Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"request parse failed: " + e.message
					)
				});
				msg.set_status(400, null);
				return;
			}
			var request = parsed as OLLMrpc.Request;
			if (request == null) {
				reply.write(new Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"body did not decode to a Request"
					)
				});
				msg.set_status(400, null);
				return;
			}
			request.connection = reply;
			if (!request.dispatch()) {
				var err = OLLMrpc.RpcErrorCode.to_error(
					(int) OLLMrpc.RpcErrorCode.METHOD_NOT_FOUND
				);
				err.message = "no handler for '" + request.method + "'";
				reply.write(new Response() {
					id = request.id,
					error = err
				});
				return;
			}
			if (reply.streaming && !reply.finished) {
				reply.paused = true;
				this.soup.pause_message(msg);
			}
		}
	}
}
