# FIXED: GiMock mints untyped `GObject` for object returns (blocks mock RPC servers)

**Status:** ✅ FIXED — `mint_object_lease` in `libocrpc/GiMock.vala` (commit `4844cc3e`)

**Started:** 2026-09-03

**Process:** `docs/bug-fix-process.md`

**Package / area:** `libocrpc` — `GiMock.vala` (`mock_new`, `mock_empty_interface`)

**Related:**

- ℹ️ [`docs/plans/done/RPC-1.7-DONE-mock-dispatch-and-gi-mock.md`](../plans/done/RPC-1.7-DONE-mock-dispatch-and-gi-mock.md)
- ℹ️ Consumer: gnome-shell-rpc [`0.7.8-gi-rpc-noop-server`](../../../../git/gnome-shell-rpc/docs/plans/0.7.8-gi-rpc-noop-server.md)

---

## Problem

🔷 `GiMock` minted plain `new GLib.Object()` for OBJECT / INTERFACE returns. `GObject` is not in `Bin.gtype_to_alias` → **Unregistered class type schema: GObject** on mock servers (`gi-rpc-mock`).

---

## Fix (landed)

🔷 `mint_object_lease(GI.TypeInfo)` in `GiMock.vala`:

1. Resolve return GType from GIR (`RegisteredTypeInfo.get_g_type()`).
2. Guard: GType must already be in `Bin.gtype_to_alias` (from `Gi.register`).
3. Mint a per-alias fake GType (`g_type_register_static_simple` under `OLLMrpcGiMock_*`) and `Bin.register_alias(alias, fake_gtype)`.
4. `Object.new(fake_gtype)` → `export` → wire encodes as the correct alias (e.g. `Meta-Context`).

Used from `mock_new` and `mock_empty_interface` (replaces plain `GLib.Object`).

**Commit:** `4844cc3e` — *fix object return type in mock rpc*

---

## Consumer verification

ℹ️ gnome-shell-rpc must link/run against rebuilt `OLLMchat/build/libocrpc/libocrpc.so` (`-Docrpc_libdir=…`, `LD_LIBRARY_PATH`).

| Check | After fix |
| --- | --- |
| `RPC-Daemon.hello` | ✔️ |
| `RPC-Bootstrap.get_display` | ✔️ |
| `Meta-Display.get_context` wire encode | ✔️ (no GObject schema error) |
| Full `register-class-trace-smoke.js` | ⏳ still fails later (`global.context is null` — separate consumer/bootstrap issue) |

---

## Attempts / changelog

- ✔️ 2026-09-03 — Filed from gnome-shell-rpc `gi-rpc-mock` bring-up.
- ✔️ 2026-09-03 — Fixed in libocrpc (`4844cc3e`).
