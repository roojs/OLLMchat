# `poll_drain_readable` skips socket reads: `get_buffer_condition` on unbuffered `IOChannel`

**Status:** ✅ fixed — consumer verified on gnome-shell-rpc  
**Hit:** 2026-09-10 — consumer stuck at `RPC-Daemon.hello` (server recv, client never `replied id=1`)  
**Component:** `libocrpc` / `Client.poll_drain_readable` + `on_read` / `call_poll`  
**Consumer:** gnome-shell-rpc (`Runtime` → `Client.call_poll` / connect read watch)  
**Related:** `call_poll` (née `sync_call_poll`) in `f7578fab` / rename `7c348c08`

---

## Symptom (live)

```text
Client: id=1 method=RPC-Daemon.hello
Listen: client connected
Connection: recv id=1 method=RPC-Daemon.hello
… no client "replied id=1" …
client sits forever with pending=1
```

Server finished dispatch (main thread back in `g_main_loop_run` / `ppoll`).
Reply bytes are almost certainly sitting in the kernel socket buffer; the
client read watch fires but **does not call `bin.parse()`**.

---

## Root cause

`Client.poll_drain_readable` (used by both `on_read` and `call_poll`) does:

```vala
if ((source.get_buffer_condition() & GLib.IOCondition.IN) == 0) {
    return true;   // ← returns WITHOUT reading
}
var msg = this.bin.parse();
```

`read_channel` is created **unbuffered**:

```vala
this.read_channel.set_buffered(false);
```

For an unbuffered `GLib.IOChannel`, `get_buffer_condition()` reports only
GLib’s **internal** buffer, **not** socket/`poll(2)` readability. After a
peer writes, `select`/`GLib.IOCondition` on the fd is `IN`, but
`get_buffer_condition()` stays `0` until something actually reads into the
channel.

So when `on_read` is invoked with `condition & IN`:

1. Watch correctly observed socket readability.
2. `poll_drain_readable` sees empty buffer condition → **returns immediately**.
3. Reply never parsed → `complete_pending` never runs → connect/`call_poll` hang.

Pre-`call_poll` `on_read` always called `bin.parse()` at least once per
watch callback, then looped while `get_buffer_condition & IN`. The new helper
inverted that: it checks buffer condition **before** any parse.

---

## Repro (Vala, no libocrpc)

```bash
# from OLLMchat repo root — extract the sample below to /tmp or copy from this doc
valac --pkg gio-2.0 --pkg posix -o /tmp/iochannel-bufcond \
  docs/bugs/done/2026-09-10-FIXED-iochannel-buffer-condition-skips-read.vala
/tmp/iochannel-bufcond
# expect: PASS and exit 0
```

Sample source (same path as this bug, `.vala` sibling):
`docs/bugs/done/2026-09-10-FIXED-iochannel-buffer-condition-skips-read.vala`

Observed:

```text
A: poll_IN=true get_buffer_condition=0
A: would return without parse/read (bytes left in kernel)
B: watch_cond=1 buf_cond=0 watch_IN=true buf_IN=false
PASS: reproduces bug precondition
```

Part B is exactly `on_read`: GLib delivered `IN` to the callback, but
`channel.get_buffer_condition()` has no `IN`.

---

## Consumer live sequence (proof of impact)

With `libocrpc` containing `poll_drain_readable` early-return:

1. `gnome-shell-rpc` connect → send `RPC-Daemon.hello`
2. `mutter-rpc` logs `recv id=1 method=RPC-Daemon.hello`
3. Client debug log stops at `id=1 method=RPC-Daemon.hello` (send); never
   `replied id=1`
4. Process remains up; `pending=1`

---

## Proposed fix

Restore “parse at least once” semantics (match old `on_read`):

```vala
private bool poll_drain_readable(GLib.IOChannel source)
{
    if (!this.connected || this.bin == null) {
        return true;
    }
    /* Do NOT gate the first parse on get_buffer_condition — unbuffered
     * channels do not surface socket POLLIN there. Caller already saw IN
     * via io watch or GLib.poll. */
    try {
        var msg = this.bin.parse();
        this.dispatch_message(msg);
    } catch (GLib.IOError e) {
        GLib.error("%s", e.message);
    } catch (GLib.Error e) {
        GLib.error("%s", e.message);
    }
    if ((source.get_buffer_condition() & GLib.IOCondition.IN) != 0) {
        return this.poll_drain_readable(source);
    }
    return true;
}
```

Also review the pre-poll opportunistic check in `call_poll`:

```vala
if (this.read_channel != null
    && (this.read_channel.get_buffer_condition() & GLib.IOCondition.IN) != 0) {
    this.poll_drain_readable(this.read_channel);
}
```

That line is harmless as an optimization (may no-op), but after `GLib.poll`
reports `IN`, the subsequent `poll_drain_readable` must not early-return.

---

## Attempts / changelog

- ✔️ `libocrpc/Client.vala` — removed `get_buffer_condition()` early-return in
  `poll_drain_readable`; parse at least once per caller invocation (matches
  pre-`call_poll` `on_read` semantics).
- ✔️ `ninja -C build` — clean.
- ✔️ `tests/test-rpc.sh` — pass.

## Verify

1. Vala repro exits 0 (documents GLib behavior; should keep passing).
2. After fix: `dbus-run-session ./build/src/mutter-rpc --debug --wayland --nested`
   must log client `replied id=1` / `connect ok hello` within milliseconds.
3. Nested `call_poll` during `Live.Invoke` must still read replies (no 120s
   timeout on `remove_child`).

## Conclusion

✅ `poll_drain_readable` parses before checking `get_buffer_condition`; hello and
nested `call_poll` verified on gnome-shell-rpc.
