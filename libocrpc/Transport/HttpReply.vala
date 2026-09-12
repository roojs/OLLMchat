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

		private Bin.Json json = new Bin.Json(Bin.Mode.AUTO);

		public HttpReply(Soup.Server soup, Soup.ServerMessage msg, Session session)
		{
			GLib.Object(soup: soup, msg: msg, session: session);
			this.bin = this.session.bin;
			this.bin.connection = this;
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
					this.msg.set_response(
						"text/plain; charset=utf-8",
						Soup.MemoryUse.COPY,
						"http write: not bin Serializable".data
					);
					this.msg.set_status(500, null);
					this.finished = true;
				}
				return;
			}
			try {
				if (this.bin_body && !this.streaming && serializable is Response) {
					this.msg.set_status(200, null);
					this.msg.get_response_headers().set_content_type(
						"application/octet-stream", null);
					this.msg.get_response_headers().set_encoding(
						Soup.Encoding.CHUNKED);
					this.bin.out_stream = new GLib.DataOutputStream(
						new BodyStream(this.msg.get_response_body())
					);
					this.bin.out_stream.set_byte_order(
						GLib.DataStreamByteOrder.BIG_ENDIAN);
					this.bin.write(serializable);
					this.bin.out_stream.close();
					this.bin.out_stream = null;
					this.msg.get_response_body().complete();
					this.finished = true;
					return;
				}
				var json_text = global::Json.to_string(
					this.json.from_gobject(serializable), false
				);
				if (!this.streaming && serializable is Response) {
					this.msg.set_response(
						"application/json; charset=utf-8",
						Soup.MemoryUse.COPY,
						json_text.data
					);
					this.msg.set_status(200, null);
					this.finished = true;
					return;
				}
				if (!this.streaming) {
					this.streaming = true;
					this.msg.set_status(200, null);
					this.msg.get_response_headers().set_content_type(
						"application/x-ndjson", null);
					this.msg.get_response_headers().set_encoding(
						Soup.Encoding.CHUNKED);
				}
				this.msg.get_response_body().append(
					Soup.MemoryUse.COPY,
					(json_text + "\n").data
				);
				if (serializable is Response) {
					this.finished = true;
					this.msg.get_response_body().complete();
					if (this.paused) {
						this.soup.unpause_message(this.msg);
						this.paused = false;
					}
				}
			} catch (GLib.Error e) {
				GLib.warning("http write error: %s", e.message);
				if (!this.streaming) {
					this.msg.set_response(
						"text/plain; charset=utf-8",
						Soup.MemoryUse.COPY,
						("encode failed: " + e.message).data
					);
					this.msg.set_status(500, null);
					this.finished = true;
				}
			}
		}
	}
}
