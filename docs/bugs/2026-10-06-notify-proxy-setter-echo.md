# `notify::` apply calls the Live proxy setter

**Status:** ⏳ open. FAIL gate already red.

**Started:** 2026-10-06

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ `docs/bugs/done/2026-09-24-FIXED-notify-skips-type-override.md` — client apply is `set_property` of the notify value
- ℹ️ gnome-shell-rpc `docs/bugs/2026-10-05-boot-crash-and-logout-hang.md` — session deaths 15:30, 09:29, and 10:09
- ℹ️ Consumer gate: `gnome-shell-rpc/tests/call-sync-repro/notify-proxy-setter-echo-gate.vala`

---

## Problem

🔷 A server `notify::` on a Live proxy must update the value the client already holds.

🔷 `Client.vala` applies it with `proxy.set_property`. On a generated gnome-shell-rpc proxy that setter is the outbound RPC, not local storage.

🔷 One `notify::value` therefore sends `St-Adjustment.set_value`. The server writes the property again and emits `notify::value` again. `call_poll` reads that notify before `set_value` returns, so the apply is still on the stack.

🔷 The client recurses until it segfaults. The shell's own `notify::value` handlers run on the way and log `JS ERROR: too much recursion`.

🚫 A guard in `workspace.js`, `St.Adjustment`, or any one listener. The next adjustment that notifies takes the same path.

---

## Evidence

```bash
meson compile -C build tests/call-sync-repro/notify-proxy-setter-echo-gate
timeout 5 ./build/tests/call-sync-repro/notify-proxy-setter-echo-gate
```

The proxy setter only counts calls. One server `notify::visible` produces:

```text
FAIL notify-proxy-setter-echo-gate: notify called outbound setter 1 time(s)
```

Installed session, user `alan2`, 2026-10-06 10:08:59. Opening the app grid assigns `fitModeAdjustment.value` (`overviewControls.js` `_update`). The client log is `notify::value` then `St-Adjustment.set_value`, repeating, then:

```text
JS ERROR: too much recursion
_updateBorderRadius@resource:///org/gnome/shell/ui/workspace.js:1002
```

`gsr-client` 690523 SIGSEGV at 10:09:01. The 09:29 core of client 595001 is the C loop: `g_object_set_property` → `st_adjustment_set_value` → `oll_mrpc_client_call_poll` → `oll_mrpc_client_dispatch_message` → `g_object_set_property`.

`libocrpc/Client.vala` apply:

```vala
this.proxies.get(notif.id).set_property(
    prop_name,
    notif.args.get(0)
);
```

---

## Fix

Apply the notify onto local storage. Do not call the proxy's public setter. The gate passes when the typed notify arrives and `outbound_sets` stays 0.
