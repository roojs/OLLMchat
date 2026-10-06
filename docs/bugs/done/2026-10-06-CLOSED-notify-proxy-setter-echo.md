# `notify::` apply calls the Live proxy setter

**Status:** 🚫 CLOSED — rejected for libocrpc. The compare belongs on the generated proxy in gnome-shell-rpc. `Client.vala` keeps applying a notify with `set_property`.

**Started:** 2026-10-06

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ `docs/bugs/done/2026-09-24-FIXED-notify-skips-type-override.md` — client apply is `set_property` of the notify value
- ℹ️ gnome-shell-rpc `docs/bugs/2026-10-05-boot-crash-and-logout-hang.md` — session deaths at 15:30, 09:29, and 10:09
- ℹ️ `gnome-shell-rpc/tests/call-sync-repro/notify-proxy-setter-echo-gate.vala`

---

## Problem

🔷 A server `notify::` on a Live proxy must update the value the client already holds.

🔷 One `notify::value` recurses until `gsr-client` segfaults. The shell logs `JS ERROR: too much recursion` from `workspace.js` `_updateBorderRadius`.

🚫 A guard in `workspace.js`, `St.Adjustment`, or any one listener. The next adjustment that notifies takes the same path.

---

## Evidence

✔️ Gate. The proxy setter only counts calls. One server `notify::visible`:

```bash
meson compile -C build tests/call-sync-repro/notify-proxy-setter-echo-gate
timeout 5 ./build/tests/call-sync-repro/notify-proxy-setter-echo-gate
```

```text
FAIL notify-proxy-setter-echo-gate: notify called outbound setter 1 time(s)
```

✔️ Installed session, user `alan2`, 2026-10-06 10:08:59. Opening the app grid assigns `fitModeAdjustment.value` (`overviewControls.js` `_update`). The client log is `notify::value` then `St-Adjustment.set_value`, about every 0.27ms, ids through 16529, 2396 notifies and 2443 sets. Then:

```text
JS ERROR: too much recursion
_updateBorderRadius@resource:///org/gnome/shell/ui/workspace.js:1002
```

`gsr-client` 690523 SIGSEGV at 10:09:01.

✔️ 09:29 core of client 595001. No JS on the stack. The frames are the chain in the next section.

Apply site, `libocrpc/Client.vala`:

```vala
this.proxies.get(notif.id).set_property(
    prop_name,
    notif.args.get(0)
);
```

---

## Root cause

✔️ The **client** is `gsr-client`. Shell JavaScript and the generated proxies run in that process. The **server** is `gsr-server`. The real `St.Adjustment` runs in that process.

`st_adjustment_set_value` is a function name in both. On the client it is the generated setter. On the server it is `vendor/gnome-shell/src/st/st-adjustment.c`. They are not the same function.

This is the order. The 09:29 core is only the client frames. The server steps run in the other process while the client is still inside `call_poll`.

### 1. Client — shell JavaScript sets the value

`overviewControls.js` `_update` assigns `fitModeAdjustment.value`. That object is the generated proxy.

### 2. Client — the proxy setter sends the RPC

`g_object_set_property` runs the generated setter, compiled as `st_adjustment_set_value`. It does not store the double. It calls `Gsr.Client.Rpc.call_value("St-Adjustment.set_value")`, which blocks in `Client.call_poll` until the reply arrives.

### 3. Server — the real adjustment stores it and may notify

`St-Adjustment.set_value` runs `st_adjustment_set_value` in `st-adjustment.c`. Same bits: return, no notify. Different bits: store, then `g_object_notify_by_pspec`.

### 4. Server — `Subscription` writes `notify::value`

`libocrpc/Live/Subscription.vala` is connected to that `notify`. It reads the property and writes the notification on the socket.

### 5. Client — `call_poll` reads the notification before the reply

`call_poll` from step 2 is still on the stack. `dispatch_message` sees `notify::value`, not the `set_value` reply, and applies it:

```vala
/* client, libocrpc/Client.vala */
this.proxies.get(notif.id).set_property(
    prop_name,
    notif.args.get(0)
);
```

### 6. Client — that `set_property` is step 2 again

The generated setter calls `call_poll` again. The 09:29 core is this loop, with no JavaScript on the stack:

```text
g_object_set_property                 client, step 5 apply
st_adjustment_set_value               client, step 2 generated setter
oll_mrpc_client_call_poll             client, still inside that setter
oll_mrpc_client_dispatch_message      client, step 5 again
g_object_set_property                 client, step 2 again
```

`workspace.js` `_updateBorderRadius` also runs on the **client**, on the proxy's own `notify::value`. That is the `JS ERROR: too much recursion`. Same loop. Not a third process.

---

## What the original adjustment does

ℹ️ `gnome-shell-rpc/vendor/gnome-shell/src/st/st-adjustment.c`

One process. JavaScript and `St.Adjustment` are both gnome-shell. There is no RPC, and `call_poll` is not on the stack. `value` is `G_PARAM_EXPLICIT_NOTIFY`, so GObject does not emit `notify` just because `set_property` returned. The only `notify::value` is the one inside the setter.

### 1. Shell — JavaScript assigns `adjustment.value`

Same process. The object is the real `St.Adjustment`, and the double is stored on it.

### 2. Shell — `set_property` calls `st_adjustment_set_value`

`st_adjustment_set_property` handles `PROP_VALUE` by calling `st_adjustment_set_value`.

### 3. Shell — the setter drops an unchanged value before notify

```c
if (priv->value != value) {
    priv->value = value;
    g_object_notify_by_pspec (G_OBJECT (adjustment), props[PROP_VALUE]);
}
```

Same bits: return. No `notify::value`. Handlers do not run. The chain stops here.

Different bits: store, then notify. A handler that writes those same bits back hits this compare and stops.

`G_PARAM_EXPLICIT_NOTIFY` is what keeps GObject from emitting a second `notify` after that return. Without it, `set_property` would notify even when `priv->value` did not change, and a handler that wrote the value back would loop inside this one process.

The generated client setter has no `priv->value`. Step 5 of the RPC loop calls that setter, so the compare the original uses never runs on the client.

---

## Proposed fix

🔷 Both ends drop a write when the value is already that value. A real change still goes through the setter once. The copy that comes back does not.

This is not libocrpc's compare. `Client.vala` applies a notify with `set_property`. That is the call the original adjustment already receives. The original then stops inside `st_adjustment_set_value`, because that object holds `priv->value`. On the client, the object that is missing that field is the generated proxy.

🚫 A remembered value in `libocrpc/Client.vala`, and skipping `set_property` from `dispatch_message`. That moves the adjustment's compare into the RPC library. `Subscription.vala` only forwards a notify the server setter already emitted. A second compare there does not see an echo `st_adjustment_set_value` already dropped.

🚫 Skipping `set_property` on every notify. The gate's header says the pass bar is `outbound_sets == 0`, which is this idea. A changed value has to reach the peer through the setter.

### Client — generated setter, step 2

On the **client**, in gnome-shell-rpc. The generated `St.Adjustment.value` setter needs a field, the same role as `priv->value`.

Same bits: return. No `call_poll`. Step 5 still called `set_property`. The setter is what stops.

Different bits: store, then `St-Adjustment.set_value`.

Reading `.value` to compare would RPC `get_value` and return the value the notify just carried, so that compare always looks unchanged. The field is the memory. It is not a get.

Doubles and floats are raw bits in `libocrpc/Bin/StreamValue.vala` (`Memory.copy` of 8 and 4 bytes). Compare the field by the bits. `NaN != NaN`, so a `!=` compare treats one NaN as a new value forever. `+0` and `-0` compare equal under `!=`. A bit compare treats them as different. A real store of `-0` is a different write.

### Server — already step 3

On the **server**. Already in gnome-shell, not in libocrpc:

```c
/* server, vendor/gnome-shell/src/st/st-adjustment.c */
if (priv->value != value) {
    priv->value = value;
    g_object_notify_by_pspec (G_OBJECT (adjustment), props[PROP_VALUE]);
}
```

Same bits: step 4 does not run. Step 5 reads the method reply. `call_poll` from step 2 returns. One extra `set_value` when the client's field did not yet match, then the stack unwinds.

Where `!=` cannot see NaN, this compare has to be by bits. Stock `set_value` does not do that.

### What this does not stop

💩 A hop whose double actually differs. Overview `_update` assigns `fitModeAdjustment.value`. That notify runs `_updateWorkspacesState`, which assigns `w.stateAdjustment.value`. Those are real changes and must still propagate once. The 10:09 pairing is a notify produced while `set_value` is still waiting. Stock `set_value` should have refused it if the bits matched. The log does not include the double, so a changing value and a NaN echo both still fit.

💩 Clamp that oscillates. Set A stores B, set B stores A. Each hop differs, so both compares let it through.

### Gate

The current peer is a Vala `bool`. Setting `visible` to the value it already holds does not notify, so the gate never builds the loop. It only shows one real `false` → `true`.

🔷 Pass becomes: a changed value calls the setter once, and a second notify with the same bits calls it zero more times. That setter is the generated proxy, which stores the value and returns when it matches. The gate changes with that setter, not with `Client.vala`.

---

## Decision

🚫 Not a libocrpc change. Archived 2026-10-06.

The follow-up is the generated setter in gnome-shell-rpc: hold the value, and return before `call_poll` when the bits already match. That is not tracked in this file.
