# TlsClient.watch holds the mutex for the 10s socket timeout

**Status:** 🚫 CLOSED 2026-11-05. Hunks not applied. Current `watch` skips `parse` when the TLS stream is not readable. Code stays as it is.

**Pointer:** `docs/bug-fix-process.md`. `docs/guide-to-writing-plans.md` — **Checklist for plans**.

ℹ️ Follow-on to `docs/bugs/done/2026-11-04-FIXED-tlsclient-watch-timeout.md`.
  That report kept `watch` alive on `TIMED_OUT`. It still waits the
  full `{@link TlsClient.timeout}` with `{@link TlsClient.mutex}` held.
ℹ️ Argus: `/home/alan/gitlive/argusrm/docs/bugs/2026-11-05-osquery-sync-10s.md`.

---

## Problem

- 🔷 Argus agent `OSQuery.sync` after a live `watch` takes ~10s per table.
- 🔷 The osquery SELECT is milliseconds. The server `recv` is ~10s later.
- 🔷 Server `backupDB` and the reply are milliseconds. The agent then
  logs `sent`.
- 🔷 Expected: `call` writes as soon as the query finishes.

---

## Evidence

- ✔️ Agent `/var/log/argusrm/agent.log` 10:51:34–10:52:14:
  - `watching app socket` at 10:51:34.374
  - `SELECT * FROM system_info 1 rows` at 10:51:34.661
  - `system_info sent` at 10:51:44.453
  - same ~9.8s gap on `cpu_info`, `logged_in_users`,
    `interface_addresses`
- ✔️ Server `/var/log/argusrm/server.log`:
  - first `recv id=0 method=OSQuery.sync` at 10:51:44.442
  - `disk backup requested` 4ms later
  - next `recv` only after the next agent `sent`
- ✔️ `argus.sqlite` is 32KB. The backup is not the 10s.
- ✔️ `open` sets `GLib.SocketClient.timeout` to
  `{@link TlsClient.timeout}` (10). That value is copied onto the
  connected `{@link GLib.Socket.timeout}`.
- ✔️ `watch` sets `blocking = false` and `parse`s on a 50ms tick
  with the mutex held. `GSocket.timeout` still waits up to 10s
  before `WOULD_BLOCK` / `TIMED_OUT`.
- ✔️ `call` cannot `write` until that `parse` unlocks.
- ✔️ `Command.stdout` after `agent.run` at 10:52:49 arrived on the
  server at 10:53:09 as one burst. The watch tick blocks the
  default main context for those same 10s.

---

## Root cause

- ✔️ `{@link TlsClient.timeout}` is documented as the TCP connect.
  The reply wait is a separate 10s monotonic loop.
- ✔️ `GLib.SocketClient.timeout` also sets `{@link GLib.Socket.timeout}`
  on the connected socket. Idle `watch` `parse` then blocks up to
  that many seconds with the mutex held.
- ✔️ `call` from the osquery thread sits on the mutex. The request
  is not on the wire until the watch read times out.

---

## Proposed fix

- 💩 `watch` sets `{@link GLib.Socket.timeout}` to 0 when it sets
  `blocking = false`.
- 💩 `call` restores `{@link TlsClient.timeout}` when it sets
  `blocking = true`.
- 🚫 Do not drop the connect timeout. `open` still uses
  `GLib.SocketClient.timeout`.
- 🚫 Do not add helpers.

### `libocrpc/Transport/TlsClient.vala` — `timeout` doc

**Why:** The property is connect plus the blocking `call` read.

**Where:** the `timeout` property docblock.

#### Remove

```vala
		/**
		 * Seconds for the TCP connect. The reply wait is 10 seconds,
		 * matching the copied loops.
		 */
```

#### Replace with

```vala
		/**
		 * Seconds for the TCP connect and a blocking {@link call}
		 * read. The reply wait is the same 10 seconds, matching the
		 * copied loops. {@link watch} sets the socket timeout to 0.
		 */
```

### `libocrpc/Transport/TlsClient.vala` — `call` after removing watch

**Why:** Idle `watch` left the socket with no I/O timeout.

**Where:** after `this.socket.socket.blocking = true;`

#### Add

```vala
			this.socket.socket.timeout = this.timeout;
```

### `libocrpc/Transport/TlsClient.vala` — `watch`

**Why:** A timed-out idle `parse` must not hold the mutex for the
connect timeout.

**Where:** both `this.socket.socket.blocking = false;` assignments.

#### Add — after each `blocking = false`

```vala
			this.socket.socket.timeout = 0;
```

---

## Attempts / changelog

- ✔️ 10:51 live logs: request is 10s late to the server, not slow
  to answer.
- ✔️ Ruled out `backupDB`. 32KB file, 4ms between `recv` and
  `disk backup requested`.

---

## Next

- 🚫 Closed. Do not apply the timeout-0 hunks.
