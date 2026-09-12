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
	 * HTTP RPC client — POST JSON or bin + session headers.
	 *
	 * Peer to {@link HttpServer}. Not {@link OLLMrpc.Client} (that type owns
	 * socket/TCP and Hub GET). One instance keeps ''X-rpc-session'' /
	 * ''X-rpc-sequence'' across {@link call}s. Set {@link bin_body} for
	 * octet-stream (JIT name tables on {@link bin}); leave false for JSON.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var http = new OLLMrpc.Transport.HttpClient("http://127.0.0.1:8080");
	 * var resp = yield http.call(new OLLMrpc.Request() {
	 *     method = "RPC-Hello.world"
	 * });
	 * http.bin_body = true;
	 * var bin_resp = yield http.call(new OLLMrpc.Request() {
	 *     method = "RPC-Hello.world"
	 * });
	 * }}}
	 */
	public class HttpClient : GLib.Object
	{
		/** Base origin (no path), e.g. ''http://127.0.0.1:8080''. */
		public string base_url { get; construct; }

		/** RPC path under {@link base_url}. Default ''/rpc''. */
		public string rpc_path { get; set; default = "/rpc"; }

		/**
		 * True → ''application/octet-stream'' (bin). False → JSON
		 * (default), matching server {@link HttpReply.bin_body}.
		 */
		public bool bin_body { get; set; default = false; }

		/** Last echoed ''X-rpc-session''; empty before first success. */
		public string session_id { get; set; default = ""; }

		/**
		 * Last echoed ''X-rpc-sequence''. Sent on the next {@link call}
		 * unless {@link reset} armed ''-1''.
		 */
		public uint sequence { get; set; default = 0; }

		/**
		 * Client JIT codec (even wire tokens). Used when {@link bin_body}.
		 * I/O streams attached per {@link call}.
		 */
		public Bin.Stream bin {
			get; set; default = new Bin.Stream(null, null, false);
		}

		private Soup.Session soup = new Soup.Session();
		private Bin.Json json = new Bin.Json(Bin.Mode.AUTO);
		private int next_id = 1;
		private bool send_reset = false;

		public HttpClient(string base_url)
		{
			GLib.Object(base_url: base_url);
		}

		/**
		 * Arm sequence ''-1'' on the next {@link call} and replace
		 * {@link bin} with a fresh client stream.
		 */
		public void reset()
		{
			this.bin = new Bin.Stream(null, null, false);
			this.send_reset = true;
		}

		/**
		 * POST one {@link OLLMrpc.Request} (JSON or bin per {@link bin_body}).
		 *
		 * @param request wire request; {@link OLLMrpc.Request.id} set here
		 * @return decoded {@link OLLMrpc.Response}
		 * @throws GLib.Error HTTP non-2xx or encode/parse failure
		 */
		public async Response call(Request request) throws GLib.Error
		{
			request.id = this.next_id++;
			var url = this.base_url + this.rpc_path;
			var message = new Soup.Message("POST", url);
			var req_headers = message.get_request_headers();
			if (this.session_id != "") {
				req_headers.replace("X-rpc-session", this.session_id);
			}
			if (this.send_reset) {
				req_headers.replace("X-rpc-sequence", "-1");
			} else {
				req_headers.replace("X-rpc-sequence",
					"%u".printf(this.sequence));
			}
			var bytes = (GLib.Bytes?) null;
			if (this.bin_body) {
				var fds = new int[2];
				if (Posix.pipe(fds) != 0) {
					throw new GLib.IOError.FAILED("pipe failed");
				}
				var unix_in = new GLib.UnixInputStream(fds[0], true);
				var unix_out = new GLib.UnixOutputStream(fds[1], true);
				message.set_request_body(
					"application/octet-stream", unix_in, -1);
				/* Start Soup before filling the pipe — avoid deadlock. */
				var send_res = (GLib.AsyncResult?) null;
				SourceFunc resume = call.callback;
				this.soup.send_and_read_async.begin(
					message, GLib.Priority.DEFAULT, null,
					(obj, res) => {
						send_res = res;
						resume();
					}
				);
				this.bin.out_stream = new GLib.DataOutputStream(unix_out);
				this.bin.out_stream.set_byte_order(
					GLib.DataStreamByteOrder.BIG_ENDIAN);
				this.bin.mode = Bin.Mode.EXPLICIT;
				try {
					this.bin.write(request);
					this.bin.out_stream.close();
				} finally {
					this.bin.out_stream = null;
				}
				yield;
				bytes = this.soup.send_and_read_async.end(send_res);
			} else {
				var json_text = global::Json.to_string(
					this.json.from_gobject(request), false
				);
				message.set_request_body(
					"application/json; charset=utf-8",
					new GLib.MemoryInputStream.from_data(
						json_text.data, null),
					json_text.data.length
				);
				bytes = yield this.soup.send_and_read_async(
					message, GLib.Priority.DEFAULT, null);
			}
			if (message.status_code < 200 || message.status_code >= 300) {
				var body_text = "";
				if (bytes != null) {
					body_text = ((string) bytes.get_data()).strip();
				}
				throw new GLib.IOError.FAILED("HTTP %u for %s: %s",
					message.status_code, url, body_text);
			}
			var res_headers = message.get_response_headers();
			var sid = res_headers.get_one("X-rpc-session");
			if (sid != null && sid != "") {
				this.session_id = sid;
			}
			var seq_hdr = res_headers.get_one("X-rpc-sequence");
			if (seq_hdr != null && seq_hdr != "") {
				var parsed_seq = (uint64) 0;
				if (uint64.try_parse(seq_hdr, out parsed_seq)
					&& parsed_seq <= uint.MAX) {
					this.sequence = (uint) parsed_seq;
				}
			}
			this.send_reset = false;
			var response = (Response?) null;
			if (this.bin_body) {
				this.bin.in_stream = new GLib.DataInputStream(
					new GLib.MemoryInputStream.from_bytes(bytes)
				);
				this.bin.in_stream.set_byte_order(
					GLib.DataStreamByteOrder.BIG_ENDIAN);
				var parsed = (Bin.Serializable?) null;
				try {
					parsed = this.bin.parse();
				} finally {
					this.bin.in_stream = null;
				}
				response = parsed as Response;
				if (response == null) {
					throw new Bin.StreamError.PROTOCOL(
						"HTTP bin body did not decode to a Response");
				}
			} else {
				var parser = new Json.Parser();
				parser.load_from_data(
					(string) bytes.get_data(), (ssize_t) bytes.get_size());
				var root = parser.get_root();
				if (root == null
					|| root.get_node_type() != Json.NodeType.OBJECT) {
					throw new Bin.StreamError.PROTOCOL(
						"HTTP JSON root must be an object");
				}
				var mem = new GLib.MemoryOutputStream.resizable();
				var encode_ctx = new Bin.Stream(
					null, new GLib.DataOutputStream(mem));
				this.json.json_to_bin(
					root.get_object(), encode_ctx, typeof(Response));
				encode_ctx.out_stream.close();
				var read_ctx = new Bin.Stream(
					new GLib.DataInputStream(
						new GLib.MemoryInputStream.from_bytes(
							mem.steal_as_bytes())
					),
					null
				);
				read_ctx.mode = this.json.mode;
				var parsed = read_ctx.parse();
				response = parsed as Response;
				if (response == null) {
					throw new Bin.StreamError.PROTOCOL(
						"HTTP JSON body did not decode to a Response");
				}
			}
			if (response.error != null) {
				GLib.warning("%s id=%d: %s",
					request.method, request.id, response.error.message);
				var quark = GLib.Quark.from_string(response.error.domain);
				var code = response.error.gerror_code;
				if (response.error.domain == "") {
					quark = new RpcErrorCode.INTERNAL_ERROR("").domain;
					code = response.error.code;
				}
				throw new GLib.Error.literal(
					quark, code, response.error.message);
			}
			return response;
		}
	}
}
