# `call_poll` never sees `IN`: `PollFD` revents written to array copy

**Status:** ✅ fixed — consumer verified on gnome-shell-rpc  
**Hit:** 2026-09-10 — gnome-shell-rpc hangs on first `call_poll` (`RPC-Bootstrap.get_display`) after hello  
**Component:** `libocrpc` / `Client.call_poll` — **library bug, not consumer**  
**Consumer:** gnome-shell-rpc `Runtime.do_call` → `Client.call_poll` (drop-in for `call_sync`)

---

## Ownership

**libocrpc.** The bad `GLib.poll` / `revents` use is entirely inside `Client.call_poll`.
gnome-shell-rpc only calls the API.

---

## Symptom

1. Hello (async `on_read` path) works after the buffer-condition fix.
2. First `call_poll` (`RPC-Bootstrap.get_display` id=2):
   - client sends request
   - server `recv id=2` and returns to the main loop (reply sent)
   - client never logs `replied id=2`; stays inside `call_poll` forever

---

## Root cause

In `call_poll`:

```vala
var poll_source = GLib.PollFD();
poll_source.fd = poll_fd;
poll_source.events = GLib.IOCondition.IN | …;
var poll_fds = new GLib.PollFD[] { poll_source };  // copy
GLib.poll(poll_fds, timeout_ms);
if ((poll_source.revents & GLib.IOCondition.IN) == 0) {  // always 0
    continue;
}
```

`GLib.poll` updates **`poll_fds[0].revents`**, not `poll_source.revents`.
So after a successful poll, the code thinks there was no `IN`, `continue`s, and
busy-loops without calling `poll_drain_readable`.

---

## Repro

```bash
valac --pkg gio-2.0 --pkg posix -o /tmp/pollfd-revents \
  docs/bugs/done/2026-09-10-FIXED-call-poll-pollfd-revents-copy.vala
/tmp/pollfd-revents
# expect exit 0 and PASS
```

---

## Fix (library)

Use the array element’s `revents` (or poll a single in-place `PollFD`):

```vala
var poll_fds = new GLib.PollFD[] { poll_source };
if (GLib.poll(poll_fds, timeout_ms) <= 0) {
    continue;
}
if ((poll_fds[0].revents & GLib.IOCondition.ERR) != 0
        || (poll_fds[0].revents & GLib.IOCondition.HUP) != 0) {
    …
}
if ((poll_fds[0].revents & GLib.IOCondition.IN) == 0) {
    continue;
}
this.poll_drain_readable(this.read_channel);
```

---

## Attempts / changelog

- ✔️ `libocrpc/Client.vala` — read `poll_fds[0].revents` after `GLib.poll`
  (not `poll_source.revents` from the pre-copy struct).
- ✔️ Repro exits 0 (`src_IN=false arr_IN=true`).
- ✔️ `ninja -C build` + `tests/test-rpc.sh` — pass.

## Verify

1. Repro exits 0.
2. After fix: nested `mutter-rpc --wayland --nested` gets past
   `RPC-Bootstrap.get_display` (`replied id=2`) without spinning.

## Conclusion

✅ `call_poll` reads `poll_fds[0].revents` after `GLib.poll`; first blocking
call after hello verified on gnome-shell-rpc.
