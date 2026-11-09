# TlsClient idle read dies without `closed`

**Status:** ✔️ fix applied in `TlsClient`; not device-verified

**Pointer:** `docs/bug-fix-process.md`. `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala must follow `docs/coding-standards.md`.

ℹ️ Filed from Argus. That tree does not edit `libocrpc`.
ℹ️ Argus log: `/home/alan/gitlive/argusrm/docs/bugs/2026-11-09-connection-drop-not-signalled.md`.
ℹ️ Class: `libocrpc/Transport/TlsClient.vala`.

---

## Problem

- 🔷 Argus must notice when the server connection drops, then try again 30 seconds later.
- 🔷 After `open` succeeds, a later read error only logs `GLib.warning` and stops the idle source.
- 🔷 `connected` stays true. `open` returns immediately, so the same object cannot handshake again.
- 🔷 Installed `TlsClient` has no signal for that stop.
- 🔷 Expected: the idle read closes the socket, clears `connected`, and emits `closed` so the caller can `open` again.

---

## Evidence

- ✔️ Installed `/usr/share/vala/vapi/ocrpc.vapi` `TlsClient` exposes `open`, `call`, `watch`, and `notification`.
  - No `closed` signal.
  - `connected` is not on `TlsClient`. The `connected` property in that vapi is `OLLMrpc.Client`.
- ✔️ `libocrpc/Transport/TlsClient.vala` keeps `connected` private.
  - `open` returns immediately while `connected` is true.
- ✔️ `watch` treats `WOULD_BLOCK` and `TIMED_OUT` as idle.
  - Any other read error calls `GLib.warning`, sets `watch_id` to 0, and returns false.
  - `watching` stays true. `connected` stays true. `link` and `socket` stay set.
- ✔️ `call` restarts `watch` while `watching` is still true.
  - A caller cannot probe the dead socket with `call`. That starts the idle read again on the same dead stream.

---

## Root cause

- ✔️ The fatal branch of `watch` drops the timeout and does not tell the caller.
- ✔️ The socket stays open and `connected` stays true, so `open` will not handshake again.

---

## Ruled out

- 🚫 Sniffing `GLib.warning` text in the caller.
- 🚫 Calling `call` on a timer to see if the connection is dead.

---

## Proposed fix

- 🔷 Emit `closed` after a fatal idle read.
- 🔷 Close the TLS connection, clear `connected`, and leave `open` able to handshake again.
- 🔷 Publish `connected` so a caller can see the flag the signal just cleared.
- 🔷 Rename the private `GLib.TlsClientConnection` field from `link` to `connection` in this class.

### `libocrpc/Transport/TlsClient.vala` — `closed` and public `connected`

**Why:** The idle read has to tell the caller the connection failed. `connected` has to be false afterwards so `open` runs the handshake.

**Where:** next to `notification`, replacing the private `connected` field.

#### Add

```vala
		/**
		 * The idle read stopped because the connection failed.
		 *
		 * {@link watch} emits this after it closes the socket.
		 * {@link connected} is then false, so {@link open} can
		 * handshake again.
		 */
		public signal void closed();

		/**
		 * True after {@link open} until the idle read fails.
		 */
		public bool connected { get; private set; default = false; }
```

#### Remove

```vala
		private bool connected = false;
```

### `libocrpc/Transport/TlsClient.vala` — `watch` doc

**Why:** The timeout comment still says every read error keeps the source. A fatal read now stops it.

**Where:** the `watch` docblock.

#### Remove

```vala
		 * timed-out read keeps the source.
```

#### Replace with

```vala
		 * timed-out read keeps the source. Any other read error
		 * stops the source, closes the socket, and emits
		 * {@link closed}.
```

### `libocrpc/Transport/TlsClient.vala` — fatal branch of `watch`

**Why:** A read error other than idle has to drop the source, close the socket, and emit `closed`. The local holds `connection` across the unlock so `close` runs after the mutex, with the field already null.

**Where:** the `catch` in the timeout, after the `WOULD_BLOCK` / `TIMED_OUT` return.

#### Remove

```vala
					GLib.warning("%s", e.message);
					this.watch_id = 0;
					this.mutex.unlock();
					return false;
```

#### Replace with

```vala
					GLib.warning("%s", e.message);
					this.watch_id = 0;
					this.watching = false;
					this.connected = false;
					this.fd = -1;
					var tls = this.connection;
					this.connection = null;
					this.socket = null;
					this.mutex.unlock();
					if (tls != null) {
						try {
							tls.close();
						} catch (GLib.Error close_error) {
							GLib.warning("%s", close_error.message);
						}
					}
					this.closed();
					return false;
```

### `libocrpc/Transport/TlsClient.vala` — field `link`

**Why:** The TLS object in this class is a connection. Callers and the close path should use that name.

**Where:** the class example, the field, `open`, and the idle poll.

#### Remove

```vala
	 * var link = new OLLMrpc.Transport.TlsClient(host, port) {
	 *     accept_any = true
	 * };
	 * var response = link.call(request);
```

```vala
		private GLib.TlsClientConnection? link = null;
```

```vala
			this.link = tls;
```

```vala
					var pollable = this.link.get_input_stream()
						as GLib.PollableInputStream;
```

#### Replace with

```vala
	 * var connection = new OLLMrpc.Transport.TlsClient(host, port) {
	 *     accept_any = true
	 * };
	 * var response = connection.call(request);
```

```vala
		private GLib.TlsClientConnection? connection = null;
```

```vala
			this.connection = tls;
```

```vala
					var pollable = this.connection.get_input_stream()
						as GLib.PollableInputStream;
```

---

## Attempts

- ✔️ Read `libocrpc/Transport/TlsClient.vala` `open`, `call`, and `watch`.
- ✔️ Read installed `/usr/share/vala/vapi/ocrpc.vapi` `TlsClient`.
- ✔️ Applied `closed`, public `connected`, the fatal `watch` branch, and the `link` → `connection` rename.

---

## Next

- ⏳ Install `libocrpc` so the vapi grows `closed` and public `connected`.
- ⏳ Argus then connects `closed` in `agent/Application.vala`. That step stays in the Argus log.
