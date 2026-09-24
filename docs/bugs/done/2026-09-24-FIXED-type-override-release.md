# TypeOverride needs a release after the handler

**Status:** ✅ FIXED — user archived. `release` and `release_params` are on `TypeOverride`.

**Started:** 2026-09-24

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ gnome-shell-rpc `docs/bugs/2026-09-24-captured-event-freed-pointer.md` — `unpack` keeps a `Clutter.Event` alive until the signal handler returns, then drops it

---

## Problem

🔷 `TypeOverride.unpack` can build a value the handler must read.

🔷 `fill_params` returns before that handler runs. Nothing tells the override the handler has finished.

🔷 gnome-shell-rpc `Signals.emit` will call `release_params` after `emitv`. This library does not know `Clutter.Event`.

🚫 A `Clutter.Event` stack in this library.

🚫 `Signals.vala` checking `typeof(Clutter.Event)`.

---

## ✔️ `libocrpc/Bin/TypeOverride.vala`

#### Add

```vala
/**
 * Drop one value this override kept alive for {@link unpack}.
 *
 * Default does nothing.
 */
public virtual void release()
{
}

/**
 * Call {@link release} once per parameter that has an override.
 *
 * @param param_types signal parameter types, not including the instance
 */
public static void release_params(GLib.Type[] param_types)
{
	foreach (var type in param_types) {
		var helper = TypeOverride.lookup(type);
		if (helper == null) {
			continue;
		}
		helper.release();
	}
}
```

---

## Conclusions

🔷 `fill_params` returns the built value before the handler runs. `release` is the hook the caller uses after that handler returns.

ℹ️ gnome-shell-rpc `Signals.emit` calls `release_params` after `emitv`. This library still does not know `Clutter.Event`.

---

## Attempts / changelog

- ✔️ 2026-09-24 — Added `TypeOverride.release` and `TypeOverride.release_params`. `libocrpc.so` rebuilt.
- ✅ 2026-09-24 — User archived.
