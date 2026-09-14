# `Hook.emit` does not clear `reply_args` before wait

**Status:** ✔️ FIXED (await user ✅)  
**Hit:** 2026-09-14 — gnome-shell-rpc consumer always clears before emit  
**Component:** `libocrpc` / `Live.Hook.emit`  
**Consumer:** gnome-shell-rpc `Helper.LayoutHooks` / `Helper.Actor.fire_button_press`  
**Related:** `libocrpc/Live/Hook.vala`, `libocrpc/Live/Callback.reply` (already clears on fill)

---

## Problem

🔷 `Live.Hook.emit` resets wait state (`replied = false`, new `reply_id`) but
leaves **`reply_args` intact**. Consumers must clear before every emit or risk
reading stale outs from a prior reply.

🔷 Expected: starting an emit clears the previous reply payload (same contract
as resetting `replied`).

🔷 Actual: `emit` leaves old `reply_args`; only `Callback.reply` clears, and
only on a successful correlation match. Paths that set `replied` without going
through reply (e.g. `Hook.drop`) leave stale args visible after the wait.

---

## Evidence

- ✔️ `libocrpc/Live/Hook.vala` `emit`:

```vala
this.replied = false;
this.reply_id = this.connection.next_handle;
this.connection.next_handle++;
this.connection.write(new Invoke() { … });
while (!this.replied) {
    this.connection.emit_wait_poll();
}
```

No `reply_args.clear()`.

- ✔️ `Callback.reply` already does `row.reply_args.clear()` before fill — so
  the happy path eventually replaces args, but only after the new reply
  arrives.
- ✔️ `Hook.drop` sets `replied = true` and does **not** clear `reply_args`.
- ✔️ Consumer workaround (every emit site): e.g.
  `gnome-shell-rpc/src/rpc/helper/ClutterActor.vala` —
  `hook.reply_args.clear();` then `hook.emit(...)`.

---

## Root cause

✔️ Confirmed from source: emit owns wait-state reset but omits clearing the
reply buffer that callers read after return. That belongs in `emit`, not at
every trampoline.

---

## Proposed fix

🔷 In `libocrpc/Live/Hook.vala` `emit`, clear `reply_args` with the other
resets (before write / wait).

#### Replace with

```vala
public void emit(Gee.ArrayList<GLib.Value?> args)
{
	this.replied = false;
	this.reply_args.clear();
	this.reply_id = this.connection.next_handle;
	this.connection.next_handle++;
	this.connection.write(new Invoke() {
		id = this.id,
		reply_id = this.reply_id,
		args = args
	});
	while (!this.replied) {
		this.connection.emit_wait_poll();
	}
}
```

ℹ️ `Callback.reply` may keep its own clear-before-fill (harmless / still
correct if reply ever fills without a prior emit reset).

🚫 Do not leave the clear as a consumer convention once this lands —
gnome-shell-rpc can drop the per-site `reply_args.clear()` after upgrading
libocrpc.

---

## Attempts / changelog

- ✔️ Applied `this.reply_args.clear()` in `Hook.emit` after `replied = false`
  (user approved 2026-09-14).

---

## Next

- ⏳ 💩 Optional: extend `tests/rpc/callback-test.vala` — emit twice; force a
  `drop` (or empty ack) on the second wait and assert `reply_args` is empty
  / replaced, not the first reply’s values.
- ⏳ Consumer follow-up (gnome-shell-rpc): remove redundant
  `hook.reply_args.clear()` before emit once libocrpc is bumped.
- ⏳ Move this log to `docs/bugs/done/` after user ✅.
