# `notify::` sends the property as a string in `Notification.message`

**Status:** ✔️ fixed — `test-rpc-subscribe` and `test-rpc-proxies` exit 0 (`args[0]` boolean `true`, `message` empty)  
**Hit:** 2026-09-24 — nested gnome-shell boot, `allocation` / `visible` / `checked`  
**Component:** `libocrpc` / `OLLMrpc.Live.Subscribe` + `OLLMrpc.Client`  
**Consumer gate:** `gnome-shell-rpc/tests/call-sync-repro/subscribe-notify-args-gate` — **FAIL** 2026-09-24

**Process:** Follow **`docs/bug-fix-process.md`** — propose → approve → apply. Do not land from the gnome-shell-rpc tree.

---

## Problem

`RPC-Live-Subscribe.rpc_signal` for a name starting with `notify::` reads the property into a `string` `GValue` and writes `Notification.message`.

Named signals already pack their parameters on `Notification.args` (`Live.Subscription.emit`, fixed 2026-09-19). The `notify::` branch was left on `message`. That was not a separate decision to keep. A boolean and a `ClutterActorBox` are not strings.

**Expected:** `notify::visible` after the property becomes `true` arrives with `args[0]` holding boolean `true` and `message` empty. The client applies `args[0]` with `set_property`.

**Actual:** `message=TRUE`, `args` empty. The server logs `can't retrieve property 'allocation' of type 'ClutterActorBox' as value of type 'gchararray'`. The client logs `unable to set property 'visible' of type 'gboolean' from value of type 'gchararray'`.

---

## Evidence

```bash
meson compile -C build tests/call-sync-repro/subscribe-notify-args-gate
timeout 5 ./build/tests/call-sync-repro/subscribe-notify-args-gate
```

```text
client: notification method=notify::visible id=3 args=0 bool=(not bool) message=TRUE
subscribe-notify-args-gate method=notify::visible args=0 visible=false message=TRUE
FAIL subscribe-notify-args-gate: notify::visible did not arrive as a boolean on Notification.args with an empty message.
```

`libocrpc/Live/Subscribe.vala` — the `notify::` branch:

```vala
var current = GLib.Value(typeof(string));
obj.get_property(pspec.name, ref current);
var text = current.get_string();
text = text != null ? text : "";
request.connection.write(new Notification() {
    method = name,
    id = id,
    message = text
});
```

`libocrpc/Client.vala` applies that string:

```vala
var current = GLib.Value(typeof(string));
current.set_string(notif.message);
this.proxies.get(notif.id).set_property(
    notif.method.substring(8),
    current
);
```

---

## Fix

Read the property into a `GValue` of `pspec.value_type`. Put that value on `Notification.args`. Leave `message` empty.

On the client, when `notify::` has `args`, `set_property` from `args[0]`. Do not build a string `GValue` for that write.

`subscribe-notify-args-gate` passes when `args[0]` is boolean `true` and `message` is empty.

---

## Attempts / changelog

- ✔️ `libocrpc/Live/Subscribe.vala` — `notify::` reads `pspec.value_type` and writes that `GValue` on `Notification.args`. `message` stays empty.
- ✔️ `libocrpc/Client.vala` — `set_property` from `args[0]` only when that list is non-empty.
- ✔️ `tests/rpc/subscribe-test.vala` — `notify::title` is a string on `args`; `notify::visible` is boolean `true` with an empty `message`.
- ✔️ `tests/rpc/proxies-test.vala` — proxy apply uses `args`, not `message`.

```text
./build/tests/test-rpc-subscribe
./build/tests/test-rpc-proxies
```

Both exited 0 on 2026-09-24.

## Next

- ✔️ Archived. `notify::` type overrides are in `docs/bugs/done/2026-09-24-FIXED-notify-skips-type-override.md`.
