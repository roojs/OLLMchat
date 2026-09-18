# `call_poll` strands a buffered reply; re-entrant `Live.Hook.emit` aliases it

**Status:** ✅ FIXED — user archived 2026-09-18 (`libocrpc` §1–§3 applied)

**Process:** `docs/bug-fix-process.md`

**Package / area:** `libocrpc` — `Client.vala` (`call_poll`, `poll_drain_readable`), `Live/Hook.vala` (`emit`)

**Related:**

- ℹ️ Consumer bug: `gnome-shell-rpc` `docs/bugs/2026-09-18-hang-after-settle-race.md`
- ℹ️ Gates (two real processes, no Clutter/GJS): `gnome-shell-rpc/tests/call-sync-repro/{nested-relay-storm-gate,same-hook-reentrant-emit-gate}.vala`
- ℹ️ Same defect class already fixed on the server path by a consumer override: `gnome-shell-rpc/src/rpc/Connection.vala` (`input_pending`)

---

## Problem

🔷 **A: `call_poll` never returns** although the reply arrived. Expected: the call completes. Actual: it blocks until `call_timeout_seconds`, then `Client.vala:1170` aborts the process when the late reply surfaces.

🔷 **B: a re-entrant emit on one hook returns the wrong value.** Expected: each `emit` gets its own reply. Actual: the inner reply releases the outer emit too; the outer returns the inner's value and the outer reply is rejected `INVALID_PARAMS`.

Reproduce:

- `meson compile -C build nested-relay-storm-gate && ./build/tests/call-sync-repro/nested-relay-storm-gate` → **A**, ~5 s, self-terminating.
- `meson compile -C build same-hook-reentrant-emit-gate && timeout 20 ./build/tests/call-sync-repro/same-hook-reentrant-emit-gate` → **B**.

ℹ️ Only reachable when a consumer re-enters `call_poll` from a `Live.Invoke` handler while the server is parked in `Live.Hook.emit` — relaying a synchronous re-entrant C API (Clutter allocate/measure) over RPC. Plain request/response never hits it.

---

## Evidence

- ✔️ **A — the reply is already inside the client.** The gate reads `bin.in_stream.get_available()` at the stall:
  - `FAIL … ping at depth 1: call timed out` / `client bin buffer at the stall: 32 bytes unparsed`
  - 5 runs, 5 stalls, at depths 1, 1, 2, 4, 4 — 25–32 bytes each, exactly one Response. Nothing was lost or unflushed.
- ✔️ **A — it is stranded, not dropped.** After the timeout the client sends its next request, the server answers, and that wake drains the backlog: `ERROR Client.vala:1170: unexpected response id 197` (a 5-second-old reply → abort).
- ✔️ **A — capping the client's reads below the smallest wire message (25 bytes) fixes it,** which isolates the over-read as the cause: `GSR_STORM_CAP=8` → PASS 400 rounds / 1600 invokes / depth 4 / 4800 notifications / 1267 ms; `=16` → PASS 1266 ms; unset → FAIL within ~13 rounds.
- ✔️ **A — the existing pending tests cannot fire.** `read_channel` is created `set_buffered(false)` (`Client.vala:420–423`), so `get_buffer_condition()` returns `0` unconditionally and both checks that consult it (`:705`, `:1054`) are dead code.
- ✔️ **B — outer emit returns `22`,** the inner emit's value; outer reply rejected.
- ✔️ **B — routine, not exotic:** one consumer session logged 86 re-entrant invokes on the same callback id, nesting to depth 4; the storm gate counts 1200 rejected replies per 400 rounds.
- ℹ️ Single-shape gates all PASS (`poll-coalesced-reply-gate`, `poll-nested-coalesced-reply-gate`, `poll-burst-strand-gate`, `buffer-invoke-gate`, `after-reply-gate`, `reentrant-emit-call-gate`) — one coalesced write usually splits across two reads, so **A** needs volume plus nesting.

---

## Root cause

- ✔️ **A.** Two readers disagree about where pending input lives. Messages are parsed from `bin.in_stream`, and `Bin.Stream.parse` opens each message with `DataInputStream.read_byte`, which fills the whole 4096-byte buffer — pulling in whatever else the socket had. Both "is more input pending?" tests instead ask the unbuffered `read_channel`, which can never say yes. So `poll_drain_readable` parses one message and returns, and `call_poll` blocks in `GLib.poll()` on an fd with nothing left. With the peer parked in `emit`, no further byte is ever written and both ends sit in `poll`.
- ✔️ **B.** Reply state lives on the hook **row** (`replied`, `reply_id`), but emits are per **call** and nest. The inner emit overwrites both, so the first reply releases every waiting frame.

---

## Proposed fix

🔷 **A** is fixed in the library (§1–§2): ask the stream that actually holds the bytes. This replaces code that is provably dead, so no existing caller changes behaviour — the only difference is that drains which should already have happened now do. The pending test is inlined at both sites (`this.bin.in_stream.get_available() > 0`); there is no helper and no override seam.

🔷 **B** needs one keyword (§3): with `emit` virtual, a consumer that owns `Live.Callback.register` / `reply` can keep per-emit frames itself. 💩 If you would rather fix **B** centrally too, move `replied` / `reply_args` into a per-`reply_id` frame on the hook and have `Callback.reply` take the matching frame — say so and I will rewrite §3 as that edit.

### 1. `libocrpc/Client.vala` — `poll_drain_readable()`: recurse while the buffer has data

**Why:** one `read_byte` can pull several messages into the buffer; the recursion currently tests the unbuffered channel, so it stops after one and leaves the rest unparsed. `bin` is already non-null here (`!this.connected || this.bin == null` returns above); `in_stream` is set with `bin` on the socket path.

**Where:** end of `poll_drain_readable`, the `if` immediately after the `try`/`catch` block.

**Depends on:** none.

#### Remove

```vala
			if ((source.get_buffer_condition() & GLib.IOCondition.IN) != 0) {
				return this.poll_drain_readable(source);
			}
```

#### Replace with

```vala
			if (this.bin.in_stream.get_available() > 0) {
				return this.poll_drain_readable(source);
			}
```

### 2. `libocrpc/Client.vala` — `call_poll()`: drain the buffer before blocking in `poll()`

**Why:** without this, a reply already sitting in the buffer is never noticed and the loop blocks on a socket fd that has nothing left to deliver.

**Where:** inside `while (entry.done_response == null)`, the `if` between the timeout check and `if (entry.done_response != null) { break; }`.

**Depends on:** none.

#### Remove

```vala
				if (this.read_channel != null && (this.read_channel.get_buffer_condition() & GLib.IOCondition.IN) != 0) {
					this.poll_drain_readable(this.read_channel);
				}
```

#### Replace with

```vala
				if (this.bin.in_stream.get_available() > 0) {
					this.poll_drain_readable(this.read_channel);
				}
```

### 3. `libocrpc/Live/Hook.vala` — `emit()`: allow a per-emit override

**Why:** everything `emit` touches is already public (`connection.next_handle`, `connection.write`, `connection.emit_wait_poll`) and `libocrpc` never emits hooks itself — only consumers do. With `emit` virtual, a consumer that owns `Live.Callback.register` / `reply` (as `gnome-shell-rpc` does) can keep per-emit frames and wait on its own frame, with no change to library semantics.

**Where:** `Hook` class body — the `emit` signature.

**Depends on:** none.

#### Remove

```vala
		public void emit(Gee.ArrayList<GLib.Value?> args)
```

#### Replace with

```vala
		public virtual void emit(Gee.ArrayList<GLib.Value?> args)
```

---

## Attempts / changelog

- ✔️ `nested-relay-storm-gate.vala` (consumer tree) — drives the live shape at volume and prints `bin.in_stream.get_available()` at the stall. That measurement is what the earlier single-shape gates were missing.
- 🚫 `in_stream.set_buffer_size(1)` — breaks the stream: a 1-byte buffer cannot satisfy `read_uint64`, so parsing dies with `Unexpected early end-of-stream` (`Client.vala:701`).
- 🚫 Consumer-side capped-read filter on `bin.in_stream.base_stream` — PASSes at caps 8 and 16, and proved the over-read is the cause, but it assumes no message is smaller than the cap and spends extra `read()` syscalls. Superseded by §1–§3; not for landing.
- 🚫 Seam + downstream override for **A** (`protected virtual poll_input_pending()`) — rejected 2026-09-18: it preserves a default that is dead code, so it is the same edit with extra indirection.
- 🚫 Private `poll_input_pending()` helper — dropped 2026-09-18: the virtual seam was already rejected, and the remaining method is one expression; inlined at both drain sites.
- 🚫 Null guards on `bin` / `in_stream` / `read_channel` in the pending test — dropped 2026-09-18: `connect` sets them together; `disconnect` completes the wait before clearing them; `poll_drain_readable` already returns when `bin` is gone.
- ℹ️ gdb was unusable in the investigation sandbox (no symbol resolution); the stall measurement and `G_MESSAGES_DEBUG=all` wire logs carried the diagnosis instead.

---

## Next

- ✅ 🔷 §1–§3 applied 2026-09-18 (drain/`call_poll` ask `in_stream.get_available()`, `Hook.emit` virtual). Pending test inlined; no `poll_input_pending`.
- ℹ️ 💩 `Client.vala` unexpected-response `GLib.error()` after timeout — separate call; not part of this fix.
- ℹ️ 🔷 Consumer regression (`nested-relay-storm-gate`, `same-hook-reentrant-emit-gate`) lives in gnome-shell-rpc.
