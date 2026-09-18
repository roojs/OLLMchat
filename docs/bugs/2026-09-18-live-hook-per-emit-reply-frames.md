# `Live.Hook` reply state is per row, so nested emits alias each other

**Status:** 🔷 proposed — the edit below is running green in a consumer tree

**Process:** `docs/bug-fix-process.md`

**Package / area:** `libocrpc` — `Live/Hook.vala` (`emit`), `Live/Callback.vala` (`reply`)

**Related:**

- ℹ️ Defect **B** of the archived `docs/bugs/done/2026-09-18-FIXED-buffered-reply-strand-and-reentrant-emit.md`, which closed it with `emit` → `virtual` and offered this central fix as the alternative. This is that alternative, written out.
- ℹ️ Gate (two real processes, no Clutter/GJS): `gnome-shell-rpc/tests/call-sync-repro/same-hook-reentrant-emit-gate.vala`

---

## Problem

🔷 **A re-entrant emit on one hook returns the wrong value.** Expected: each `emit` gets its own reply. Actual: the inner reply releases the outer emit too, the outer returns the inner's value, and the outer's real reply is then rejected `INVALID_PARAMS`.

Reproduce: `meson compile -C build same-hook-reentrant-emit-gate && timeout 20 ./build/tests/call-sync-repro/same-hook-reentrant-emit-gate` → `FAIL … outer emit got 22, want 11 (got the INNER emit's value)`.

ℹ️ Reached whenever a client's `Invoke` handler causes another emit on the same callback id before replying — relaying a re-entrant C API (Clutter measure/allocate) over RPC. One consumer session logged 86 re-entrant invokes on a single id, nesting to depth 4.

---

## Evidence

- ✔️ Gate FAIL is exact: outer emit returns `22` (the inner's value); the outer reply is rejected.
- ✔️ Volume: a storm gate driving the same shape counted **1200 rejected replies per 400 rounds** (depth 4, 1600 invokes).
- ✔️ **The edit below fixes it.** Held as a consumer override (`gnome-shell-rpc/src/rpc/Hook.vala`, on the now-`virtual` `emit`): gate **FAIL → PASS** (`outer=11 inner=0`), storm rejected replies **1200 → 0**, all 19 transport gates PASS, no call-site changes anywhere.
- ℹ️ Both emits do complete, so this is a wrong-value defect, not a hang — it is not the deadlock that was fixed in `Client.vala`.

---

## Root cause

- ✔️ Reply state (`replied`, `reply_id`, `reply_args`) lives on the hook **row**, but emits are per **call** and nest. The inner emit overwrites all three, so the first reply to arrive releases every waiting frame, and `Callback.reply` can only ever match the row's latest `reply_id`.

---

## Proposed fix

🔷 Give each emit its own frame and match replies to the frame that is waiting. `reply_args` is still filled before `emit` returns and the list object is kept (filled in place, not replaced), so every existing caller is unchanged. `replied` keeps its meaning as the row-wide abandon flag — `drop` and `unregister` still release every nested waiter at once.

💩 This supersedes the `virtual` on `emit` (§3 of the archived report) as far as consumers are concerned; keeping or reverting the keyword is your call, the consumer override is deleted either way.

### 1. `libocrpc/Live/Hook.vala` — per-emit frames

**Why:** nested emits share one row, so reply state has to be keyed by `reply_id`, not stored on the row.

**Where:** `Hook` class body — after the `reply_args` property, and the whole `emit` method.

**Depends on:** none.

#### Add

After the `reply_args` property, before the `emit` doc comment:

```vala
		/** One in-flight emit: emits nest, so reply state cannot live on the row. */
		private class Frame : GLib.Object
		{
			public bool replied { get; set; default = false; }
			public Gee.ArrayList<GLib.Value?> args {
				get; set; default = new Gee.ArrayList<GLib.Value?>();
			}
		}

		private Gee.HashMap<int, Frame> frames = new Gee.HashMap<int, Frame>();
```

#### Remove

```vala
		public virtual void emit(Gee.ArrayList<GLib.Value?> args)
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

#### Replace with

```vala
		public virtual void emit(Gee.ArrayList<GLib.Value?> args)
		{
			var correlation = this.connection.next_handle;
			this.connection.next_handle++;
			var frame = new Frame();
			this.frames.set(correlation, frame);

			this.replied = false;
			this.reply_id = correlation;
			this.connection.write(new Invoke() {
				id = this.id,
				reply_id = correlation,
				args = args
			});
			while (!frame.replied && !this.replied) {
				this.connection.emit_wait_poll();
			}
			this.frames.unset(correlation);
			this.reply_args.clear();
			foreach (var arg in frame.args) {
				this.reply_args.add(arg);
			}
		}

		/**
		 * Complete the emit waiting on {@code correlation}.
		 *
		 * @param correlation {@link Invoke.reply_id} the client replied to
		 * @param args values after the {@code reply_id} argument
		 * @return {@code false} when no emit on this row is waiting for it
		 */
		public bool complete(int correlation, Gee.ArrayList<GLib.Value?> args)
		{
			if (!this.frames.has_key(correlation)) {
				return false;
			}
			var frame = this.frames.get(correlation);
			frame.args.clear();
			foreach (var arg in args) {
				frame.args.add(arg);
			}
			frame.replied = true;
			return true;
		}
```

### 2. `libocrpc/Live/Callback.vala` — `reply()`: route to the waiting emit

**Why:** the scan matches `row.reply_id`, which is the row's latest emit, so a reply to an outer emit lands on the inner one. `complete` answers "is this row waiting for that id" instead.

**Where:** `reply`, the `correlation` scan after the empty-args guard.

**Depends on:** §1.

#### Remove

```vala
			var correlation = (int) request.args.get(0).get_uint64();
			foreach (var id in request.connection.callbacks.keys) {
				var row = request.connection.callbacks.get(id);
				if (row.reply_id != correlation) {
					continue;
				}
				row.reply_args.clear();
				for (var i = 1; i < request.args.size; i++) {
					row.reply_args.add(request.args.get(i));
				}
				row.replied = true;
				request.reply(new Response());
				return;
			}
```

#### Replace with

```vala
			var correlation = (int) request.args.get(0).get_uint64();
			var values = new Gee.ArrayList<GLib.Value?>();
			for (var i = 1; i < request.args.size; i++) {
				values.add(request.args.get(i));
			}
			foreach (var id in request.connection.callbacks.keys) {
				var row = request.connection.callbacks.get(id);
				if (!row.complete(correlation, values)) {
					continue;
				}
				request.reply(new Response());
				return;
			}
```

---

## Attempts / changelog

- ✔️ Held downstream first as an override on the `virtual` `emit`, which is how the edit above was proven; proposing it centrally because nothing in it is consumer-specific and any consumer that relays a re-entrant callback hits the same defect.
- 🚫 Matching replies on the row's latest `reply_id` (current code) — cannot work while emits nest; the ids are allocated per emit but only one is remembered.
- ℹ️ `complete` is public so consumers replacing `Live.Callback` (e.g. to add error replies) route through the same path rather than re-implementing frame matching.

---

## Next

- 🔷 Apply §1–§2, then `same-hook-reentrant-emit-gate` must PASS and the storm gate must report `0 rejected replies`.
- ℹ️ On apply, the consumer drops `gnome-shell-rpc/src/rpc/Hook.vala` and calls `complete` from its own `Live.Callback` replacement.
