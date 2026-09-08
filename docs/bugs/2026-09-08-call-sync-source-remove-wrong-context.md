# call_sync: Source.remove on private-context watch → CRITICAL + consumer hang

**Status:** ✔️ OPC fix applied (consumer prove ⏳)  
**Hit:** 2026-09-08 ~20:55–20:56 — gnome-shell-rpc nested Wayland after `do_call` → `call_sync`  
**Related:** [nested MainLoop / call_sync API](done/2026-09-08-FIXED-sync-call-nested-mainloop-reentrancy.md)  
**Consumer:** gnome-shell-rpc `GiStub.Runtime.do_call`  

---

## Symptom (consumer)

After switching `Runtime.do_call` to `Client.call_sync`:

1. **Every** sync call logs:
   ```
   G_LOG_LEVEL_CRITICAL : Source ID 1 was not found when attempting to remove it
   ```
2. Nested Wayland boots ~50–55 RPCs then **stalls** (process alive, no further `Client.vala` send). Last seen:
   ```
   id=55 method=Clutter-Actor.add_constraint
   replied id=55
   ```
   Never reaches panel / volume (`this._output` path unproven).

Log: `~/.cache/gnome-shell-rpc/org.gnome.ShellRpc.debug.log` (2026-09-08 ~20:56).

## Cause

✔️ `call_sync` attached the read watch to a **private** `MainContext`, then cleaned up with `GLib.Source.remove(id)`. That API only removes from the **default** main context — CRITICAL every call; private watch / default restore wrong → hang.

## Fix (OPC)

🔷 Keep the `IOSource` / timeout `Source` and `destroy()` them (context-correct). Do not `Source.remove` private attach ids. Do not store the private attach id in `read_watch_id`.

✔️ Applied in `libocrpc/Client.vala` `call_sync`:
- `sync_watch.attach(private)` then `sync_watch.destroy()` in `finally`
- `TimeoutSource.seconds` attached to the private context; `destroy()` in `finally`
- Default `add_watch` restored only after private sources are destroyed

## Prove

⏳ gnome-shell-rpc nested (~5–10s): no per-call `Source ID … was not found`; RPC continues past layout constraints into panel/volume; stock `volume.js` with no `this._output is undefined`.
