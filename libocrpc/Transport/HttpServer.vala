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
	 * var cert = new OLLMrpc.Transport.Cert() {
	 *     dir = tls_dir,
	 *     ca_pem_path = ca_pem,
	 *     ca_key_path = ca_key,
	 *     server_san = true,
	 * };
	 * cert.ensure();
	 * http.tls_certificate = cert.certificate;
	 * http.start();
	 * }}}
	 */
	public class HttpServer : Listen
	{
		/**
		 * Bound TCP port. After {@link start} with port ''0'', updated to the
		 * ephemeral port Soup chose.
		 */
		public uint port { get; set; default = 8080; }

		/**
		 * Path for POST body-method RPC (Hello / stream).
		 *
		 * Default ''/rpc''. Typed {@link OLLMrpc.Http.routes} paths are separate.
		 */
		public string rpc_path { get; set; default = "/rpc"; }

		/**
		 * Server TLS identity. Non-null → {@link start} listens with
		 * {@link Soup.ServerListenOptions.HTTPS}.
		 *
		 * Typical: configure {@link Cert}, call {@link Cert.ensure}, assign
		 * {@link Cert.certificate}.
		 */
		public GLib.TlsCertificate? tls_certificate { get; set; default = null; }

		/**
		 * Registration / auth gate before {@link OLLMrpc.Request.dispatch}.
		 *
		 * Return ''false'' when the request was already answered (rejected).
		 * Default allows all. Override in a subclass (e.g. ollmfilesd Https).
		 *
		 * @param reply HTTP reply for this POST (fingerprint / IP filled)
		 * @param request parsed request about to dispatch
		 * @return true to dispatch, false if already rejected
		 */
		protected virtual bool allow_rpc(HttpReply reply, OLLMrpc.Request request)
		{
			return true;
		}

		/**
		 * Bind host for {@link start}. Empty → {@link Soup.Server.listen_local}.
		 */
		public string host { get; set; default = ""; }

		/**
		 * Expect PROXY Protocol v1 on each inbound TCP connection before TLS.
		 */
		public bool proxy { get; set; default = false; }

		/**
		 * Client IPs to drop on accept (flood ban). Small list; checked
		 * before {@link Soup.Server.accept_iostream}.
		 */
		public Gee.ArrayList<string> banned_ips {
			get; set; default = new Gee.ArrayList<string>();
		}

		private Soup.Server soup { get; set; default = new Soup.Server("server-header", null); }
		private bool listening = false;
		private Bin.Json json { get; set; default = new Bin.Json(Bin.Mode.AUTO); }
		private GLib.SocketService? proxy_service = null;

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
			var opts = (Soup.ServerListenOptions) 0;
			if (this.tls_certificate != null) {
				this.soup.set_tls_certificate(this.tls_certificate);
				this.soup.set_tls_auth_mode(GLib.TlsAuthenticationMode.REQUESTED);
				opts = Soup.ServerListenOptions.HTTPS;
			}
			this.soup.request_started.connect((server, msg) => {
				msg.accept_certificate.connect((peer_cert, errors) => {
					msg.set_data("ollmrpc-peer-cert", peer_cert);
					return true;
				});
			});
			this.proxy_service = new GLib.SocketService();
			GLib.SocketAddress effective;
			try {
				this.proxy_service.add_address(
					new GLib.InetSocketAddress.from_string(
						this.host != "" ? this.host : "127.0.0.1", this.port),
					GLib.SocketType.STREAM, GLib.SocketProtocol.TCP, null, out effective);
			} catch (GLib.Error e) {
				GLib.warning("failed to start HTTP server on port %u: %s", this.port, e.message);
				return false;
			}
			var bound = effective as GLib.InetSocketAddress;
			if (bound != null) {
				this.port = bound.get_port();
			}
			this.proxy_service.incoming.connect((connection, source_object) => {
				var src_ip = "";
				var src_port = (uint) 0;
				if (this.proxy) {
					var accum = new GLib.ByteArray();
					var one = new uint8[1];
					try {
						var input = connection.get_input_stream();
						while (accum.len < 128) {
							if (input.read(one) <= 0) {
								break;
							}
							accum.append(one);
							if (accum.len >= 2 && accum.data[accum.len - 2] == '\r'
								&& accum.data[accum.len - 1] == '\n') {
								break;
							}
						}
					} catch (GLib.Error e) {
						GLib.warning("proxy accept failed: %s", e.message);
						return true;
					}
					var line = ((string) accum.data).chomp();
					if (line.has_prefix("PROXY ")) {
						var parts = line.split(" ");
						if (parts.length >= 5) {
							src_ip = parts[2];
							uint.try_parse(parts[4], out src_port);
						}
					}
				}
				if (!this.proxy) {
					try {
						var peer = connection.get_remote_address() as GLib.InetSocketAddress;
						if (peer != null) {
							src_ip = peer.get_address().to_string();
							src_port = peer.get_port();
						}
					} catch (GLib.Error e) {
					}
				}
				if (src_ip != "" && this.banned_ips.contains(src_ip)) {
					GLib.debug("dropping banned client IP %s", src_ip);
					try {
						connection.close();
					} catch (GLib.Error e) {
					}
					return true;
				}
				GLib.SocketAddress? remote = null;
				if (src_ip != "") {
					remote = new GLib.InetSocketAddress.from_string(src_ip, src_port);
				}
				GLib.SocketAddress? local = null;
				try {
					local = connection.get_local_address();
				} catch (GLib.Error e) {
				}
				if (this.tls_certificate == null) {
					try {
						this.soup.accept_iostream(connection, local, remote);
					} catch (GLib.Error e) {
						GLib.warning("proxy accept failed: %s", e.message);
					}
					return true;
				}
				GLib.TlsServerConnection tls;
				try {
					tls = GLib.TlsServerConnection.@new(
						connection, this.tls_certificate);
				} catch (GLib.Error e) {
					GLib.warning("proxy accept failed: %s", e.message);
					return true;
				}
				tls.authentication_mode = GLib.TlsAuthenticationMode.REQUESTED;
				tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
				tls.handshake_async.begin(
					GLib.Priority.DEFAULT, null, (obj, res) => {
					try {
						tls.handshake_async.end(res);
					} catch (GLib.Error e) {
						GLib.warning("tls handshake failed: %s", e.message);
						return;
					}
					GLib.debug("tls handshake peer cert %s",
						tls.peer_certificate != null ? "present" : "missing");
					if (tls.peer_certificate != null) {
						connection.socket.set_data("ollmrpc-peer-cert", tls.peer_certificate);
						if (remote != null) {
							remote.set_data("ollmrpc-peer-cert", tls.peer_certificate);
						}
					}
					try {
						this.soup.accept_iostream(tls, local, remote);
					} catch (GLib.Error e) {
						GLib.warning("proxy accept failed: %s", e.message);
					}
				});
				return true;
			});
			this.proxy_service.start();
			this.listening = true;
			return true;
		}

		public override void stop()
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			if (this.proxy_service != null) {
				this.proxy_service.stop();
				this.proxy_service = null;
			}
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
			var reply = new HttpReply(this.soup, msg, new Session()) {
				live_handles = this.live_handles
			};
			var peer = msg.get_tls_peer_certificate();
			if (peer == null) {
				peer = msg.get_data<GLib.TlsCertificate>("ollmrpc-peer-cert");
			}
			if (peer == null && msg.get_socket() != null) {
				peer = msg.get_socket().get_data<GLib.TlsCertificate>("ollmrpc-peer-cert");
			}
			if (peer == null && msg.get_remote_address() != null) {
				peer = msg.get_remote_address().get_data<GLib.TlsCertificate>("ollmrpc-peer-cert");
			}
			if (peer != null) {
				var der = peer.certificate;
				reply.cert_fingerprint = GLib.Checksum.compute_for_data(GLib.ChecksumType.SHA256, der.data);
			}
			GLib.debug("route peer fingerprint %s",	reply.cert_fingerprint != "" ? "set" : "empty");
			if (reply.client_ip == "") {
				var remote = msg.get_remote_address() as GLib.InetSocketAddress;
				if (remote != null) {
					reply.client_ip = remote.get_address().to_string();
				}
			}
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
			if (!this.allow_rpc(reply, request)) {
				return;
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
			var req_headers = msg.get_request_headers();
			var session_hdr = req_headers.get_one("X-rpc-session");
			if (session_hdr == null) {
				session_hdr = "";
			}
			var session = Session.take(session_hdr);
			if (session == null) {
				msg.set_status(409, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY,
					"unknown session".data);
				return;
			}
			var client_seq_hdr = req_headers.get_one("X-rpc-sequence");
			var client_seq = (int64) 0;
			if (client_seq_hdr != null && client_seq_hdr != "") {
				if (!int64.try_parse(client_seq_hdr, out client_seq)) {
					msg.set_status(409, null);
					msg.set_response("text/plain", Soup.MemoryUse.COPY,	"sequence mismatch".data);
					return;
				}
			}
			if (client_seq == -1) {
				session.bin = new Bin.Stream(null, null, true);
				session.sequence = 0;
			} else if (client_seq < 0
				|| client_seq > uint.MAX
				|| (uint) client_seq != session.sequence) {
				msg.set_status(409, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY, "sequence mismatch".data);
				return;
			}
			session.sequence++;
			var reply = new HttpReply(this.soup, msg, session) {
				live_handles = this.live_handles
			};
			var res_headers = msg.get_response_headers();
			res_headers.replace("X-rpc-session", session.id);
			res_headers.replace("X-rpc-sequence","%u".printf(session.sequence));
			var peer = msg.get_tls_peer_certificate();
			if (peer == null) {
				peer = msg.get_data<GLib.TlsCertificate>("ollmrpc-peer-cert");
			}
			if (peer == null && msg.get_socket() != null) {
				peer = msg.get_socket().get_data<GLib.TlsCertificate>("ollmrpc-peer-cert");
			}
			if (peer == null && msg.get_remote_address() != null) {
				peer = msg.get_remote_address().get_data<GLib.TlsCertificate>("ollmrpc-peer-cert");
			}
			if (peer != null) {
				var der = peer.certificate;
				reply.cert_fingerprint = GLib.Checksum.compute_for_data(
					GLib.ChecksumType.SHA256, der.data);
			}
			GLib.debug("rpc peer fingerprint %s",
				reply.cert_fingerprint != "" ? "set" : "empty");
			if (reply.client_ip == "") {
				var remote = msg.get_remote_address() as GLib.InetSocketAddress;
				if (remote != null) {
					reply.client_ip = remote.get_address().to_string();
				}
			}
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
			var content_type = msg.get_request_headers().get_one("Content-Type");
			if (content_type == null) {
				content_type = "";
			}
			OLLMrpc.Request request;
			if (content_type.has_prefix("application/octet-stream")) {
				reply.bin_body = true;
				var bytes = msg.get_request_body().flatten();
				reply.session.bin.in_stream = new GLib.DataInputStream(
					new GLib.MemoryInputStream.from_bytes(bytes)
				);
				reply.session.bin.in_stream.set_byte_order(
					GLib.DataStreamByteOrder.BIG_ENDIAN);
				reply.session.bin.mode = Bin.Mode.EXPLICIT;
				Bin.Serializable parsed;
				try {
					parsed = reply.session.bin.parse();
				} catch (GLib.Error e) {
					reply.write(new Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.PARSE_ERROR,
							"invalid bin: " + e.message
						)
					});
					msg.set_status(400, null);
					return;
				}
				reply.session.bin.in_stream = null;
				request = parsed as OLLMrpc.Request;
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
			} else {
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
				request = parsed as OLLMrpc.Request;
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
			}
			request.connection = reply;
			if (!this.allow_rpc(reply, request)) {
				return;
			}
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
