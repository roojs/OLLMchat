# call_sync: consumer hangs mid-boot after RPC burst (no further calls)

**Status:** ✔️ done — consumer nested prove 2026-09-08 ~21:11  
**Hit:** 2026-09-08 ~21:04 nested Wayland (after Source.remove fix)  
**Related:** [Source.remove wrong context](done/2026-09-08-FIXED-call-sync-source-remove-wrong-context.md) (CRITICAL ✅)  
**Consumer:** gnome-shell-rpc `GiStub.Runtime.do_call` → `call_sync`  

---

## Symptom (consumer)

Nested `mutter-rpc --wayland --nested` (~12–15s):

- ✔️ No per-call `Source ID … was not found` (destroy fix).
- ❌ Client stops making RPCs after a short burst; process stays alive; compositor keeps getting pointer motion.
- Hang point varies by run (~id 24 early, or ~id 132 `Clutter-Actor.set_opacity` after `St-BoxLayout` / `hide` / `set_reactive`). Last line is **replied**, then silence — not a stuck in-flight `call_sync`.
- Never reaches panel / volume (`this._output` still unproven).

Log: `~/.cache/gnome-shell-rpc/org.gnome.ShellRpc.debug.log` (2026-09-08 ~21:04).

## Cause

💩 `call_sync` used `push_thread_default(private)`. While the private loop ran, Clutter/GJS/`Idle.add` / other thread-default sources were created on that private context. Teardown destroyed them → shell stopped scheduling the next JS work → no further `do_call` after the last reply.

## Fix (OPC)

🔷 Do **not** `push_thread_default`. Attach only the RPC read watch + call timeout to the private context. Sync-write/flush the pending head inside `call_sync` (do not `send_head.begin()` while `sync_loop` is set — that would land on the default context and never run mid-wait).

✔️ `libocrpc/Client.vala` `call_sync` / `complete_pending`:
- removed `push_thread_default` / `pop_thread_default`
- blocking `bin.write` + `output.flush` for unsent head
- `complete_pending` skips `send_head.begin()` when `sync_loop != null` (quits loop for `sync_id` only)

## Prove

✔️ Nested 2026-09-08 ~21:11: thousands of RPCs (max id ~4844), `Meta-Context.notify_ready`, no mid-burst stall, no `Source ID` CRITICAL.

Next consumer wall (separate): `Meta-BackgroundImageCache.load` → empty `-32602` / uncaught → shell exits during layout backgrounds.
