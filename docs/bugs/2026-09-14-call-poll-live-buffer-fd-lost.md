# `call_poll` loses `Live.Buffer` fd on reply

**Status:** ✔️ applied — in-tree tests green; await consumer / user ✅  
**Hit:** 2026-09-14 — gnome-shell-rpc DING `WaylandClient.spawnv` stdout  
**Component:** `libocrpc` / `OLLMrpc.Client.call_poll` + `Live.BufferStream`  
**Consumer gate:** `gnome-shell-rpc/tests/call-sync-repro/call-poll-buffer-fd-gate`  
**In-tree repro:** `tests/rpc/scm-response-call-poll-test.vala`  
**Related:** `Client.vala` `call_poll`, `dispatch_message` `take_pending`, `Live/BufferStream.vala`  
**Prior `call_poll` fixes (same style):**  
`docs/bugs/done/2026-09-10-FIXED-call-poll-pollfd-revents-copy.md`,  
`docs/bugs/done/2026-09-10-FIXED-iochannel-buffer-condition-skips-read.md`

---

## Problem

🔷 Server `request.reply(response, new Live.Buffer(fd))` sends the fd on
the **`.fd`** channel first, then the bin Response (fd-first order).

🔷 Client `call_poll` only `GLib.poll`s the **main** bin socket. When the
Response is demuxed, `buffer_stream.take_pending()` is often still empty
because the `.fd` watch lives on the default MainContext, which
`call_poll` does not iterate.

🔷 Nest: Helper logs `stdout_fd=77`; client logs `stdout_fd=-1 buffer=null`
→ DING `Gio.DataInputStream.new(null)` → `Argument base_stream may not be null`.

---

## Evidence

### Consumer (gnome-shell-rpc)

```bash
meson compile -C build call-poll-buffer-fd-gate
timeout 5 ./build/tests/call-sync-repro/call-poll-buffer-fd-gate
# FAIL — call_poll echo_fd got_fd=-1
```

```
Helper-WaylandClient.spawnv stdout_fd=77
WaylandClient.spawnv client stdout_fd=-1 buffer=null
```

### In-tree (OLLMchat) — ✔️ library owns it

Control (async `Client.call` + MainLoop — drains `.fd` watch):

```bash
meson test -C build test-rpc-scm-response
# OK
```

Repro (`Client.call_poll`, server in a **separate process** — no fork-after-GApp,
no shared MainContext with client):

```bash
meson test -C build test-rpc-scm-response-call-poll
# FAIL exit 1 — call_poll paint got_fd=-1 buffer=null
```

✔️ Same symptom as the consumer gate. Async SCM Response path still passes.

---

## Root cause

✔️ Confirmed from code + in-tree repro:

1. `Live.BufferStream.write_with` — fd on `.fd` socket **first**, then bin object.
2. `BufferStream` fills `pending` only via `receive_one()` (IOChannel watch on
   **default** MainContext, or an explicit call).
3. `Client.call_poll` removes the main read watch and blocks on `GLib.poll` of
   the **main** bin fd only — it never drains `buffer_stream.socket`.
4. `dispatch_message` on Response does `take_pending()` immediately → empty →
   `response.buffer == null`.

Same pattern as prior `call_poll` bugs: the poll path must do by hand what the
async MainContext watch used to do — **not** by iterating MainContext.

ℹ️ `call_sync` uses a **private** MainContext with only the main read watch;
the `.fd` watch stays on default context, so it has the same structural gap
(consumer is on `call_poll`).

---

## Proposed fix (library only)

💩 Drain the `.fd` socket with `GLib.poll(…, 0)` + `receive_one` at the
start of `dispatch_message` when under `call_poll`, **before**
`take_pending` / `attach`. Same contract as `scm-notification-test` (parse
bin → receive fd → attach). No MainContext.

**Why here:** `take_pending` runs from `poll_drain_readable` →
`dispatch_message`. Fd-first means when the Response is readable on the main
socket, the `.fd` data is already in the kernel — non-blocking poll is enough.

**🚫** `GLib.MainContext.default().iteration` / Idle / sleep / “pump until fd”.  
**🚫** Re-introducing a private MainLoop for the fd leg.  
**🚫** Consumer workarounds around spawnv.  
**🚫** New private helper — inline in `dispatch_message`.

### 1. `libocrpc/Client.vala` — `dispatch_message`: drain `.fd` under `call_poll`

**Why:** During `call_poll`, the `BufferStream` IOChannel watch never runs.
Fill `pending` before the existing `take_pending` / `attach` lines.

**Where:** `dispatch_message` — from method open through Response
`take_pending` (Notification `attach` unchanged; same `pending` queue).

**Depends on:** none.

#### Remove

```vala
		private void dispatch_message(Bin.Serializable msg)
		{
			var response = msg as Response;
			if (response != null) {
				var found = false;
				foreach (var entry in this.pending) {
					if (entry.request.id != response.id) {
						continue;
					}
					found = true;
					break;
				}
				if (!found) {
					GLib.error(
						"unexpected response id %d",
						response.id
					);
				}
				if (this.buffer_stream != null) {
					response.buffer = this.buffer_stream.take_pending();
				}
```

#### Replace with

```vala
		private void dispatch_message(Bin.Serializable msg)
		{
			/* call_poll does not run the .fd IOChannel watch — drain SCM fds into pending first. */
			while (this.poll_depth > 0 && this.buffer_stream != null
				&& this.buffer_stream.socket != null) {
				var buffer_poll = GLib.PollFD();
				buffer_poll.fd = this.buffer_stream.socket.get_fd();
				buffer_poll.events = GLib.IOCondition.IN;
				var buffer_fds = new GLib.PollFD[] { buffer_poll };
				if (GLib.poll(buffer_fds, 0) <= 0
					|| (buffer_fds[0].revents & GLib.IOCondition.IN) == 0) {
					break;
				}
				try {
					this.buffer_stream.receive_one();
				} catch (GLib.IOError e) {
					if (e.code == GLib.IOError.WOULD_BLOCK) {
						break;
					}
					GLib.warning("buffer stream receive: %s", e.message);
					break;
				} catch (GLib.Error e) {
					GLib.warning("buffer stream receive: %s", e.message);
					break;
				}
			}
			var response = msg as Response;
			if (response != null) {
				var found = false;
				foreach (var entry in this.pending) {
					if (entry.request.id != response.id) {
						continue;
					}
					found = true;
					break;
				}
				if (!found) {
					GLib.error(
						"unexpected response id %d",
						response.id
					);
				}
				if (this.buffer_stream != null) {
					response.buffer = this.buffer_stream.take_pending();
				}
```

ℹ️ Outer `if` folded into the `while` condition. Loop exits when not in
`call_poll`, no buffer stream, or `.fd` not readable.

---

## Attempts / changelog

- ✔️ Read `call_poll`, `dispatch_message`, `BufferStream` (watch vs `receive_one`).
- ✔️ Compared to `tests/rpc/scm-response-test.vala` (async — passes).
- 🚫 Fork-after-GApplication repro — crashes (`gee_abstract_map_has_key`);
  do not use.
- ✔️ Subprocess server (`argv[1] == "server"`) + client `call_poll` —
  `got_fd=-1 buffer=null`.
- ✔️ 🔷 Applied §1 (tighter `while` break, comment) —
  `test-rpc-scm-response` + `test-rpc-scm-response-call-poll` OK.

## Next

- ⏳ 🔷 Consumer gate / nest verify → ✅ then rename FIXED and move to `docs/bugs/done/`.
