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
	 * Client for a held HTTP binary RPC stream.
	 *
	 * Peer to streaming {@link HttpReply} when {@link HttpReply.bin_body}
	 * is true. Keeps its own {@link Bin.Stream} so JIT wire-name tables
	 * stay isolated from unary {@link HttpClient} calls. Reads 4-byte
	 * length-framed {@link Bin.Serializable} objects asynchronously on the
	 * main loop without blocking.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var stream = new OLLMrpc.Transport.HttpStream("http://127.0.0.1:8071/events");
	 * stream.headers.set("Authorization", "Basic YWxhbjp4");
	 * stream.received.connect((obj) => {
	 *     var notif = obj as OLLMrpc.Notification;
	 *     if (notif != null) GLib.debug("event %s", notif.method);
	 * });
	 * stream.closed.connect((reason) => {
	 *     GLib.debug("stream closed: %s", reason);
	 * });
	 * stream.open.begin();
	 * }}}
	 */
	public class HttpStream : GLib.Object
	{
		/**
		 * Full stream URL, e.g. [[http://127.0.0.1:8071/events]].
		 */
		public string url { get; construct; }

		/**
		 * Extra HTTP request headers sent on {@link open} (e.g. ''Authorization''
		 * or ''Cookie'').
		 */
		public Gee.HashMap<string, string> headers {
			get; set; default = new Gee.HashMap<string, string>();
		}

		/**
		 * Trust store for a server installation's CA. Null uses the platform
		 * default.
		 */
		public GLib.TlsDatabase? tls_database { get; set; default = null; }

		/**
		 * Soup session used by {@link open}. Timeout stays 0 (no limit)
		 * so idle windows between server events do not drop the socket.
		 */
		public Soup.Session soup { get; private set; default = new Soup.Session(); }

		/**
		 * Isolated client JIT codec for this stream.
		 */
		public Bin.Stream bin {
			get; private set; default = new Bin.Stream(null, null, false);
		}

		/**
		 * True while {@link open} is connecting or reading frames.
		 */
		public bool active { get; private set; default = false; }

		/**
		 * Emitted for each decoded binary frame from the server.
		 *
		 * @param obj decoded wire object
		 */
		public signal void received(Bin.Serializable obj);

		/**
		 * Emitted once when the stream ends, fails, or is closed.
		 *
		 * @param reason short reason text (''eof'', ''closed'', or error)
		 */
		public signal void closed(string reason);

		private GLib.Cancellable cancellable = new GLib.Cancellable();

		/**
		 * Create a stream client for ''url''.
		 *
		 * @param url full HTTP or HTTPS stream URL
		 */
		public HttpStream(string url)
		{
			GLib.Object(url: url);
		}

		/**
		 * Connect to {@link url} and read binary frames until EOF, error, or
		 * {@link close}.
		 */
		public async void open()
		{
			if (this.active) {
				return;
			}
			this.active = true;
			this.bin = new Bin.Stream(null, null, false);
			this.bin.mode = Bin.Mode.EXPLICIT;
			this.cancellable = new GLib.Cancellable();
			var reason = "eof";
			var message = new Soup.Message("GET", this.url);
			if (this.tls_database != null) {
				this.soup.set_tls_database(this.tls_database);
				message.accept_certificate.connect((peer_cert, errors) => {
					return (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
				});
			}
			foreach (var key in this.headers.keys) {
				message.get_request_headers().replace(key, this.headers.get(key));
			}
			var input = (GLib.InputStream?) null;
			try {
				input = yield this.soup.send_async(message, GLib.Priority.DEFAULT, this.cancellable);
			} catch (GLib.Error e) {
				reason = this.cancellable.is_cancelled() ? "closed" : e.message;
				this.active = false;
				this.closed(reason);
				return;
			}
			if (message.status_code < 200 || message.status_code >= 300) {
				try {
					input.close(null);
				} catch (GLib.Error e) {
				}
				this.active = false;
				this.closed("HTTP %u".printf(message.status_code));
				return;
			}
			var hdr = new uint8[4];
			while (!this.cancellable.is_cancelled()) {
				var got = (size_t) 0;
				try {
					yield input.read_all_async(hdr, GLib.Priority.DEFAULT, this.cancellable, out got);
				} catch (GLib.Error e) {
					reason = this.cancellable.is_cancelled() ? "closed" : e.message;
					break;
				}
				if (got == 0) {
					reason = "eof";
					break;
				}
				if (got < 4) {
					reason = "truncated header";
					break;
				}
				var hdr_in = new GLib.DataInputStream(new GLib.MemoryInputStream.from_data(hdr));
				hdr_in.set_byte_order(GLib.DataStreamByteOrder.BIG_ENDIAN);
				var frame_len = (uint32) 0;
				try {
					frame_len = hdr_in.read_uint32();
				} catch (GLib.Error e) {
					reason = e.message;
					break;
				}
				if (frame_len == 0 || frame_len > 16 * 1024 * 1024) {
					reason = "invalid frame size %u".printf(frame_len);
					break;
				}
				var payload = new uint8[frame_len];
				var body_got = (size_t) 0;
				try {
					yield input.read_all_async(payload, GLib.Priority.DEFAULT, this.cancellable, out body_got);
				} catch (GLib.Error e) {
					reason = this.cancellable.is_cancelled() ? "closed" : e.message;
					break;
				}
				if (body_got < frame_len) {
					reason = "truncated frame";
					break;
				}
				this.bin.in_stream = new GLib.DataInputStream(new GLib.MemoryInputStream.from_data(payload));
				this.bin.in_stream.set_byte_order(GLib.DataStreamByteOrder.BIG_ENDIAN);
				var parsed = (Bin.Serializable?) null;
				try {
					parsed = this.bin.parse();
				} catch (GLib.Error e) {
					this.bin.in_stream = null;
					reason = e.message;
					break;
				}
				this.bin.in_stream = null;
				this.received(parsed);
			}
			if (this.cancellable.is_cancelled()) {
				reason = "closed";
			}
			try {
				input.close(null);
			} catch (GLib.Error e) {
			}
			this.active = false;
			this.closed(reason);
		}

		/**
		 * Cancel the open stream and close the connection.
		 */
		public void close()
		{
			this.cancellable.cancel();
		}
	}
}
