# HTTP binary streaming and request headers in libocrpc

**Status:** ✔️

## User decisions required

None.

## User reported

- 🔷 Finch Phase 6 needs a held HTTP event stream (`GET /events`) that carries `OLLMrpc` binary RPC objects (ready, 1-minute ping, and desktop file events) instead of custom SSE text.
- 🔷 Finch also enforces HTTP Basic Auth on every request (`POST /rpc`, `GET /events`, `GET /file/{id}`), so `HttpClient` must send preemptive request headers (`Authorization` now, `Cookie` later for Cloudflare).
- 🔷 Propose this report in `OLLMchat` first before changing `libocrpc`.

## Success scenario

- A server route handler (such as `GET /events`) can set `reply.bin_body = true` and call `reply.write(obj)` repeatedly over time while the HTTP connection stays open.
- Each written `Bin.Serializable` object is flushed immediately to the peer as a length-framed binary chunk on `application/octet-stream` without ending the HTTP response.
- JIT wire-name tables persist across frames on that stream and do not collide with unary `POST /rpc` sessions.
- When the client disconnects or aborts, `HttpReply.closed` fires so the server removes the dead watch.
- A client using `OLLMrpc.Transport.HttpStream` opens the stream via `Soup.Session.send_async`, receives each `Bin.Serializable` object asynchronously on the main loop without blocking, and emits `closed` on EOF, error, or `close()`.
- `OLLMrpc.Transport.HttpClient` and `OLLMrpc.Transport.HttpStream` send custom `headers` (e.g. `Authorization`, `Cookie`) preemptively on every request.
- Existing unary binary `POST /rpc` (`HttpClient.call` + `HttpReply.write` for `Response`) and JSON NDJSON streaming remain unchanged.
- `HttpStream` compiles on Linux, Windows, and Android (GLib/Soup only, no Unix-only stream APIs).
- New RPC test `test-rpc-http-stream` passes under `meson test -C build --suite rpc`, alongside existing HTTP RPC tests and `ninja -C build docs/valadoc`.

## Current behavior

- What you said
  - Finch Phase 6 wants to send binary `OLLMrpc` objects over a held HTTP connection (`GET /events`) and reject unauthenticated requests on `POST /rpc`.
- Observable
  - `HttpReply.write` only encodes binary for a single unary `Response`, then closes the HTTP response body.
  - Writing a non-`Response` `Bin.Serializable` (such as `Notification` or a custom event) ignores `bin_body` and falls through to JSON `application/x-ndjson`.
  - Writing a follow-up event after `HttpServer` has paused the message does not unpause the `Soup.ServerMessage`, so chunks are not flushed onto the wire.
  - `HttpClient.call` uses `Soup.Session.send_and_read_async`, which waits for EOF before parsing a single `Response`.
  - `HttpClient` has no custom request header property for preemptive `Authorization` or `Cookie` headers.

## Codebase observed behavior

- [`libocrpc/Transport/HttpReply.vala`](../../libocrpc/Transport/HttpReply.vala) `write()`
  - Only checks `this.bin_body` when `!this.streaming && serializable is Response`, then completes the body and unpauses.
  - All other writes fall through to JSON `application/x-ndjson` and never unpause mid-stream.

```vala
if (this.bin_body && !this.streaming && serializable is Response) {
	this.msg.set_status(200, null);
	this.msg.get_response_headers().set_content_type("application/octet-stream", null);
	…
	this.msg.get_response_body().complete();
	this.finished = true;
	…
	return;
}
var json_text = global::Json.to_string(this.json.from_gobject(serializable), false);
```

- [`libocrpc/Transport/HttpReply.vala`](../../libocrpc/Transport/HttpReply.vala) constructor does not connect to `Soup.ServerMessage.finished`, so route handlers holding an open `HttpReply` have no signal when the client drops the socket.
- [`libocrpc/Transport/HttpServer.vala`](../../libocrpc/Transport/HttpServer.vala) `on_route()` already gives each route request its own `new Session()` (isolating its `Bin.Stream` JIT tables from `/rpc`) and pauses the message when `!reply.finished`.

```vala
var reply = new HttpReply(this.soup, msg, new Session()) {
	live_handles = this.live_handles
};
…
if (!reply.finished) {
	reply.paused = true;
	this.soup.pause_message(msg);
}
```

- [`libocrpc/Transport/HttpClient.vala`](../../libocrpc/Transport/HttpClient.vala) `call()` sends only `X-rpc-session` and `X-rpc-sequence` request headers, streams `bin_body` requests through a non-seekable pipe (`pipe_in`, length `-1`), and reads the whole response with `send_and_read_async`.

```vala
var req_headers = message.get_request_headers();
if (this.session_id != "") {
	req_headers.replace("X-rpc-session", this.session_id);
}
…
message.set_request_body("application/octet-stream", pipe_in, -1);
```

- [`libocrpc/Bin/Stream.vala`](../../libocrpc/Bin/Stream.vala) `parse()` uses synchronous `DataInputStream.read_byte()` and `read_all()`, so reading directly from a live Soup `GLib.InputStream` on the main loop would block until the next server event arrives.

## Debugging

### Current debug output

None yet.

### Debug code added (remove when complete)

None.

## Proposed fix

Edits are **Remove** / **Replace with** / **Add** from the tree (**Keep** is unchanged context); verify surrounding context before applying.

### ✔️ Phase 1 — `HttpReply` binary streaming and `closed` signal

- In [`libocrpc/Transport/HttpReply.vala`](../../libocrpc/Transport/HttpReply.vala) and [`libocrpc/Transport/HttpServer.vala`](../../libocrpc/Transport/HttpServer.vala):
  - Add a `closed` signal wired to `Soup.ServerMessage.finished` in the constructor, keeping a message-owned ref (`ollmrpc-http-reply`) until `finished` fires so `closed` still emits if the caller holds no external ref.
  - Attach `connection.socket` onto `remote` (`ollmrpc-peer-socket`) in `HttpServer` (`accept_iostream` leaves `msg.get_socket() == null`) and watch it with `GLib.SocketSource` (`IN | HUP | ERR`) while streaming so peer disconnects complete and unpause the Soup message immediately.
  - Handle streaming binary writes (`this.bin_body` after the unary `Response` check) by reserving a 4-byte big-endian length prefix via `GLib.DataOutputStream.put_uint32(0)` in a `GLib.MemoryOutputStream`, writing the object, seeking back to `0` to write the payload length, and appending the single framed `GLib.Bytes` chunk to `msg.get_response_body()`.
  - Unpause Soup so chunks flush immediately, including via `GLib.Idle.add` when the initial write runs inside `dispatch()` before `HttpServer` pauses the message.
  - Leave the existing unary `this.bin_body && !this.streaming && serializable is Response` path unchanged.

#### 1. `libocrpc/Transport/HttpReply.vala` — `closed` signal

**Why:** Route handlers holding an open streaming `HttpReply` need notification when the peer disconnects or the message finishes so they can clean up watches.

**Where:** `HttpReply` class body, after `cert_fingerprint` and before `private Bin.Json json`.

**Depends on:** none.

#### Keep

```vala
		/**
		 * SHA-256 hex of the TLS peer cert DER. Empty when no client cert.
		 */
		public string cert_fingerprint { get; set; default = ""; }
```

#### Add — Emit `closed` when the Soup message finishes or peer disconnects.

```vala
		/**
		 * Emitted when the underlying HTTP message finishes or the
		 * peer disconnects.
		 */
		public signal void closed();
```

#### Keep

```vala
		private Bin.Json json { get; set; default = new Bin.Json(Bin.Mode.AUTO); }
```

#### Add — Track the streaming peer socket watch so it is destroyed on finish.

```vala
		private GLib.SocketSource? peer_watch = null;
```

#### 2. `libocrpc/Transport/HttpReply.vala` — `HttpReply()` constructor

**Why:** Keep `HttpReply` alive until `Soup.ServerMessage.finished`, tear down any `peer_watch`, mark `this.finished = true`, and emit `this.closed()`.

**Where:** `HttpReply` constructor body (`libocrpc/Transport/HttpReply.vala`).

**Depends on:** Phase 1 §1 (`closed` signal).

#### Remove

```vala
		public HttpReply(Soup.Server soup, Soup.ServerMessage msg, Session session)
		{
			GLib.Object(soup: soup, msg: msg, session: session);
			this.bin = this.session.bin;
			this.bin.connection = this;
		}
```

#### Replace with — Keep `HttpReply` alive on `this.msg` until `finished`, clean up `peer_watch`, and emit `this.closed()`.

```vala
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
```

#### 3. `libocrpc/Transport/HttpReply.vala` — `write()` streaming binary branch

**Why:** Stream 4-byte length-framed `Bin.Serializable` objects over chunked `application/octet-stream` when `this.bin_body` is true and the write is not a unary `Response`, flushing each frame immediately without changing unary binary `Response` or JSON/NDJSON output.

**Where:** `HttpReply.write()`, inside the `try` block, immediately after the unary `if (this.bin_body && !this.streaming && serializable is Response)` block and before `var json_text = ...`.

**Depends on:** none.

#### Keep

```vala
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
					if (this.paused) {
						this.soup.unpause_message(this.msg);
						this.paused = false;
					}
					return;
				}
```

#### Add — Encode streaming binary frames with a 4-byte BE length header via `DataOutputStream.put_uint32` and unpause Soup to flush immediately.

```vala
				if (this.bin_body) {
					if (!this.streaming) {
						this.streaming = true;
						this.msg.set_status(200, null);
						this.msg.get_response_headers().set_content_type(
							"application/octet-stream", null);
						this.msg.get_response_headers().replace("Cache-Control", "no-cache");
						this.msg.get_response_headers().replace("X-Accel-Buffering", "no");
						this.msg.get_response_headers().set_encoding(
							Soup.Encoding.CHUNKED);
						var sock = this.msg.get_socket();
						if (sock == null && this.msg.get_remote_address() != null) {
							sock = this.msg.get_remote_address().get_data<GLib.Socket>(
								"ollmrpc-peer-socket");
						}
						if (sock != null) {
							this.peer_watch = sock.create_source(
								GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR);
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
					var mem = new GLib.MemoryOutputStream.resizable();
					this.bin.out_stream = new GLib.DataOutputStream(mem);
					this.bin.out_stream.set_byte_order(
						GLib.DataStreamByteOrder.BIG_ENDIAN);
					this.bin.mode = Bin.Mode.EXPLICIT;
					this.bin.out_stream.put_uint32(0);
					this.bin.write(serializable);
					mem.seek(0, GLib.SeekType.SET);
					this.bin.out_stream.put_uint32((uint32) (mem.get_data_size() - 4));
					this.bin.out_stream.close();
					this.bin.out_stream = null;
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
```

#### Keep

```vala
				var json_text = global::Json.to_string(
					this.json.from_gobject(serializable), false
				);
				if (!this.streaming && serializable is Response) {
```

#### 4. `libocrpc/Transport/HttpServer.vala` — attach peer socket on `remote`

**Why:** `Soup.Server.accept_iostream()` leaves `Soup.ServerMessage.get_socket()` null, so attach `connection.socket` to `remote` (same pattern as `ollmrpc-peer-cert`) for streaming disconnect detection in `HttpReply`.

**Where:** `HttpServer.start()` (`incoming` handler) and `HttpServer.take()`, immediately before `accept_iostream()`.

**Depends on:** none.

#### Keep

```vala
				GLib.SocketAddress? remote = null;
				if (src_ip != "") {
					remote = new GLib.InetSocketAddress.from_string(src_ip, src_port);
```

#### Add — Store `connection.socket` on `remote` in `start()` (`incoming`).

```vala
					remote.set_data("ollmrpc-peer-socket", connection.socket);
```

#### Keep

```vala
				}
```

#### Keep

```vala
			var aborted = this.soup.request_aborted.connect((msg) => {
				loop.quit();
			});
```

#### Add — Store `connection.socket` on `remote` in `take()`.

```vala
			if (remote != null && connection is GLib.SocketConnection) {
				remote.set_data("ollmrpc-peer-socket", ((GLib.SocketConnection) connection).socket);
			}
```

#### Keep

```vala
			try {
				this.soup.accept_iostream(connection, local, remote);
```

### ✔️ Phase 2 — Preemptive `headers` on `HttpClient`

- In [`libocrpc/Transport/HttpClient.vala`](../../libocrpc/Transport/HttpClient.vala):
  - Add a `headers` map copied onto every outgoing `Soup.Message` before sending.
  - Preemptive headers are required for `Authorization` and future `Cookie` headers because `bin_body` pipe requests cannot be replayed after a 401 challenge.

#### 1. `libocrpc/Transport/HttpClient.vala` — `headers` property

**Why:** Let callers configure preemptive HTTP request headers (such as `Authorization` or `Cookie`) applied to every RPC POST.

**Where:** `HttpClient` class body, after `tls_certificate` and before `soup`.

**Depends on:** none.

#### Keep

```vala
		/**
		 * Client certificate to present (mTLS). Null → none.
		 */
		public GLib.TlsCertificate? tls_certificate { get; set; default = null; }
```

#### Add — Store extra HTTP request headers sent on every `call()`.

```vala
		/**
		 * Extra HTTP request headers sent on every {@link call}
		 * (e.g. ''Authorization'' or ''Cookie'').
		 */
		public Gee.HashMap<string, string> headers {
			get; set; default = new Gee.HashMap<string, string>();
		}
```

#### Keep

```vala
		/**
		 * Soup session used by {@link call}.
		 *
		 * Startup sets {@link Soup.Session.timeout} to 15 for the
		 * desktop hello, then 0. 0 means no limit.
		 */
		public Soup.Session soup { get; private set; default = new Soup.Session(); }
```

#### 2. `libocrpc/Transport/HttpClient.vala` — `call()` request headers

**Why:** Apply configured `this.headers` onto each outgoing `Soup.Message` before setting session headers.

**Where:** `HttpClient.call()`, immediately after `var req_headers = message.get_request_headers();` and before `if (this.session_id != "")`.

**Depends on:** Phase 2 §1 (`headers` property).

#### Keep

```vala
			var req_headers = message.get_request_headers();
```

#### Add — Copy configured custom headers onto the outgoing request.

```vala
			foreach (var key in this.headers.keys) {
				req_headers.replace(key, this.headers.get(key));
			}
```

#### Keep

```vala
			if (this.session_id != "") {
				req_headers.replace("X-rpc-session", this.session_id);
			}
```

### ✔️ Phase 3 — New `OLLMrpc.Transport.HttpStream` client

- Create [`libocrpc/Transport/HttpStream.vala`](../../libocrpc/Transport/HttpStream.vala) and wire it into [`libocrpc/meson.build`](../../libocrpc/meson.build) and [`docs/meson.build`](../../docs/meson.build).

#### 1. `libocrpc/Transport/HttpStream.vala` — new binary stream client

**Why:** Provide a cross-platform (Linux, Windows, Android) async HTTP client for held binary RPC streams with an isolated `Bin.Stream` JIT codec and preemptive request headers.

**Where:** New file `libocrpc/Transport/HttpStream.vala`.

**Depends on:** Phase 1 (server-side 4-byte BE length-framed binary streaming).

#### Add — Create `OLLMrpc.Transport.HttpStream` in `libocrpc/Transport/HttpStream.vala`.

```vala
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
	 * var stream = new OLLMrpc.Transport.HttpStream(
	 *     "http://127.0.0.1:8071/events");
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
		 * Extra HTTP request headers sent on {@link open}
		 * (e.g. ''Authorization'' or ''Cookie'').
		 */
		public Gee.HashMap<string, string> headers {
			get; set; default = new Gee.HashMap<string, string>();
		}

		/**
		 * Trust store for a server installation's CA. Null uses the
		 * platform default.
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
		 * Connect to {@link url} and read binary frames until EOF,
		 * error, or {@link close}.
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
				input = yield this.soup.send_async(
					message, GLib.Priority.DEFAULT, this.cancellable);
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
					yield input.read_all_async(
						hdr, GLib.Priority.DEFAULT, this.cancellable, out got);
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
				var hdr_in = new GLib.DataInputStream(
					new GLib.MemoryInputStream.from_data(hdr)
				);
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
					yield input.read_all_async(
						payload, GLib.Priority.DEFAULT, this.cancellable, out body_got);
				} catch (GLib.Error e) {
					reason = this.cancellable.is_cancelled() ? "closed" : e.message;
					break;
				}
				if (body_got < frame_len) {
					reason = "truncated frame";
					break;
				}
				this.bin.in_stream = new GLib.DataInputStream(
					new GLib.MemoryInputStream.from_data(payload)
				);
				this.bin.in_stream.set_byte_order(
					GLib.DataStreamByteOrder.BIG_ENDIAN);
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
```

#### 2. `libocrpc/meson.build` — compile `Transport/HttpStream.vala`

**Why:** Include `HttpStream.vala` in `libocrpc` on all platforms (Linux, Windows, Android).

**Where:** `ocrpc_core_src` list in `libocrpc/meson.build`, after `'Transport/HttpClient.vala'`.

**Depends on:** Phase 3 §1.

#### Keep

```meson
  'Transport/HttpReply.vala',
  'Transport/HttpServer.vala',
  'Transport/HttpClient.vala',
```

#### Add — Add `Transport/HttpStream.vala` to `ocrpc_core_src`.

```meson
  'Transport/HttpStream.vala',
```

#### Keep

```meson
  'Transport/TlsClient.vala',
```

#### 3. `docs/meson.build` — add `HttpStream.vala` to valadoc inputs

**Why:** Keep `ninja -C build docs/valadoc` in sync with `libocrpc/meson.build`.

**Where:** `valadoc_docs` `input:` list in `docs/meson.build`, after `'../libocrpc/Transport/HttpClient.vala'`.

**Depends on:** Phase 3 §1.

#### Keep

```meson
    '../libocrpc/Transport/HttpReply.vala',
    '../libocrpc/Transport/HttpServer.vala',
    '../libocrpc/Transport/HttpClient.vala',
```

#### Add — Add `../libocrpc/Transport/HttpStream.vala` to `valadoc_docs`.

```meson
    '../libocrpc/Transport/HttpStream.vala',
```

#### Keep

```meson
    '../libocrpc/Transport/TlsClient.vala',
```

### ✔️ Phase 4 — Unit test (`tests/rpc/http-stream-test.vala`)

- Add [`tests/rpc/http-stream-test.vala`](../../tests/rpc/http-stream-test.vala) and wire it into [`tests/meson.build`](../../tests/meson.build) under `suite: 'rpc'`, proving:
  - Route handler (`GET /events`) sets `reply.bin_body = true`, writes an initial `Notification` inside `dispatch()`, then writes a second `Notification` from a `GLib.Timeout` (exercising initial idle unpause, mid-stream unpause, and JIT token reuse across frames).
  - `HttpStream` sends a custom `Authorization` header, receives both `Notification` frames in order, then calls `close()` and verifies both `HttpStream.closed` and server `HttpReply.closed` fire.
  - `HttpClient.call` with `bin_body = true` and `headers.set("Authorization", ...)` sends the header preemptively on `POST /rpc` and succeeds alongside the held stream without JIT collision.

#### 1. `tests/meson.build` — wire `test-rpc-http-stream`

**Why:** Run the new HTTP binary streaming and request-header test under `meson test -C build --suite rpc`.

**Where:** `tests/meson.build`, after `test('test-rpc-http-client', ...)` and before `test_rpc_http_https`.

**Depends on:** Phases 1–3.

#### Keep

```meson
test('test-rpc-http-client',
  test_rpc_http_client,
  suite: 'rpc',
  timeout: 10,
)
```

#### Add — Build and register `test-rpc-http-stream` in suite `rpc`.

```meson
test_rpc_http_stream = executable('test-rpc-http-stream',
  'rpc/http-stream-test.vala',
  dependencies: rpc_test_deps + [
    rpc_test_app_dep,
    dependency('libsoup-3.0'),
  ],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  export_dynamic: true,
  vala_args: rpc_test_vala_args + [
    '--pkg=libsoup-3.0',
  ],
)
test('test-rpc-http-stream',
  test_rpc_http_stream,
  suite: 'rpc',
  timeout: 10,
)
```

#### Keep

```meson
test_rpc_http_https = executable('test-rpc-http-https',
```

## LLM

- ℹ️ Consumer: `finchsync/docs/bugs/2026-11-25-FEATURE-phase6-fork-and-sse.md` (Phase 2 auth rejection + Phase 3 held binary event stream).
- ℹ️ Why 4-byte length framing on HTTP binary streaming:
  - `Bin.Stream.parse()` uses synchronous blocking reads, so reading directly from a live Soup `InputStream` on the GLib main loop would block the application.
  - Framing each binary object lets `HttpStream` assemble one full object asynchronously via `read_all_async` before calling `bin.parse()` on a `MemoryInputStream`, with zero worker threads and full Windows/Android/Linux portability.
  - Write side reserves 4 bytes with `DataOutputStream.put_uint32(0)` in `GLib.MemoryOutputStream`, encodes the object, seeks to `0`, overwrites the BE length with `put_uint32((uint32) (mem.get_data_size() - 4))`, and emits one `append_bytes` chunk; read side decodes the 4-byte BE length via `GLib.DataInputStream.read_uint32()` (no manual bit-shifting).
- ℹ️ Why separate `HttpStream` instead of adding streaming onto `HttpClient`:
  - `HttpClient` owns `session_id`, `sequence`, and `Session.bin` for sequenced unary `POST /rpc` calls.
  - A held stream needs an independent `Bin.Stream` and `Cancellable` lifecycle so concurrent unary `POST /rpc` calls cannot race or corrupt JIT token tables.
- 🚫 Do not change the unary `HttpReply.write` binary `Response` wire format (`!this.streaming && serializable is Response`).
  - Existing `HttpClient.call` and `test-rpc-http-bin-session` expect raw unframed `Bin.Stream` bytes for unary replies.
- 🚫 This report does not change `finchsync`.
- ✔️ Applied 2026-11-27 (Phases 1–4):
  - `ninja -C build` succeeded cleanly.
  - `meson test -C build test-rpc-http-stream test-rpc-http-server test-rpc-http-routes test-rpc-http-bin-session test-rpc-http-client test-rpc-http-https` — all 6 passed (`test-rpc-http-stream` in 0.10s, zero errors).
  - Caught and fixed two issues during verification:
    - Calling `HttpStream.close()` synchronously from a `received` handler exited the `while` loop with `reason` still `"eof"`; added `if (this.cancellable.is_cancelled()) { reason = "closed"; }` after the loop.
    - `Soup.Server.accept_iostream()` leaves `msg.get_socket() == null`, Soup does not poll paused chunked messages for peer EOF, and `g_signal_connect_object` on `msg.finished` disconnected when `HttpReply` had no external ref; fixed via `ollmrpc-peer-socket` on `remote`, `GLib.SocketSource` watch on `HttpReply`, and `ollmrpc-http-reply` ref cleared in `msg.finished`.
  - `ninja -C build docs/valadoc` parsed `HttpReply.vala`, `HttpClient.vala`, and `HttpStream.vala` with zero errors (pre-existing unrelated `OLLMchat.VERSION` errors remain in `libollmchat/Settings/FilesdClient.vala` and `ollmapp/`).
  - Remaining non-HTTP tests in `--suite rpc` (`test-rpc-gi`, `test-rpc`, `test-rpc-t1`, `test-rpc-t2`, `test-rpc-stacked-review`) timed out under agent sandbox permissions (`/run/user/1001` read-only / bwrap); run outside sandbox if full-suite verify is needed.
  - Follow-up cleanup: removed the overarching `try/catch` in `HttpReply.write()`, narrowing `try/catch` strictly to the throwing encode calls in each branch (and encoding the first streaming frame before setting `this.streaming = true` so a first-frame failure still returns HTTP 500); re-verified all 6 HTTP RPC tests (`test-rpc-http-stream` 0.09s).
