# `call_sync` head-only send blocks nested Request

**Status:** ✅ fixed — consumer verified on gnome-shell-rpc  
**Hit:** 2026-09-09 — gnome-shell-rpc nested Wayland (`remove_child` 120s)  
**Component:** `libocrpc` / `Client.call_sync` pending send loop  
**Consumer:** gnome-shell-rpc layout `Live.Invoke` → `RPC-Live-Callback.reply`  
**Related:** [FIXED mid-wait Live.Invoke flow](done/2026-09-09-FIXED-call-sync-mid-wait-live-invoke-flow.md) (nested same-pump — keep; this was the remaining send-policy gap)

---

## Symptom

🔷 Consumer is inside `call_sync(A)` (e.g. `Clutter-Actor.remove_child`). Server
`Hook.emit` delivers `Live.Invoke`; handler starts nested `call_sync(B)`
(`RPC-Live-Callback.reply` or child GI).

**B is enqueued but never written** until A hits the call timeout. Then B is
sent — reply appears only after abort.

Consumer log:

```
recv remove_child id=44
… 120s silence …
call timed out Clutter-Actor.remove_child id=44 after 120 s
id=45 method=RPC-Live-Callback.reply    ← first write after timeout
```

Pure-gio proof in consumer `tests/call-sync-repro/`:

| Mode | Result |
|------|--------|
| `opc-head` | FAIL — head-only send (this bug) |
| `same-pump` | PASS — write first unsent |

## Cause

✔️ `call_sync` wait loop only wrote when **head** was unsent:

```vala
if (!this.sending && this.pending.size > 0 && !this.pending.get(0).sent) {
    var head = this.pending.get(0);
    // write head …
}
```

After A is written, `pending[0].sent == true` while A still waits. Nested B
is `pending[1]` with `sent == false`. Condition never wrote B until A was
removed (timeout / `complete_pending`).

Same-pump `sync_depth` reenter was applied; **send policy still blocked
pipelining** behind an in-flight head.

## Fix

🔷 Write the **first unsent** pending entry (not only an unsent head). Keep
private-pump nested `call_sync`, no `push_thread_default`, `complete_pending`
quits mid-sync on any completion.

### 1. `libocrpc/Client.vala` — `call_sync` wait loop: first unsent

**Why:** Nested B must go on the wire while A is still in flight (Hook.emit
waits on reply before Response(A)).

**Where:** `call_sync`, the `while (entry.done_response == null)` send branch.

**Depends on:** none.

#### Remove

```vala
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
```

#### Replace with

```vala
				while (entry.done_response == null) {
					if (!this.sending && this.pending.size > 0) {
						var sent_one = false;
						for (var i = 0; i < this.pending.size; i++) {
							var p = this.pending.get(i);
							if (p.sent) {
								continue;
							}
							this.sending = true;
							GLib.debug("id=%d method=%s", p.request.id, p.request.method);
							this.bin.write(p.request);
							this.output.flush(null);
							p.sent = true;
							this.sending = false;
							sent_one = true;
							break;
						}
						if (sent_one) {
							continue;
						}
					}
					if (entry.done_response != null) {
						break;
					}
					this.sync_loop.run();
				}
```

## Non-goals

- 🚫 New `reply_invoke` API — trampoline stays `call_sync(RPC-Live-Callback.reply)`
- 🚫 Re-opening default MainLoop nesting
- 🚫 Changing async `send_head` (still head-only; queue advances on `complete_pending`)

## Conclusion

✅ First-unsent send policy verified; gnome-shell-rpc nested `remove_child` no
longer blocks behind head-only send.
