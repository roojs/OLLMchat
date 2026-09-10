# RPC-8.3.8 — `Client.call_poll`: manual read loop blocking RPC

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Status:** **DONE** ✅ — `call_poll` landed; gnome-shell-rpc on poll; bugs closed in `docs/bugs/done/2026-09-10-FIXED-*`

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`** (`line-length-breaking`: format string on the call line; short `if` / `||` on one line; match `libocrpc/Client.vala`)

**Related:**

- ℹ️ `docs/bugs/done/2026-09-10-FIXED-call-sync-nested-io-watch-reentrancy-hang.md` — `G_HOOK_FLAG_IN_CALL` / nested IO watch on `call_sync`
- ℹ️ `docs/bugs/done/2026-09-10-FIXED-iochannel-buffer-condition-skips-read.md` — `poll_drain_readable` buffer gate
- ℹ️ `docs/bugs/done/2026-09-10-FIXED-call-poll-pollfd-revents-copy.md` — `PollFD.revents` array copy
- ℹ️ `docs/bugs/done/2026-09-09-FIXED-call-sync-mid-wait-live-invoke-flow.md` — mid-wait `Live.Invoke` + nested `call_sync` contract
- ℹ️ `gnome-shell-rpc/tests/call-sync-repro/` — consumer behavioural spec (`flow`, `flow+child`, `opc-head`)

---

## Purpose

- 🔷 **Primary consumer: gnome-shell-rpc on Linux** (Wayland/GI blocking path). Same platform class as `call_sync` today — **not** Windows, **not** Android (`#if ANDROID` unavailable stub like `call_sync`).
- 🔷 Add `call_poll` — blocking RPC via **manual `GLib.poll` + parse/dispatch** instead of a private `GLib.MainLoop` + IO watch.
- 🔷 Keep `call_sync` in-tree during bring-up; **gnome-shell-rpc switches fully** to `call_poll` (one entry point, no mix-and-match). No runtime guards for `call_sync` ↔ `call_poll` nesting — out of scope.
- 🔷 Same wire contract: demux `Live.Invoke` / `Notification` mid-wait; nested blocking calls during invoke handling (`RPC-Live-Callback.reply`, child GI).
- ✅ 🔷 `call_poll` in `libocrpc/Client.vala` — landed with `poll_close`, `poll_drain_readable`, `poll_depth`.
- ✅ 🔷 Consumer verify: gnome-shell-rpc on `call_poll` (hello, `get_display`, nested invoke).
- ⏳ 💩 Follow-up (not this plan): delete MainLoop `call_sync` implementation once gnome-shell-rpc is fully off `call_sync`.

---

## Current behaviour

- ℹ️ `call_sync` tears down the async `read_watch_id`, creates a private `GLib.MainContext`, attaches a per-frame `IOSource` + timeout source, and blocks in `my_loop.run()` until `complete_pending` calls `sync_loop.quit()`.
- ℹ️ Nested `call_sync` reenters on the same `sync_context` with a **new** `MainLoop` and **new** IO watch per frame (recent fix for `G_HOOK_FLAG_IN_CALL`).
- ℹ️ Mid-wait `dispatch_message` → `invoke` runs **synchronously** on the call stack inside `on_read`.
- ℹ️ No `call_sync` coverage in `tests/rpc/` today — consumer repro owns the behavioural spec.

---

## Proposed behaviour

- 🔷 `call_poll(Request)` — Linux gnome-shell-rpc path; socket/TCP only; same throws/retval/error mapping as `call_sync`.
- 🔷 **No** private `MainContext` / `MainLoop` / per-frame IO watch for the poll path.
- 🔷 **Read-watch lifecycle** — open inlined in `call_poll` (depth++, outer drops async `read_watch_id`); **`poll_close(request, entry)`** only private helper — called once at the end (`return this.poll_close(request, entry);`), no `try` / `finally`. Teardown (depth--, restore watch) plus response return/throw live in `poll_close`.
- 🔷 **Pending queue recurses with the call stack** — each `call_poll` frame owns one `PendingWrite`:

```text
call_poll(request):          // one stack frame per in-flight sync call
  enqueue entry for this request
  if poll_depth == 0: remove async read_watch_id
  poll_depth++
  send THIS entry once (blocking flush)
    catch GLib.Error → complete_pending(entry.id, e) only
  while entry.done_response == null:
    if call_timeout expired: complete_pending(TIMED_OUT); break
    poll_drain_readable (recursive; returns true when buffer drained)
      Live.Invoke → handler → call_poll(child) … poll_close(child)
    if entry.done_response: break
    GLib.poll(socket_fd, remaining_timeout_ms)
    on POLLIN/HUP/ERR: poll_drain_readable
  return poll_close(request, entry)   // depth--; restore watch; return/throw
```

- 🔷 Nested send does **not** rely on the outer frame scanning `pending` for “first unsent”. Outer sent A before it polls; when invoke fires, **inner** `call_poll` enqueues B and sends B on **its own** frame entry — that is the queue recursion. (Flat “scan first unsent” each loop iteration is the `call_sync` workaround; poll path should not copy it.)
- 🔷 Nested `call_poll` is **stack recursion** into another wait loop — no `GSource` re-dispatch, so no `G_HOOK_FLAG_IN_CALL` skip.
- 🔷 `complete_pending`: when `poll_depth > 0`, do **not** `send_head.begin()`; poll waiter observes `done_response` on the next loop check.
- 🚫 Replacing or deleting `call_sync` in this plan (follow-up after gnome-shell-rpc ✅).
- 🚫 Runtime guards for mixing `call_sync` and `call_poll` — consumer picks one API.
- 🚫 Dual-socket / protocol changes.
- 🚫 New `reply_invoke` API — trampoline stays `call_poll(RPC-Live-Callback.reply, …)`.

---

## Phase 1 — `libocrpc/Client.vala`

### 1. `libocrpc/Client.vala` — field: `poll_depth`

**Why:** Track poll-mode wait nesting and outer lifecycle (read-watch teardown) without a `MainLoop`.

**Where:** private fields next to `sync_depth` / `sync_loop`.

**Depends on:** none.

#### Add — after `sync_depth` field declaration.

```vala
		/** Nesting depth of {@link call_poll} (0 = idle). */
		private int poll_depth = 0;
```

### 2. `libocrpc/Client.vala` — `complete_pending`: poll waiters

**Why:** Poll loop does not use `sync_loop.quit()`; must not kick `send_head.begin()` while a poll frame is open.

**Where:** `complete_pending`, branch after `entry.promise.set_value`.

**Depends on:** §1.

#### Remove

```vala
				if (this.sync_loop != null) {
					this.sync_loop.quit();
				} else {
					this.send_head.begin();
				}
```

#### Replace with

```vala
				if (this.sync_loop != null) {
					this.sync_loop.quit();
				} else if (this.poll_depth == 0) {
					this.send_head.begin();
				}
```

### 3. `libocrpc/Client.vala` — `poll_close`: frame teardown + return

**Why:** Replaces `try` / `finally` — `call_poll` always ends with `return this.poll_close(request, entry);`.

**Where:** class body — immediately after `call_sync` (before `call_poll`).

**Depends on:** §1.

#### Add — private method after `call_sync` closing brace.

```vala
		/**
		 * Leave one {@link call_poll} frame and return its
		 * response.
		 *
		 * Depth--, outer restores async read watch, then same
		 * return/throw tail as {@link call_sync}.
		 */
		private Response poll_close(Request request, PendingWrite entry) throws GLib.Error
		{
			this.poll_depth--;
			if (this.poll_depth == 0 && this.connected && this.read_channel != null) {
				this.read_watch_id = this.read_channel.add_watch(
					GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
					this.on_read
				);
				if (this.pending.size > 0 && !this.pending.get(0).sent) {
					this.send_head.begin();
				}
			}
			if (entry.done_response == null) {
				throw new GLib.IOError.FAILED("call ended without response");
			}
			if (entry.done_response.error == null) {
				return entry.done_response;
			}
			GLib.warning("%s id=%d: %s",
				request.method, request.id, entry.done_response.error.message);
			this.failed(request, entry.done_response.error);
			var quark = GLib.Quark.from_string(entry.done_response.error.domain);
			var code = entry.done_response.error.gerror_code;
			if (entry.done_response.error.domain == "") {
				quark = new RpcErrorCode.INTERNAL_ERROR("").domain;
				code = entry.done_response.error.code;
			}
			throw new GLib.Error.literal(quark, code, entry.done_response.error.message);
		}
```

### 4. `libocrpc/Client.vala` — `call_poll`: new public method

**Why:** Blocking RPC via manual poll/dispatch; alternative to MainLoop-based `call_sync`.

**Where:** class body — immediately after `poll_close`.

**Depends on:** §1, §2, §3, §5 (`poll_drain_readable` — apply §5 before build).

#### Add — full new method after `poll_close`.

```vala
		/**
		 * Blocking {@link call} using a manual socket poll loop.
		 *
		 * Same contract as {@link call_sync}: does not iterate the
		 * default {@link GLib.MainContext}; demuxes {@link Live.Invoke}
		 * and {@link Notification} while waiting; supports nested
		 * {@link call_poll} (e.g. invoke handler →
		 * ''RPC-Live-Callback.reply''). Socket / TCP only. Linux
		 * gnome-shell-rpc; not Windows or Android.
		 *
		 * Unlike {@link call_sync}, does not attach a private
		 * {@link GLib.MainLoop} or per-frame IO watch — nested waits
		 * recurse on the call stack and read with {@link GLib.poll}.
		 * Ends with {@code return this.poll_close(request, entry);}
		 * (no {@code try} / {@code finally}).
		 *
		 * @param request wire request; {@link Request.id} is set here
		 * @return wire response on success
		 * @throws GLib.Error same as {@link call_sync}
		 */
		public Response call_poll(Request request) throws GLib.Error
		{
#if ANDROID
			throw new GLib.IOError.FAILED("call_poll is not available");
#else
			if (this.protocol != Protocol.SOCKET && this.protocol != Protocol.TCP) {
				throw new GLib.IOError.FAILED("call_poll requires a socket protocol");
			}
			request.id = this.next_id++;
			if (!this.connected) {
				GLib.error("%s id=%d: not connected", request.method, request.id);
			}

			var entry = new PendingWrite(request);
			this.pending.add(entry);

			if (this.poll_depth == 0 && this.read_watch_id != 0) {
				GLib.Source.remove(this.read_watch_id);
				this.read_watch_id = 0;
			}
			this.poll_depth++;

			try {
				this.sending = true;
				GLib.debug("id=%d method=%s", entry.request.id, entry.request.method);
				this.bin.write(entry.request);
				this.output.flush(null);
				entry.sent = true;
				this.sending = false;
			} catch (GLib.Error e) {
				this.sending = false;
				this.complete_pending(entry.request.id, null, e);
			}

			int poll_fd = -1;
			var poll_source = new GLib.PollFD();
			if (this.read_channel != null) {
				poll_fd = this.read_channel.unix_get_fd();
				poll_source.fd = poll_fd;
				poll_source.events = GLib.IO_IN | GLib.IO_ERR | GLib.IO_HUP;
			}

			int64 deadline_us = 0;
			if (this.call_timeout_seconds > 0) {
				deadline_us = GLib.get_monotonic_time()
					+ (int64) this.call_timeout_seconds * GLib.USEC_PER_SEC;
			}

			while (entry.done_response == null) {
				if (deadline_us > 0 && GLib.get_monotonic_time() >= deadline_us) {
					GLib.warning("call timed out %s id=%d after %u s",
						entry.request.method, entry.request.id, this.call_timeout_seconds);
					this.complete_pending(
						entry.request.id, null, new GLib.IOError.TIMED_OUT("call timed out"));
					break;
				}
				if (this.read_channel != null && (this.read_channel.get_buffer_condition() & GLib.IOCondition.IN) != 0) {
					this.poll_drain_readable(this.read_channel);
				}
				if (entry.done_response != null) {
					break;
				}
				if (poll_fd < 0) {
					GLib.error("%s id=%d: poll socket fd missing", entry.request.method, entry.request.id);
				}
				var timeout_ms = -1;
				if (deadline_us > 0) {
					var remain_us = deadline_us - GLib.get_monotonic_time();
					if (remain_us <= 0) {
						continue;
					}
					timeout_ms = (int) (remain_us / 1000);
					if (timeout_ms == 0) {
						timeout_ms = 1;
					}
				}
				if (GLib.poll(poll_source, 1, timeout_ms) <= 0) {
					continue;
				}
				if ((poll_source.revents & GLib.IO_ERR) != 0 || (poll_source.revents & GLib.IO_HUP) != 0) {
					GLib.warning("socket closed socket_path=%s pending=%u",
						this.socket_path, this.pending.size);
					this.disconnect();
					break;
				}
				if ((poll_source.revents & GLib.IO_IN) == 0) {
					continue;
				}
				this.poll_drain_readable(this.read_channel);
				if (entry.done_response != null) {
					break;
				}
			}

			return this.poll_close(request, entry);
#endif
		}
```

### 5. `libocrpc/Client.vala` — `poll_drain_readable`: recursive bool drain

**Why:** `call_poll` must parse/dispatch identically to `on_read` without registering a `GSource`. One wire message per stack frame; **`return this.poll_drain_readable(source)`** when more `IN` remains. Returns **`true`** when the buffer is drained; propagates the recursive result.

**Where:** class body — immediately before `on_read`.

**Depends on:** none (apply before §4 compile).

#### Add — new private method before `on_read` docblock.

```vala
		/**
		 * Parse and dispatch buffered socket messages recursively.
		 *
		 * @param source RPC socket channel
		 * @return {@code true} when the buffer has no more readable data
		 */
		private bool poll_drain_readable(GLib.IOChannel source)
		{
			if (!this.connected || this.bin == null) {
				return true;
			}
			if ((source.get_buffer_condition() & GLib.IOCondition.IN) == 0) {
				return true;
			}
			try {
				var msg = this.bin.parse();
				this.dispatch_message(msg);
			} catch (GLib.IOError e) {
				GLib.error("%s", e.message);
			} catch (GLib.Error e) {
				GLib.error("%s", e.message);
			}
			if ((source.get_buffer_condition() & GLib.IOCondition.IN) != 0) {
				return this.poll_drain_readable(source);
			}
			return true;
		}
```

### 6. `libocrpc/Client.vala` — `on_read`: delegate drain to `poll_drain_readable`

**Why:** Same recursive drain as `call_poll`; single call (return ignored).

**Where:** `on_read` body — replace inner `do/while` parse loop.

**Depends on:** §5.

#### Remove

```vala
			do {
				if (!this.connected || this.bin == null) {
					break;
				}
				try {
					var msg = this.bin.parse();
					this.dispatch_message(msg);
				} catch (GLib.IOError e) {
					GLib.error("%s", e.message);
				} catch (GLib.Error e) {
					GLib.error("%s", e.message);
				}
			} while ((source.get_buffer_condition() & GLib.IOCondition.IN) != 0);
```

#### Replace with

```vala
			this.poll_drain_readable(source);
```

## Phase 2 — `tests/rpc/call-sync-poll-test.vala`

### 1. `tests/rpc/call-sync-poll-test.vala` — nested invoke + reply under poll

**Why:** Lock in mid-wait demux and nested `call_poll` without consumer repro.

**Where:** new test file; wire into `tests/rpc/meson.build` like `callback-test.vala`.

**Depends on:** Phase 1.

#### Add — new test (skeleton — implementer fills server loop to match `call-sync-repro` `flow`):

- 🔷 Spawn or attach loopback TCP / Unix test server (reuse `RpcTestAppBase` patterns from `tests/rpc/gi-test.vala` if present).
- 🔷 Server handler for method `RPC-Test.hold`: write `Live.Invoke` to client, block until `RPC-Live-Callback.reply`, then write `Response(hold)`.
- 🔷 Client: `rpc.invoke.connect((call) => { rpc.call_poll(reply_request); })`.
- 🔷 Client: `call_poll(hold_request)` completes without timeout.
- 🔷 Second case **💩** `flow+child`: invoke handler issues a child `call_poll` before trampoline reply — mirror consumer repro if cheap; otherwise defer to consumer verify only.

**Meson:** add executable + `test()` entry alongside `callback-test`.

---

## Phase 3 — consumer verify (out of tree)

- ✅ 🔷 gnome-shell-rpc: `GiStub.Runtime.do_call` → `call_poll` only.
- ✅ 🔷 `call-sync-repro` + nested mutter `remove_child` — pass on poll path.
- ✅ 🔷 Real shell layout pass (panel / nested window).

---

## Suggested order

1. Phase 1 §1 → §2 → §5 → §6 → §3 → §4 (build `libocrpc` after §6).
2. Phase 2 unit test.
3. Phase 3 consumer verify.

---

## Risks / open questions

- ℹ️ `GLib.poll` + `unix_get_fd()` — Linux gnome-shell-rpc / CI only; no Windows target for this path.
- ℹ️ Follow-up: remove MainLoop `call_sync` once gnome-shell-rpc is ✅ on `call_poll`.

## LLM notes

- Implement only Phase 1–2 unless user approves Phase 3 in-tree edits (gnome-shell-rpc is another repo).
- Named private helpers: `poll_close(request, entry)` (teardown + return/throw — replaces `try`/`finally`), `poll_drain_readable` (recursive `bool`; `return this.poll_drain_readable(source)` when more `IN`). Frame **open** stays inlined in `call_poll`.
