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

🔷 Both ends drop a write when the value is already that value. A real
change still goes through the setter once. The copy that comes back
the other way does not.

🚫 Apply the notify by skipping `set_property` entirely. That was the
earlier proposal in this file. A changed value has to reach the peer
through the setter. Skipping every setter also makes the current gate's
`outbound_sets == 0` the pass bar, and that bar is the wrong one for
this design.

### Client

`Client.vala` apply is `proxy.set_property(prop_name, notif.args.get(0))`
(or the `TypeOverride` unpack, then the same `set_property`). On a
generated gnome-shell-rpc proxy that setter is the outbound RPC. The
generated `value` set block does not keep a field. Reading `.value` to
compare would RPC `get_value`, and that returns the server's current
value, which is the value the notify just carried, so the compare would
always look unchanged.

Compare against the last value this proxy property already applied.
Missing or different → `set_property` once, and remember it. Same value
→ do not call `set_property`.

Doubles and floats are copied as raw bits in `Bin/StreamValue.vala`
(`Memory.copy` of 8 and 4 bytes), so a normal number round-trips.
Compare those by the bits. `NaN != NaN` is true in IEEE, so a `!=`
compare treats one NaN as a new value forever. `+0` and `-0` already
compare equal under `!=`; bit compare treats them as different, which
is acceptable here because a real store of `-0` is a different write.

### Server

Do not emit `notify::` when the stored value did not change.
`st_adjustment_set_value` already does that
(`gnome-shell-rpc/vendor/gnome-shell/src/st/st-adjustment.c`):

```c
if (priv->value != value) {
    priv->value = value;
    g_object_notify_by_pspec (G_OBJECT (adjustment), props[PROP_VALUE]);
}
```

Vala properties do the same before `g_object_notify`.
`Live/Subscription.vala` writes the notification from that GObject
`notify`, after `get_property`. A second compare in `Subscription`
would not see a same-value `St.Adjustment` echo that the setter
already dropped. The server half is the setter's existing compare,
including a bit compare where `!=` cannot see NaN.

### What this stops

💩 A same-bits echo. The first notify still calls the setter, because
the client's remembered value differs. The server already holds that
value, so it does not notify again. `call_poll` then reads the method
reply and the stack unwinds. One extra `set_value`.

💩 The return trip, on the client, when a second notify carries the
same bits. That is the half stock `set_value` does not cover if the
server notifies anyway.

### What this does not stop

💩 A hop whose double is actually different. Overview `_update` assigns
`fitModeAdjustment.value`, that notify runs `_updateWorkspacesState`,
and that assigns `w.stateAdjustment.value`. Those are real changes and
must still propagate once. The 10:09 log is `notify::value` then
`St-Adjustment.set_value` about every 0.27ms, ids through 16529, 2396
notifies and 2443 sets, and the 09:29 core is
`set_property` → `st_adjustment_set_value` → `call_poll` →
`dispatch_message` → `set_property` with no JS on the stack. That
pairing is a notify produced while `set_value` is still waiting. Stock
`set_value` should have refused the second notify if the bits matched.
The logged lines do not include the double, so a changing value and a
NaN echo are both still open.

💩 Clamp that oscillates (set A stores B, set B stores A). Each hop
differs, so both compares let it through.

### Gate

The current gate's server peer is a Vala `bool`. Setting `visible`
to the value it already holds does not notify, so the gate never
builds the loop. It only shows that one real `false` → `true` calls
the outbound setter once:

```text
FAIL notify-proxy-setter-echo-gate: notify called outbound setter 1 time(s)
```

🔷 Pass becomes: a changed value calls the setter once, and a second
notify carrying the same bits calls it zero more times. `outbound_sets == 0`
is the pass bar for the rejected "never call the setter" fix. Change
the gate with the libocrpc change. Do not edit libocrpc until that
design is confirmed and the double from one 10:09-style pair is known.

⏳ Log the double on one `notify::value` / `set_value` pair before
writing the compare.
