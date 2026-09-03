# FIXED: GiMock fake GType registration fails on GLib 2.84 (`register_static_simple` size 0)

**Status:** ✔️ FIXED — superseded parent choice in [`2026-09-03-FIXED-gimock-fake-gtype-gobject-parent-mint-segfault.md`](2026-09-03-FIXED-gimock-fake-gtype-gobject-parent-mint-segfault.md); see `GiMock.mint`

**Started:** 2026-09-03

**Process:** `docs/bug-fix-process.md`

**Package / area:** `libocrpc` — `GiMock.vala` (`fake_gtype_for_alias`, `mint_object_lease`)

**Related:**

- ℹ️ Fixed sibling (wire encode): [`2026-09-03-FIXED-gimock-untyped-object-returns.md`](2026-09-03-FIXED-gimock-untyped-object-returns.md) (`4844cc3e`)
- ℹ️ Consumer: gnome-shell-rpc [`0.7.8-gi-rpc-noop-server`](../../../../git/gnome-shell-rpc/docs/plans/0.7.8-gi-rpc-noop-server.md)
- ℹ️ Consumer workaround to drop: `gnome-shell-rpc/src/gi-rpc-mock/MockLease.vala` → call `OLLMrpc.GiMock.fake_gtype_for_alias`

---

## Problem

🔷 `GiMock.mint_object_lease()` registered per-alias fake GTypes via `g_type_register_static_simple()` with **`class_size = 0`** and **`instance_size = 0`**, expecting GLib to inherit sizes from the parent.

On **GLib 2.84** (Ubuntu 25.04 / GNOME 48 stack), that call **failed**:

```
GLib-GObject-CRITICAL: specified class size for type 'OLLMrpcGiMock_Meta_Compositor'
  is smaller than 'GTypeClass' size
```

Registration returned `G_TYPE_INVALID`; mock servers could not mint leases for abstract Meta types (`Meta-Compositor`, `Meta-Context`, `Meta-Backend`, …).

---

## Fix (landed)

🔷 New public `GiMock.fake_gtype_for_alias(string alias)`; `mint_object_lease` delegates to it.

1. Parent = `Bin.alias_to_gtype.get(alias)` (registered GType from `Gi.register`) — not `typeof(GLib.Object)`.
2. `parent.query()` → pass `class_size` / `instance_size` to `g_type_register_static_simple`.
3. Cache in `mock_gtypes`; `Bin.register_alias` maps fake GType to wire alias.
4. `mint_object_lease` → `Object.new(fake_gtype_for_alias(alias))`.

**Optional follow-ups (not this bug):**

- ⏳ gnome-shell-rpc: drop duplicate `MockLease.fake_gtype_for_alias`, call libocrpc API.
- ⏳ Mint on **pointer** object returns (`MetaContext*`, …) instead of `is_pointer()` early return — `HelperMock` handles boot getters today.

---

## Verification

| Check | After fix |
| --- | --- |
| `libocrpc.so` build | ✔️ |
| `fake_gtype_for_alias("Meta-Compositor")` after `Gi.register` | ✔️ (valid GType, parent = MetaCompositor) |
| `gi-rpc-mock` boot | ⏳ consumer rebuild + drop `MockLease` duplicate |
| `Meta-Display.get_context` via GiMock (pointer return) | ⏳ optional follow-up |

Rebuild consumer against fixed `libocrpc.so` (`-Docrpc_libdir=…`, `LD_LIBRARY_PATH`).

---

## Attempts / changelog

- ✔️ 2026-09-03 — Filed from gnome-shell-rpc `gi-rpc-mock` bring-up; root cause confirmed with standalone C repro on GLib 2.84.
- ✔️ 2026-09-03 — **Workaround** in gnome-shell-rpc `MockLease.fake_gtype_for_alias()` (queried parent sizes). Superseded by libocrpc fix.
- ✔️ 2026-09-03 — Fixed in libocrpc: `fake_gtype_for_alias`, parent from alias GType + queried sizes.
