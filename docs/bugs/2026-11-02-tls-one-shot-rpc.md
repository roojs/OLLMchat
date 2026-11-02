# One TLS request is copied instead of living in libocrpc

**Status:** ✔️ `OLLMrpc.Transport.TlsClient` is in `libocrpc`. `FilesdClient.try_connection` and the Android address probe use it. ⏳ Argus `fetch`, `Identity.run`, and `Register.try_connection` still use their loops until the installed `ocrpc` exports this type.

## Problem

- 🔷 `Argus.Agent.Download.fetch` spends most of its body opening a TLS socket, writing one bin request, and polling for one response.
- 🔷 That sequence should live in the RPC library. Callers repeat it.
- 🔷 This report is the change. libocrpc is not edited from the Argus tree.

## Evidence

- ✔️ The same connect, handshake, `Bin.Stream.write`, and `PollFD` reply loop is in:
  - `argusrm/agent/Download.vala` `fetch` — client certificate, any server certificate accepted
  - `argusrm/agent/Identity.vala` `run` — same, then `Machine.identity`
  - `argusrm/shared/Register.vala` `try_connection` — no client certificate yet, any server certificate accepted
  - `libollmchat/Settings/FilesdClient.vala` `try_connection` — registration accepts any server certificate; the next connection sets the client certificate and trust and allows only a bad identity
  - `FilesdClient.complete_pairing` — a second request on that already-open stream
- ℹ️ `OLLMrpc.Client` already connects `tcp://host:port`, emits `configure_tls`, and allows only `BAD_IDENTITY` on the server certificate.
- ℹ️ `Client.connect` always sends a hello and returns a bool. The hello `Response` body is dropped.
- ℹ️ `Client.call` and `Client.call_sync` require `connected`. `call_sync` throws on Android.
- ℹ️ `docs/bugs/done/2026-10-06-FIXED-android-live-rpc-read-watch.md` — the pairing dialog still does its own one-shot read. The steady-state reader stays in `Client`. That does not cover a call whose reply is the result, or a second call on the same handshake.

## Root cause

- ✔️ There is no library call that opens TLS, sends one `Request`, and returns that `Response`. Registration cannot use `Client.connect`: the reply is the certificate, and the CA is not known until that reply arrives. `FilesdClient` then sends another request on the same connection.

## Proposed fix

- 💩 Add `OLLMrpc.Transport.TlsClient` in `libocrpc`. `open` connects and handshakes. `call` writes one request and waits for the response. A second `call` uses the same handshake. `call` opens first when the caller did not.
- 💩 It belongs in `Transport`, beside `HttpClient`. That type is already the client that sends one `Request` and returns the `Response`. `OLLMrpc.Client` is the long-lived session: it always sends hello, drops that body, and keeps a read watch. A top-level `TlsLink` would be a second client. `Transport` already owns the socket, the handshake, and `HttpClient.call`.
- 💩 `accept_any` is the server-certificate rule. It does not clear a client certificate. Registration sets `accept_any` and leaves `tls_certificate` unset. Argus `fetch` and the identity post set both: the client certificate is presented, and any server certificate is accepted. A call with `accept_any` false keeps the `Client.connect` rule: a peer certificate is required, and a bad identity is the only ignored flag.
- 💩 `tls_certificate` and `tls_database` stay nullable, the same as `HttpClient`. Null means the credential is not set.
- 💩 Argus `fetch`, `try_connection`, and the identity post call this type and delete their copies of the loop. They wait until the installed `ocrpc` exports it. `FilesdClient` and the Android probe wait for the same export.
- 🚫 Do not add another poll loop in Argus or in the Android app as the fix.
- 🚫 Do not change `Client.call_sync` or the Android read watch.

### `libocrpc/Transport/TlsClient.vala` — one handshake, then `call`

**Why:** The copies differ only in the certificate and in how many requests they send. `open` connects and handshakes. `call` writes and polls on that stream.

**Where:** new file. `ocrpc_core_src` in `libocrpc/meson.build`, after `Transport/HttpClient.vala`, so Android builds it too.

**Depends on:** none. Applying it is a libocrpc change, after this shape is confirmed.

#### Add — new file `libocrpc/Transport/TlsClient.vala`

The class is the library change. Callers keep their loops until this export is installed.

```vala
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
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMrpc.Transport
{
	/**
	 * TCP TLS client that sends a {@link OLLMrpc.Request} and
	 * returns that {@link OLLMrpc.Response}.
	 *
	 * Peer to {@link HttpClient} for a raw socket. Not
	 * {@link OLLMrpc.Client}: that type sends hello, drops the
	 * body, and keeps a read watch. {@link open} handshakes
	 * once. A later {@link call} writes the next request on
	 * that stream. {@link call} opens first when the caller
	 * did not. The reply wait polls the socket, so it runs on
	 * Android, where {@link OLLMrpc.Client.call_sync} throws.
	 *
	 * Set {@link accept_any} to accept any server certificate.
	 * {@link tls_certificate} is still presented when it is
	 * set. Registration leaves it unset. Argus download and
	 * the identity post set both. Leave {@link accept_any}
	 * false to require a peer certificate and ignore only
	 * {@link GLib.TlsCertificateFlags.BAD_IDENTITY}, the same
	 * rule as {@link OLLMrpc.Client.connect}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var link = new OLLMrpc.Transport.TlsClient(host, port) {
	 *     accept_any = true
	 * };
	 * var response = link.call(request);
	 *
	 * var authed = new OLLMrpc.Transport.TlsClient(host, port) {
	 *     tls_certificate = certificate,
	 *     tls_database = trust
	 * };
	 * var paired = authed.call(pair_request);
	 * var hello = authed.call(hello_request);
	 *
	 * var download = new OLLMrpc.Transport.TlsClient(host, port) {
	 *     accept_any = true,
	 *     tls_certificate = certificate
	 * };
	 * var file = download.call(get_request);
	 * }}}
	 */
	public class TlsClient : GLib.Object
	{
		/** Remote host passed to {@link GLib.SocketClient.connect_to_host}. */
		public string host { get; construct; }

		/** Remote port passed to {@link GLib.SocketClient.connect_to_host}. */
		public uint16 port { get; construct; }

		/**
		 * True accepts any server certificate.
		 *
		 * {@link tls_certificate} is still presented when it is set.
		 * Registration leaves the certificate unset. Argus download
		 * and the identity post set both.
		 */
		public bool accept_any = false;

		/**
		 * Seconds for the TCP connect. The reply wait is 10 seconds,
		 * matching the copied loops.
		 */
		public uint timeout = 10;

		/**
		 * Client certificate to present. Null sends none, matching
		 * {@link HttpClient.tls_certificate}.
		 */
		public GLib.TlsCertificate? tls_certificate { get; set; default = null; }

		/**
		 * Product CA trust store. Null leaves the handshake on
		 * the {@link accept_any} or bad-identity rule, matching
		 * {@link HttpClient.tls_database}.
		 */
		public GLib.TlsDatabase? tls_database { get; set; default = null; }

		private bool connected = false;
		private int fd = -1;
		/* Keeps the handshake alive. The bin streams borrow the
		 * TLS input stream; they do not own the connection. */
		private GLib.SocketConnection? socket = null;
		private GLib.TlsClientConnection? link = null;
		private Bin.Stream bin {
			get; set; default = new Bin.Stream(null, null, false);
		}

		public TlsClient(string host, uint16 port)
		{
			GLib.Object(host: host, port: port);
		}

		/**
		 * Connect and handshake. A second call returns immediately.
		 *
		 * {@link call} invokes this when the caller did not.
		 *
		 * @throws GLib.Error the TCP connect or the TLS handshake failed
		 */
		public void open() throws GLib.Error
		{
			if (this.connected) {
				return;
			}
			var client = new GLib.SocketClient();
			client.timeout = this.timeout;
			var conn = client.connect_to_host(this.host, this.port);
			/* Android's async connect leaves the socket nonblocking.
			 * The reply wait in call needs a blocking socket that
			 * still reports WOULD_BLOCK until TLS has data. */
			conn.socket.blocking = true;
			var tls = GLib.TlsClientConnection.@new(conn, null);
			if (this.tls_certificate != null) {
				tls.set_certificate(this.tls_certificate);
			}
			if (this.accept_any) {
				tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
			}
			if (!this.accept_any) {
				if (this.tls_database != null) {
					tls.database = this.tls_database;
				}
				tls.accept_certificate.connect((peer_cert, errors) => {
					return peer_cert != null &&
						(errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
				});
			}
			tls.handshake();
			this.bin.in_stream = new GLib.DataInputStream(tls.get_input_stream());
			this.bin.in_stream.set_byte_order(GLib.DataStreamByteOrder.BIG_ENDIAN);
			this.bin.out_stream = new GLib.DataOutputStream(tls.get_output_stream());
			this.bin.out_stream.set_byte_order(GLib.DataStreamByteOrder.BIG_ENDIAN);
			this.socket = conn;
			this.link = tls;
			this.fd = conn.socket.fd;
			this.connected = true;
		}

		/**
		 * Write one request and return the next {@link OLLMrpc.Response}.
		 *
		 * Opens first when {@link open} has not run. A later call
		 * uses the same stream.
		 *
		 * @param request wire request; the caller owns
		 *   {@link OLLMrpc.Request.id}
		 * @return decoded response, including a response error
		 * @throws GLib.Error connect, handshake, or the reply
		 *   wait ran out
		 */
		public Response call(Request request) throws GLib.Error
		{
			this.open();
			this.bin.write(request);
			var reply_wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					var parsed = this.bin.parse();
					if (!(parsed is Response)) {
						continue;
					}
					return (Response) parsed;
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK ||
						GLib.get_monotonic_time() >= reply_wait) {
						throw e;
					}
					var reply_poll = GLib.PollFD();
					reply_poll.fd = this.fd;
					reply_poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { reply_poll }, 200);
				}
			}
		}
	}
}
```

### `libocrpc/meson.build` — compile the new file

**Why:** `ocrpc_core_src` is the shared list. Android and desktop both get the type.

**Where:** `ocrpc_core_src`, the line after `'Transport/HttpClient.vala'`.

#### Add — after `'Transport/HttpClient.vala',`

```meson
  'Transport/TlsClient.vala',
```

### `libocrpc/Transport/namespace.vala` — name the client

**Why:** The namespace comment describes daemon sockets and `HttpClient` is already a client. `TlsClient` needs the same mention.

**Where:** the overview paragraph in the namespace docblock. The following sentence about one {@link OLLMrpc.Bin.Stream} per connection stays.

#### Remove

```vala
 * The OLLMrpc.Transport namespace owns daemon-side sockets: {@link Listen}
 * accept loops, {@link Connection} per peer, and helpers for Unix socket
 * ({@link SocketListen}) or TCP ({@link TcpListen}). HTTP JSON RPC uses
 * {@link HttpServer} with per-POST {@link HttpReply} write targets.
```

#### Replace with

```vala
 * The OLLMrpc.Transport namespace owns the sockets. {@link Listen}
 * accept loops, {@link Connection} per peer, and helpers for Unix
 * socket ({@link SocketListen}) or TCP ({@link TcpListen}). HTTP
 * uses {@link HttpServer}, per-POST {@link HttpReply}, and
 * {@link HttpClient}. {@link TlsClient} is the TCP TLS caller:
 * one handshake, then one or more bin requests.
```

### Argus callers — delete the copied loop

**Why:** `fetch`, `Identity.run`, and `Register.try_connection` each repeat the connect, handshake, write, and poll. That is the large block. `TlsClient` is one copy of it. The rest of each method stays: `fetch` still writes the file, `run` still runs osquery, and `try_connection` still stores the certificate, the CA, and the sockets.

**Where:** the Argus tree, after the installed `ocrpc` exports `Transport.TlsClient`. Not edited from this tree.

**Depends on:** `OLLMrpc.Transport.TlsClient`.

#### `agent/Download.vala` `fetch` — socket loop

`tls_files.ensure()` stays. The bytes check and the temp-file write stay.

#### Remove

```vala
			var client = new GLib.SocketClient() {
				timeout = 10
			};
			GLib.SocketConnection conn;
			try {
				conn = client.connect_to_host(host, (uint16) port);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			conn.socket.blocking = true;
			GLib.TlsClientConnection tls;
			try {
				tls = GLib.TlsClientConnection.@new(conn, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			tls.set_certificate(tls_files.certificate);
			tls.accept_certificate.connect((peer_cert, errors) => {
				return true;
			});
			try {
				tls.handshake();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var bin = new OLLMrpc.Bin.Stream(
				new GLib.DataInputStream(tls.get_input_stream()),
				new GLib.DataOutputStream(tls.get_output_stream())
			);
			GLib.debug("fetching %s", name);
			try {
				bin.write(new OLLMrpc.Request() {
					method = "Download.get",
					args = OLLMrpc.args("s", name)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			OLLMrpc.Bin.Serializable parsed;
			var reply_wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					parsed = bin.parse();
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK || GLib.get_monotonic_time() >= reply_wait) {
						GLib.warning("%s", e.message);
						return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
					}
					var reply_poll = GLib.PollFD();
					reply_poll.fd = conn.socket.fd;
					reply_poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { reply_poll }, 200);
					continue;
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				if (!(parsed is OLLMrpc.Response)) {
					continue;
				}
				break;
			}
			var response = (OLLMrpc.Response) parsed;
```

#### Replace with

```vala
			GLib.debug("fetching %s", name);
			OLLMrpc.Response response;
			try {
				var link = new OLLMrpc.Transport.TlsClient(host, (uint16) port) {
					accept_any = true,
					tls_certificate = tls_files.certificate
				};
				response = link.call(new OLLMrpc.Request() {
					method = "Download.get",
					args = OLLMrpc.args("s", name)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
```

#### `agent/Identity.vala` `run` — socket loop

The osquery queries stay. `computer_type` and `network` stay. They are built before the call.

#### Remove

```vala
			var client = new GLib.SocketClient() {
				timeout = 10
			};
			GLib.SocketConnection conn;
			try {
				conn = client.connect_to_host(host, (uint16) port);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			conn.socket.blocking = true;
			GLib.TlsClientConnection tls;
			try {
				tls = GLib.TlsClientConnection.@new(conn, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			tls.set_certificate(tls_files.certificate);
			tls.accept_certificate.connect((peer_cert, errors) => {
				return true;
			});
			try {
				tls.handshake();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var bin = new OLLMrpc.Bin.Stream(
				new GLib.DataInputStream(tls.get_input_stream()),
				new GLib.DataOutputStream(tls.get_output_stream())
			);
			var computer_type = (vendor + " " + model).strip();
			var network = string.joinv("\n", nets);
			GLib.debug("posting identity for %s", computer_name);
			try {
				bin.write(new OLLMrpc.Request() {
					method = "Machine.identity",
					args = OLLMrpc.args("ssssss", user, computer_name,
						computer_type, speed, uuid, network)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			OLLMrpc.Bin.Serializable parsed;
			var reply_wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					parsed = bin.parse();
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK || GLib.get_monotonic_time() >= reply_wait) {
						GLib.warning("%s", e.message);
						return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
					}
					var reply_poll = GLib.PollFD();
					reply_poll.fd = conn.socket.fd;
					reply_poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { reply_poll }, 200);
					continue;
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				if (!(parsed is OLLMrpc.Response)) {
					continue;
				}
				break;
			}
			var response = (OLLMrpc.Response) parsed;
```

#### Replace with

```vala
			var computer_type = (vendor + " " + model).strip();
			var network = string.joinv("\n", nets);
			GLib.debug("posting identity for %s", computer_name);
			OLLMrpc.Response response;
			try {
				var link = new OLLMrpc.Transport.TlsClient(host, (uint16) port) {
					accept_any = true,
					tls_certificate = tls_files.certificate
				};
				response = link.call(new OLLMrpc.Request() {
					method = "Machine.identity",
					args = OLLMrpc.args("ssssss", user, computer_name,
						computer_type, speed, uuid, network)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
```

#### `shared/Register.vala` `try_connection` — socket loop

No client certificate yet. The reply is still stored as `client.pem`, the CA, `download`, and `server`.

#### Remove

```vala
			var client = new GLib.SocketClient() {
				timeout = 10
			};
			GLib.SocketConnection conn;
			try {
				conn = client.connect_to_host(host, port);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			conn.socket.blocking = true;
			GLib.TlsClientConnection tls;
			try {
				tls = GLib.TlsClientConnection.@new(conn, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			tls.accept_certificate.connect((peer_cert, errors) => {
				return true;
			});
			try {
				tls.handshake();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var bin = new OLLMrpc.Bin.Stream(
				new GLib.DataInputStream(tls.get_input_stream()),
				new GLib.DataOutputStream(tls.get_output_stream())
			);
			try {
				bin.write(new OLLMrpc.Request() {
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("sss", pin, csr, requester)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			OLLMrpc.Bin.Serializable parsed;
			var reply_wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					parsed = bin.parse();
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK || GLib.get_monotonic_time() >= reply_wait) {
						GLib.warning("%s", e.message);
						return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
					}
					var reply_poll = GLib.PollFD();
					reply_poll.fd = conn.socket.fd;
					reply_poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { reply_poll }, 200);
					continue;
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				if (!(parsed is OLLMrpc.Response)) {
					continue;
				}
				break;
			}
			var response = (OLLMrpc.Response) parsed;
```

#### Replace with

```vala
			OLLMrpc.Response response;
			try {
				var link = new OLLMrpc.Transport.TlsClient(host, port) {
					accept_any = true
				};
				response = link.call(new OLLMrpc.Request() {
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("sss", pin, csr, requester)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
```

## Next

- 💩 `⏳` Confirm `Transport.TlsClient`, `open`, `accept_any`, and the class body before editing libocrpc.
- ℹ️ Argus applies the three caller replacements after that export is installed. `FilesdClient` and the Android probe keep their loops until the same export.
