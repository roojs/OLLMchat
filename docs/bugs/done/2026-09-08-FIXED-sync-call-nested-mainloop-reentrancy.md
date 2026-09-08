# Sync Client.call via nested MainLoop re-enters default context

**Status:** ✅ FIXED (OPC `call_sync` + consumer `do_call` → `call_sync`)  
**Hit:** 2026-09-08 — gnome-shell-rpc nested Wayland (`this._output is undefined`)  
**Consumer:** gnome-shell-rpc `GiStub.Runtime.do_call`  

---

## Symptom (consumer)

During `new OutputStreamSlider` (stock `volume.js`), sync RPC for Clutter/St construct runs a nested `GLib.MainLoop`. Gvc/`default-sink-changed` fires on the default context mid-call → JS handler runs while `this._output` is still unset.

## Cause

```vala
// gnome-shell-rpc src/gi-stub/Runtime.vala do_call
var call_loop = new GLib.MainLoop();
Runtime.client.call.begin(…, (obj, res) => { …; call_loop.quit(); });
call_loop.run();  // == iterate default MainContext until quit
```

`OLLMrpc.Client.call` is async on the default/thread-default context. Turning it sync by nesting `MainLoop.run()` dispatches **every** ready source (Pulse, Gvc, timeouts, idle), not only the RPC socket.

## Fix (OPC)

✔️ `Client.call_sync` — private `MainContext` + `IOSource.attach`; consumer `do_call` → `call_sync`.

## Follow-up

ℹ️ [call_sync Source.remove wrong context](../2026-09-08-call-sync-source-remove-wrong-context.md) — CRITICAL every call + hang ~RPC 55.
