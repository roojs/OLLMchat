# `notify::` skips `TypeOverride` and resets the connection

**Status:** ✔️ fixed — `test-rpc-subscribe` and `test-rpc-proxies` exit 0. `notify::stamp` packs as the override string and the proxy unpacks it.

**Started:** 2026-09-24

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ `docs/bugs/done/2026-09-24-FIXED-bin-type-override.md` — named signals pack through `TypeOverride.pack_params`
- ℹ️ `docs/bugs/done/2026-09-24-FIXED-notify-property-string-message.md` — `notify::` already puts the property on `args`
- ℹ️ gnome-shell-rpc boot 19:24:09 — `unsupported bin value type 'ClutterActorBox'` on `notify::allocation`, then `Connection reset by peer`
- ℹ️ Consumer gate: `gnome-shell-rpc/tests/call-sync-repro/subscribe-notify-args-gate`

---

## Problem

🔷 `Subscription.emit` looks up `OLLMrpc.Bin.TypeOverride` and writes the packed fields.

🔷 `Live.Subscribe` for a name starting with `notify::` puts the raw property `GValue` on `Notification.args`.

🔷 A registered override is ignored. `StreamValue.write` throws `unsupported bin value type` and the connection drops.

🔷 The client apply path is `set_property` of `args[0]`. A multi-field pack only round-trips if that path calls `TypeOverride.unpack` first.

🚫 A `ClutterActorBox` or `GDateTime` encoder in this library. The override subclass lives with the consumer and calls `TypeOverride.register`.

---

## Evidence

```bash
meson compile -C build tests/call-sync-repro/subscribe-notify-args-gate
timeout 8 ./build/tests/call-sync-repro/subscribe-notify-args-gate
```

The gate registers a `TypeOverride` for `GDateTime` that packs an ISO-8601 string. `notify::visible` passes. `notify::stamp` then dies:

```text
client: notification method=notify::visible id=3 args=1 bool=true message=
subscribe-notify-args-gate method=notify::visible args=1 visible=true message=
connection write error: unsupported bin value type 'GDateTime'
Client.vala:701: Unexpected early end-of-stream
```

Exit 133. The process aborts inside `Client.vala` on the reset, so the gate's own FAIL line does not print.

Same failure on the nested boot, type `ClutterActorBox`, during the first layout.

`libocrpc/Live/Subscribe.vala` before the fix:

```vala
var current = GLib.Value(pspec.value_type);
obj.get_property(pspec.name, ref current);
var packed = new Gee.ArrayList<GLib.Value?>();
packed.add(current);
```

---

## Fix

Pack the property with `TypeOverride.lookup(pspec.value_type)`. When an override exists, `args` is `pack(current)`. When it does not, `args` is the single property value, as for a boolean.

On the client, when `notify::` has an override for the property type, `unpack` the fields and `set_property` that value. Otherwise `set_property` `args[0]`.

---

## Attempts / changelog

- ✔️ `libocrpc/Live/Subscribe.vala` — `notify::` looks up `TypeOverride` for `pspec.value_type`. Override present: `args` is `pack`. Absent: `args` is the property value.
- ✔️ `libocrpc/Client.vala` — `notify::` unpacks when the proxy property type has an override, then `set_property`. Otherwise `set_property` from `args[0]`.
- ✔️ `tests/rpc/subscribe-test.vala` — `GDateTime` override. `notify::stamp` is the ISO-8601 string. `notify::visible` stays a boolean.
- ✔️ `tests/rpc/proxies-test.vala` — packed stamp string is unpacked onto the proxy `DateTime`.

```text
./build/tests/test-rpc-subscribe
./build/tests/test-rpc-proxies
```

Both exited 0 on 2026-09-24.

## Next

- ⏳ Re-run `gnome-shell-rpc` `subscribe-notify-args-gate` against this library.
