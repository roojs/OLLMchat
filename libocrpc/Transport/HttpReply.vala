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
	 * ''GLib.OutputStream'' that appends into a Soup response body.
	 *
	 * Lets {@link Bin.Stream} write HTTP chunked octets without buffering
	 * the whole reply in a {@link GLib.MemoryOutputStream}.
	 */
	private class BodyStream : GLib.OutputStream
	{
		public Soup.MessageBody body { get; construct; }

		public BodyStream(Soup.MessageBody body)
		{
			GLib.Object(body: body);
		}

		public override ssize_t write(
			uint8[] buffer,
			GLib.Cancellable? cancellable = null
		) throws GLib.IOError
		{
			this.body.append(Soup.MemoryUse.COPY, buffer);
			return (ssize_t) buffer.length;
		}

		public override bool close(GLib.Cancellable? cancellable = null) throws GLib.IOError
		{
			return true;
		}
	}

	/**
	 * Server-side write target for one HTTP POST.
	 *
	 * Subclasses {@link Connection} so {@link OLLMrpc.Request.reply}
	 * can call {@link write}. The RPC payload is still an
	 * {@link OLLMrpc.Response} (or {@link Notification}); this type only
	 * holds the {@link Soup.ServerMessage} and encodes JSON or bin into it.
	 * First {@link Notification} opens NDJSON streaming; a final
	 * {@link Response} finishes the stream. Shared JIT tables come from
	 * {@link session}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var session = OLLMrpc.Transport.Session.take("");
	 * var reply = new OLLMrpc.Transport.HttpReply(soup, msg, session);
	 * request.connection = reply;
	 * request.dispatch();
	 * }}}
	 */
	public class HttpReply : Connection
	{
		/**
		 * Shared HTTP session (bin name tables + id). Not used for leases.
		 */
		public Session session { get; construct; }

		/**
		 * Owning Soup server (unpause when a streamed {@link Response} finishes).
		 */
		public Soup.Server soup { get; construct; }

		/**
		 * Soup message for this POST (request body already read; response filled by {@link write}).
		 */
		public Soup.ServerMessage msg { get; construct; }

		/**
		 * True after the first non-{@link Response} write opened NDJSON chunked output.
		 */
		public bool streaming = false;

		/**
		 * True after unary {@link Response} or final streamed {@link Response}.
		 */
		public bool finished = false;

		/**
		 * True after {@link Soup.Server.pause_message} until final {@link Response}.
		 */
		public bool paused = false;

		/**
		 * True when the POST used ''application/octet-stream'' (bin reply).
		 */
		public bool bin_body { get; set; default = false; }

		/**
		 * Client address for pending registration (PROXY-sourced when
		 * ''filesd.proxy'', else TCP peer). Empty when unknown.
		 */
		public string client_ip { get; set; default = ""; }

		/**
		 * SHA-256 hex of the TLS peer cert DER. Empty when no client cert.
		 */
		public string cert_fingerprint { get; set; default = ""; }

		/**
		 * Emitted when the underlying HTTP message finishes or the peer
		 * disconnects.
		 */
		public signal void closed();

		private Bin.Json json { get; set; default = new Bin.Json(Bin.Mode.AUTO); }
		private GLib.SocketSource? peer_watch = null;

		public HttpReply(Soup.Server soup, Soup.ServerMessage msg, Session session)
		{
			GLib.Object(soup: soup, msg: msg, session: session);
			this.bin = this.session.bin;
			this.bin.connection = this;
			this.msg.set_data("ollmrpc-http-reply", this);
			this.msg.finished.connect(() => {
				if (this.peer_watch != null) {
					this.peer_watch.destroy();
					this.peer_watch = null;
				}
				this.finished = true;
				this.closed();
				this.msg.set_data<HttpReply?>("ollmrpc-http-reply", null);
			});
		}

		public override void start()
		{
		}

		public override void write(GLib.Object gobject, Live.Buffer? buffer = null)
		{
			if (this.finished) {
				GLib.warning("http write after finish");
				return;
			}
			var serializable = gobject as Bin.Serializable;
			if (serializable == null) {
				GLib.warning("http write: not bin Serializable");
				if (!this.streaming) {
					this.msg.set_response("text/plain; charset=utf-8", Soup.MemoryUse.COPY,
						"http write: not bin Serializable".data);
					this.msg.set_status(500, null);
					this.finished = true;
					if (this.paused) {
						this.soup.unpause_message(this.msg);
						this.paused = false;
					}
				}
				return;
			}
			if (this.bin_body && !this.streaming && serializable is Response) {
				this.msg.set_status(200, null);
				this.msg.get_response_headers().set_content_type("application/octet-stream", null);
				this.msg.get_response_headers().set_encoding(Soup.Encoding.CHUNKED);
				this.bin.out_stream = new GLib.DataOutputStream(new BodyStream(this.msg.get_response_body()));
				this.bin.out_stream.set_byte_order(GLib.DataStreamByteOrder.BIG_ENDIAN);
				try {
					this.bin.write(serializable);
					this.bin.out_stream.close();
				} catch (GLib.Error e) {
					this.bin.out_stream = null;
					GLib.warning("http write error: %s", e.message);
					this.msg.set_response("text/plain; charset=utf-8", Soup.MemoryUse.COPY,
						("encode failed: " + e.message).data);
					this.msg.set_status(500, null);
					this.finished = true;
					if (this.paused) {
						this.soup.unpause_message(this.msg);
						this.paused = false;
					}
					return;
				}
				this.bin.out_stream = null;
				this.msg.get_response_body().complete();
				this.finished = true;
				if (this.paused) {
					this.soup.unpause_message(this.msg);
					this.paused = false;
				}
				return;
			}
			if (this.bin_body) {
				var mem = new GLib.MemoryOutputStream.resizable();
				this.bin.out_stream = new GLib.DataOutputStream(mem);
				this.bin.out_stream.set_byte_order(GLib.DataStreamByteOrder.BIG_ENDIAN);
				this.bin.mode = Bin.Mode.EXPLICIT;
				try {
					this.bin.out_stream.put_uint32(0);
					this.bin.write(serializable);
					mem.seek(0, GLib.SeekType.SET);
					this.bin.out_stream.put_uint32((uint32) (mem.get_data_size() - 4));
					this.bin.out_stream.close();
				} catch (GLib.Error e) {
					this.bin.out_stream = null;
					GLib.warning("http write error: %s", e.message);
					if (!this.streaming) {
						this.msg.set_response("text/plain; charset=utf-8", Soup.MemoryUse.COPY,
							("encode failed: " + e.message).data);
						this.msg.set_status(500, null);
						this.finished = true;
						if (this.paused) {
							this.soup.unpause_message(this.msg);
							this.paused = false;
						}
					}
					return;
				}
				this.bin.out_stream = null;
				if (!this.streaming) {
					this.streaming = true;
					this.msg.set_status(200, null);
					this.msg.get_response_headers().set_content_type("application/octet-stream", null);
					this.msg.get_response_headers().replace("Cache-Control", "no-cache");
					this.msg.get_response_headers().replace("X-Accel-Buffering", "no");
					this.msg.get_response_headers().set_encoding(Soup.Encoding.CHUNKED);
					var sock = this.msg.get_socket();
					if (sock == null && this.msg.get_remote_address() != null) {
						sock = this.msg.get_remote_address().get_data<GLib.Socket>("ollmrpc-peer-socket");
					}
					if (sock != null) {
						this.peer_watch = sock.create_source(GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR);
						this.peer_watch.set_callback((s, cond) => {
							this.peer_watch = null;
							if (!this.finished) {
								this.msg.get_response_body().complete();
								this.soup.unpause_message(this.msg);
							}
							return false;
						});
						this.peer_watch.attach(null);
					}
				}
				this.msg.get_response_body().append_bytes(mem.steal_as_bytes());
				if (serializable is Response) {
					this.finished = true;
					this.msg.get_response_body().complete();
				}
				if (this.paused) {
					this.soup.unpause_message(this.msg);
					if (this.finished) {
						this.paused = false;
					}
				}
				if (!this.paused && !this.finished) {
					GLib.Idle.add(() => {
						if (!this.finished && this.paused) {
							this.soup.unpause_message(this.msg);
						}
						return false;
					});
				}
				return;
			}
			var json_text = "";
			try {
				json_text = global::Json.to_string(this.json.from_gobject(serializable), false);
			} catch (GLib.Error e) {
				GLib.warning("http write error: %s", e.message);
				if (!this.streaming) {
					this.msg.set_response("text/plain; charset=utf-8", Soup.MemoryUse.COPY,
						("encode failed: " + e.message).data);
					this.msg.set_status(500, null);
					this.finished = true;
					if (this.paused) {
						this.soup.unpause_message(this.msg);
						this.paused = false;
					}
				}
				return;
			}
			if (!this.streaming && serializable is Response) {
				this.msg.set_response("application/json; charset=utf-8", Soup.MemoryUse.COPY, json_text.data);
				this.msg.set_status(200, null);
				this.finished = true;
				if (this.paused) {
					this.soup.unpause_message(this.msg);
					this.paused = false;
				}
				return;
			}
			if (!this.streaming) {
				this.streaming = true;
				this.msg.set_status(200, null);
				this.msg.get_response_headers().set_content_type("application/x-ndjson", null);
				this.msg.get_response_headers().set_encoding(Soup.Encoding.CHUNKED);
			}
			this.msg.get_response_body().append(Soup.MemoryUse.COPY, (json_text + "\n").data);
			if (serializable is Response) {
				this.finished = true;
				this.msg.get_response_body().complete();
				if (this.paused) {
					this.soup.unpause_message(this.msg);
					this.paused = false;
				}
			}
		}
	}
}
