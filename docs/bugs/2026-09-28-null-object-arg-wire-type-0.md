# Null GObject in `Notification.args` aborts the client

**Status:** ✔️ applied in `StreamValue.write`. Gate passes. ⏳ calendar close on the shell not re-checked.

## Problem

- **🔷** Closing the calendar (date/time menu) kills `gnome-shell-rpc`. Kernel: `trap int3` in `libglib`, twice, 2026-09-28 08:16:20 and 08:16:50. `mutter-rpc` hits `int3` in the same second.
- **🔷** Last client line both times: `Client.vala:704: unsupported wire type 0x00`. That is `GLib.error` on `Bin.Stream.parse`.
- **ℹ️** The call before the death is `Clutter-Stage.set_key_focus`. Menu close clears key focus. `notify::key-focus` with a real actor (08:16:49.299, menu open) is delivered. The clear is not.

## Root cause

- **✔️** `notify::key-focus` carries one `Clutter.Actor`. Cleared focus is a null object.
- **✔️** `Notification.bin_write_prop` writes `args` as a counted list and calls `Bin.StreamValue.write` for each element.
- **✔️** `StreamValue.write` returns without a type byte when `val.get_object() == null`. The count stays 1.
- **✔️** The reader takes the next property tag as that element’s type byte. Tags are big-endian `uint16`. A registered token below 256 starts with `0x00`. `StreamValue.read` throws `unsupported wire type 0x00`.
- **ℹ️** Skipping a null object is correct for a named property (`Serializable.bin_default_write_prop` skips the tag). It is not correct inside a counted `args` array.

## Prove

From `gnome-shell-rpc`, against this tree’s `build/libocrpc`:

```text
meson compile -C build tests/call-sync-repro/null-object-arg-gate
timeout 5 ./build/tests/call-sync-repro/null-object-arg-gate
```

Run 2026-09-28:

```text
FAIL null-object-arg-gate: null object: unsupported wire type 0x00
EXIT:1
```

The bool notification and an explicit uint64 `0` both parse. The raw null `GLib.Object` is the line above.

Pass: that raw null also comes back as uint64 `0`.

## Proposed fix

- **🔷** A null object in a counted `args` list is uint64 lease `0`. `GnomeShellRpc.call_value` rewrites the request `Value` to that before `StreamValue.write`. `Gi.convert_interface` reads lease `0` as null. An explicit `0` in `Notification.args` parses.
- **🔷** `notify::` (`Live.Subscribe`) and `Subscription.emit` put the raw null `GObject` into that counted list. `Notification.bin_write_prop` then calls `StreamValue.write`, which returns with no type byte. The same hole is on `Request`, `Response`, and `Invoke` `args` (and `Response.retval`): each calls `StreamValue.write` and expects one type byte per element.
- **🔷** Encode the null inside `StreamValue.write` as the compact uint64 `0` those callers already accept (`GLib.Type.UINT64`, length `1`, value `0`). `call_value` keeps writing the same bytes. `bin_default_write_prop` still omits a null named property and never reaches `write`.
- **🚫** A second null-object encoding. Omitting the property tag stays only in `bin_default_write_prop`.

### `libocrpc/Bin/StreamValue.vala` — null object in a value slot

#### Remove

```vala
			if (val.type().is_a(GLib.Type.OBJECT)) {
				if (val.get_object() == null) {
					return;
				}
```

#### Replace with

```vala
			if (val.type().is_a(GLib.Type.OBJECT)) {
				if (val.get_object() == null) {
					ctx.out_stream.put_byte((uint8) GLib.Type.UINT64);
					ctx.out_stream.put_byte(1);
					ctx.out_stream.put_byte(0);
					return;
				}
```

## Attempts / changelog

- **✔️** 2026-09-28 — `libocrpc/Bin/StreamValue.vala`: a null object in a value slot writes compact uint64 `0`. `ninja -C build libocrpc/libocrpc.so`.
- **✔️** Gate from `gnome-shell-rpc` against `build/libocrpc`: `PASS null-object-arg-gate`, exit 0.
