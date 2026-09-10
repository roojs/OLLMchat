# `call_sync` wait is not a demuxing flow for mid-request Live.Invoke

**Status:** ✔️ FIXED (OPC same-pump reenter applied)  
**Hit:** 2026-09-09 — gnome-shell-rpc nested Wayland chrome layout  
**Component:** `libocrpc` / `Client.call_sync` + `complete_pending`  
**Consumer:** gnome-shell-rpc `GiStub.Runtime` / layout `Live.Hook.emit`  
**Related:** [FIXED sync-call nested MainLoop](2026-09-08-FIXED-sync-call-nested-mainloop-reentrancy.md) (private context — keep)

---

## Symptom (consumer)

🔷 Server handles Request(A) and, before writing Response(A), pushes `Live.Invoke`(B) (layout preferred/allocate hooks via `Hook.emit`). Client is inside `call_sync(A)` on the private sync context:

1. `on_read` → `dispatch_message` → `invoke(B)` runs **on the private wait**.
2. Handler / trampoline often needs another RPC (`RPC-Live-Callback.reply`, or child GI calls).
3. Second `call_sync` → **`nested call_sync is not supported`**.
4. Consumer workarounds (queue invoke, Idle reply on default) **deadlock or hang** with `Hook.emit` (server blocked until trampoline reply; client will not reply until A finishes / default is pumped).

Chrome layout never converges (panel piled / blank nested window).

## Cause

✔️ `call_sync` correctly avoids nesting the **default** MainLoop (volume/`_output` race). But the wait is still modeled as:

```text
write Request(A) → pump private ctx until Response(A)
```

On the wire, A’s conversation is actually:

```text
Request(A)
  … Live.Invoke(B) …          ← intermediary (signal-like call)
  … Notification …            ← possible
Response(A)
```

`dispatch_message` already delivers Invoke during the private pump (`invoke` signal). The hard forbid is:

```vala
if (this.sync_loop != null) {
    throw new GLib.IOError.FAILED("nested call_sync is not supported");
}
```

That forbids the **wrong** kind of nesting (second private loop / default nest) **and** the **required** kind: reenter the **same** private pump for child Requests (trampoline `RPC-Live-Callback.reply`, allocate GI children) while A is still open.

`complete_pending` only `quit()`s when `id == sync_id` (outer A). A child Response(B) would never wake a nested waiter even if the forbid were lifted without also quitting on any in-flight sync completion.

🔷 This is not “re-open default-context nesting.” It is “Request wait must demux intermediaries in-flow; child `call_sync` reuses the open private pump.”

## Pure-GLib proof (consumer)

ℹ️ `gnome-shell-rpc/tests/call-sync-repro/`:

| Mode | Result |
|------|--------|
| `broken-nested` / `broken-queue` / `broken-idle` | fail / hang (today’s traps) |
| **`flow`** | PASS — demux Invoke in the wait; trampoline replied **in-flow** |
| **`flow+child`** | PASS — child request reuses the **same private pump** (`depth++`) |

Server order under test matches production: **emit Invoke, then Response**.

Mapped to OPC: trampoline reply is itself a Request/Response (`RPC-Live-Callback.reply`), so both `flow` and `flow+child` need the same fix — **same-private-context reenter of `call_sync`**. No separate fire-and-forget `reply_invoke` API.

## Proposed fix

🔷✔️ Same-private-context reenter of `call_sync` (approved + applied). Nested waits reuse `sync_loop`; only the outer frame creates/destroys it. `complete_pending` always `quit()`s mid-sync.

```text
call_sync(A):                    // outer — create private ctx
  write Request(A)
  while A not done:
    demux on private pump
      Live.Invoke(B) → invoke handler
        call_sync(reply/child)   // nested — same sync_loop, depth++
      Response(A) → done
```

🚫 Do **not** invent `reply_invoke` / helper methods — trampoline reply stays `call_sync(RPC-Live-Callback.reply, …)`.
🚫 Do **not** `push_thread_default` (prior hang fix stays).
🚫 Do **not** create a second `MainContext` / `MainLoop` when `sync_loop != null`.

### 1. `libocrpc/Client.vala` — fields: `sync_id` → `sync_depth`

**Why:** Outer/nested share one loop; depth decides who tears it down. `sync_id` only gated `quit()` and becomes wrong under reenter.

**Where:** private fields next to `sync_loop`.

**Depends on:** none.

#### Remove

```vala
		/** Non-null while {@link call_sync} runs a private {@link GLib.MainLoop}. */
		private GLib.MainLoop? sync_loop;
		private int sync_id = 0;
```

#### Replace with

```vala
		/** Non-null while {@link call_sync} runs a private {@link GLib.MainLoop}. */
		private GLib.MainLoop? sync_loop;
		/** Nesting depth of {@link call_sync} on {@link sync_loop} (0 = idle). */
		private int sync_depth = 0;
```

### 2. `libocrpc/Client.vala` — `complete_pending`: quit any mid-sync completion

**Why:** Nested waiters finish on Response(B) while outer `sync_id` would still be A; any completion must wake the private pump. Spurious wake when an unrelated pending completes is fine — waiters re-check `done_response`.

**Where:** `complete_pending`, the `sync_loop` / `send_head` branch after promise resolution.

**Depends on:** §1.

#### Remove

```vala
				if (this.sync_loop != null) {
					if (id == this.sync_id) {
						this.sync_loop.quit();
					}
				} else {
					this.send_head.begin();
				}
```

#### Replace with

```vala
				if (this.sync_loop != null) {
					this.sync_loop.quit();
				} else {
					this.send_head.begin();
				}
```

### 3. `libocrpc/Client.vala` — `call_sync`: same-pump reenter

**Why:** Match consumer `flow` / `flow+child`. Outer owns context lifecycle; nested only enqueues + pumps until its own Response.

**Where:** whole `call_sync` method body (docblock + implementation).

**Depends on:** §1, §2.

#### Remove

```vala
		/**
		 * Blocking {@link call} that does not iterate the default
		 * {@link GLib.MainContext}.
		 *
		 * Attaches the read watch (and call timeout) to a private context
		 * and runs only that loop until this request completes. Does not
		 * {@link GLib.MainContext.push_thread_default} — that would steal
		 * Clutter/GJS idles onto the private context and drop them on
		 * teardown. Sends with a blocking flush so {@link send_head} is
		 * not required mid-call. Socket / TCP only.
		 *
		 * @param request wire request; {@link Request.id} is set here
		 * @return wire response on success
		 * @throws GLib.Error same as {@link call}
		 */
		public Response call_sync(Request request) throws GLib.Error
		{
#if ANDROID
			throw new GLib.IOError.FAILED("call_sync is not available");
#else
			if (this.protocol != Protocol.SOCKET && this.protocol != Protocol.TCP) {
				throw new GLib.IOError.FAILED("call_sync requires a socket protocol");
			}
			if (this.sync_loop != null) {
				throw new GLib.IOError.FAILED("nested call_sync is not supported");
			}
			request.id = this.next_id++;
			if (!this.connected) {
				GLib.error("%s id=%d: not connected", request.method, request.id);
			}

			var entry = new PendingWrite(request);
			this.pending.add(entry);

			if (this.read_watch_id != 0) {
				GLib.Source.remove(this.read_watch_id);
				this.read_watch_id = 0;
			}

			this.sync_loop = new GLib.MainLoop(new GLib.MainContext(), false);
			this.sync_id = request.id;
			var sync_watch = this.read_channel.create_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR
			);
			sync_watch.set_callback(this.on_read);
			sync_watch.attach(this.sync_loop.get_context());
			GLib.Source? timeout_source = null;
			if (this.call_timeout_seconds > 0) {
				timeout_source = new GLib.TimeoutSource.seconds(this.call_timeout_seconds);
				timeout_source.set_callback(() => {
					GLib.warning("call timed out %s id=%d after %u s",
						entry.request.method, entry.request.id, this.call_timeout_seconds);
					this.complete_pending(
						entry.request.id, null, new GLib.IOError.TIMED_OUT("call timed out"));
					return false;
				});
				timeout_source.attach(this.sync_loop.get_context());
			}
			try {
				while (entry.done_response == null) {
					if (!this.sending && this.pending.size > 0 && !this.pending.get(0).sent) {
						var head = this.pending.get(0);
						this.sending = true;
						GLib.debug("id=%d method=%s", head.request.id, head.request.method);
						this.bin.write(head.request);
						this.output.flush(null);
						head.sent = true;
						this.sending = false;
						continue;
					}
					if (entry.done_response != null) {
						break;
					}
					this.sync_loop.run();
				}
			} catch (GLib.Error e) {
				this.sending = false;
				this.complete_pending(
					this.pending.size > 0 ? this.pending.get(0).request.id : entry.request.id,
					null, e);
			} finally {
				if (timeout_source != null) {
					timeout_source.destroy();
				}
				sync_watch.destroy();
				this.sync_loop = null;
				this.sync_id = 0;
				if (this.connected && this.read_channel != null) {
					this.read_watch_id = this.read_channel.add_watch(
						GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
						this.on_read
					);
					if (this.pending.size > 0 && !this.pending.get(0).sent) {
						this.send_head.begin();
					}
				}
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
#endif
		}
```

#### Replace with

```vala
		/**
		 * Blocking {@link call} that does not iterate the default
		 * {@link GLib.MainContext}.
		 *
		 * Attaches the read watch (and call timeout) to a private context
		 * and runs only that loop until this request completes. Does not
		 * {@link GLib.MainContext.push_thread_default} — that would steal
		 * Clutter/GJS idles onto the private context and drop them on
		 * teardown. Sends with a blocking flush so {@link send_head} is
		 * not required mid-call. Socket / TCP only.
		 *
		 * While an outer wait is open, a nested {@link call_sync} (e.g.
		 * {@link Live.Invoke} handler → ''RPC-Live-Callback.reply'' or a
		 * child GI request) reuses the same private loop; it must not
		 * iterate the default context. Handlers run on that private
		 * context.
		 *
		 * @param request wire request; {@link Request.id} is set here
		 * @return wire response on success
		 * @throws GLib.Error same as {@link call}
		 */
		public Response call_sync(Request request) throws GLib.Error
		{
#if ANDROID
			throw new GLib.IOError.FAILED("call_sync is not available");
#else
			if (this.protocol != Protocol.SOCKET && this.protocol != Protocol.TCP) {
				throw new GLib.IOError.FAILED("call_sync requires a socket protocol");
			}
			request.id = this.next_id++;
			if (!this.connected) {
				GLib.error("%s id=%d: not connected", request.method, request.id);
			}

			var entry = new PendingWrite(request);
			this.pending.add(entry);

			var outer = (this.sync_loop == null);
			GLib.IOSource? sync_watch = null;
			GLib.Source? timeout_source = null;
			if (outer) {
				if (this.read_watch_id != 0) {
					GLib.Source.remove(this.read_watch_id);
					this.read_watch_id = 0;
				}
				this.sync_loop = new GLib.MainLoop(new GLib.MainContext(), false);
				sync_watch = this.read_channel.create_watch(
					GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR
				);
				sync_watch.set_callback(this.on_read);
				sync_watch.attach(this.sync_loop.get_context());
				if (this.call_timeout_seconds > 0) {
					timeout_source = new GLib.TimeoutSource.seconds(this.call_timeout_seconds);
					timeout_source.set_callback(() => {
						GLib.warning("call timed out %s id=%d after %u s",
							entry.request.method, entry.request.id, this.call_timeout_seconds);
						this.complete_pending(
							entry.request.id, null, new GLib.IOError.TIMED_OUT("call timed out"));
						return false;
					});
					timeout_source.attach(this.sync_loop.get_context());
				}
			}
			this.sync_depth++;
			try {
				while (entry.done_response == null) {
					if (!this.sending && this.pending.size > 0 && !this.pending.get(0).sent) {
						var head = this.pending.get(0);
						this.sending = true;
						GLib.debug("id=%d method=%s", head.request.id, head.request.method);
						this.bin.write(head.request);
						this.output.flush(null);
						head.sent = true;
						this.sending = false;
						continue;
					}
					if (entry.done_response != null) {
						break;
					}
					this.sync_loop.run();
				}
			} catch (GLib.Error e) {
				this.sending = false;
				this.complete_pending(
					this.pending.size > 0 ? this.pending.get(0).request.id : entry.request.id,
					null, e);
			} finally {
				this.sync_depth--;
				if (outer) {
					if (timeout_source != null) {
						timeout_source.destroy();
					}
					if (sync_watch != null) {
						sync_watch.destroy();
					}
					this.sync_loop = null;
					if (this.connected && this.read_channel != null) {
						this.read_watch_id = this.read_channel.add_watch(
							GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
							this.on_read
						);
						if (this.pending.size > 0 && !this.pending.get(0).sent) {
							this.send_head.begin();
						}
					}
				}
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
#endif
		}
```

## Non-goals

- 🚫 Reverting private-context `call_sync` (volume fix stays).
- 🚫 Allowing nested `call_sync` that pumps the default context.
- 🚫 Requiring consumers to queue Live.Invoke until Response(A) (proven deadlock with sync `Hook.emit`).
- 🚫 New `reply_invoke` / fire-and-forget write API (reply stays `call_sync`).
- 🚫 Changing server `Hook.emit`; inventing GI APIs; consumer Idle flags in widget peers.

## Prove (after OPC change)

⏳ Consumer nested `mutter-rpc --wayland --nested`:

1. Zero `nested call_sync is not supported` on Live.Invoke reply path.
2. Reach `Meta-Context.notify_ready`.
3. Panel / chrome not piled top-left (JS preferred+allocate hooks can complete).

ℹ️ Consumer unit: `tests/call-sync-repro` modes `flow` / `flow+child` remain the behavioral spec.

## Next

- Consumer: use in-flow `call_sync` for Live.Invoke reply (not Idle on default).
- Nested mutter prove remains the device check; promote ✅ when verified on device.

## References

- Consumer bug: `gnome-shell-rpc/docs/bugs/2026-09-09-layout-relay-call-sync-reentrancy.md`
- Repro README: `gnome-shell-rpc/tests/call-sync-repro/README.md`
- OPC `Client.call_sync` / `dispatch_message` (`Live.Invoke` → `invoke` mid-wait)
