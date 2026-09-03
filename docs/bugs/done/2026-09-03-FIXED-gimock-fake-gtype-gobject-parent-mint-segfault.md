# FIXED: GiMock fake GType parents on real Meta type — Object.new segfaults in mock servers

**Status:** ✔️ FIXED — `GiMock.mint` in `libocrpc/GiMock.vala`

**Started:** 2026-09-03

**Process:** `docs/bug-fix-process.md`

**Package / area:** `libocrpc` — `GiMock.vala` (`mint`, `mint_object_lease`)

**Related:**

- ℹ️ Prior fix (GLib 2.84 sizes, superseded parent choice): [`2026-09-03-FIXED-gimock-fake-gtype-register-static-simple-glib-284.md`](2026-09-03-FIXED-gimock-fake-gtype-register-static-simple-glib-284.md)
- ℹ️ Consumer: gnome-shell-rpc [`0.7.8-gi-rpc-noop-server`](../../../../git/gnome-shell-rpc/docs/plans/0.7.8-gi-rpc-noop-server.md)
- ℹ️ Consumer workaround to drop: `gnome-shell-rpc/src/gi-rpc-mock/boot-register.c` + `HelperMock.fake_gtype()`

---

## Problem

🔷 Mock servers must mint **fake** leases for every wire alias — never instantiate real Meta/Clutter/St GTypes (no live compositor).

🔷 `GiMock.fake_gtype_for_alias()` registered a fake GType **parented on the alias GType** from `Bin.alias_to_gtype` (e.g. `MetaCompositor`). `Object.new()` on that fake type still ran the stock **C instance init chain** → segfault in mutter.

---

## Fix (landed)

🔷 Replaced public `fake_gtype_for_alias` with **`GiMock.mint(string alias)`** — one entry point for mock servers and `mint_object_lease`:

1. Validate alias exists in `Bin.alias_to_gtype`.
2. Parent = **`GLib.Type.OBJECT`**; query `class_size` / `instance_size` (GLib 2.84+).
3. Register/cache fake GType under `OLLMrpcGiMock_*`; `Bin.register_alias(alias, fake_gtype)`.
4. Return `Object.new(fake_gtype)` — no stock Meta/Clutter C init; wire encodes as `alias`.

`register_static_simple_type` stays private in libocrpc (Vala `extern` conflicts if consumers redeclare it).

**Consumer follow-up:**

- ⏳ gnome-shell-rpc: `HelperMock.mint` → `OLLMrpc.GiMock.mint(wire_alias)`; delete `boot-register.c` + local cache.

---

## Verification

| Check | After fix |
| --- | --- |
| `libocrpc.so` build | ✔️ |
| `GiMock.mint("Meta-Compositor")` after `Gi.register` | ⏳ consumer rebuild |
| `gi-rpc-mock` boot through `Meta-Backend.get_stage` | ⏳ consumer follow-up |
| `mint_object_lease` (non-pointer object returns) | ✔️ (calls `GiMock.mint`) |

---

## Attempts / changelog

- ✔️ 2026-09-03 — Reproduced from gnome-shell-rpc; gdb backtrace through `meta_backend_get_clutter_backend`.
- ✔️ 2026-09-03 — Consumer workaround: `boot-register.c` (GObject parent) + local cache in `HelperMock.fake_gtype()`.
- ✔️ 2026-09-03 — Fixed in libocrpc: public `GiMock.mint`, GObject parent, removed `fake_gtype_for_alias` export.
