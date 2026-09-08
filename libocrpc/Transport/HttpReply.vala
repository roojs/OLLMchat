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
	 * Server-side write target for one HTTP POST.
	 *
	 * Subclasses {@link Connection} so {@link OLLMrpc.Request.reply}
	 * can call {@link write}. The RPC payload is still an
	 * {@link OLLMrpc.Response} (or {@link Notification}); this type only
	 * holds the {@link Soup.ServerMessage} and encodes JSON into it.
	 * First {@link Notification} opens NDJSON streaming; a final
	 * {@link Response} finishes the stream.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var reply = new OLLMrpc.Transport.HttpReply(soup, msg);
	 * request.connection = reply;
	 * request.dispatch();
	 * }}}
	 */
	public class HttpReply : Connection
	{
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

		private Bin.Json json = new Bin.Json(Bin.Mode.AUTO);

		public HttpReply(Soup.Server soup, Soup.ServerMessage msg)
		{
			GLib.Object(soup: soup, msg: msg);
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
						"application/x-ndjson", null
					);
					this.msg.get_response_headers().set_encoding(
						Soup.Encoding.CHUNKED
					);
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
