# GiMock mints untyped `GObject` for object returns (blocks mock RPC servers)

**Status:** ⏳ OPEN

**Started:** 2026-09-03

**Process:** `docs/bug-fix-process.md`

**Package / area:** `libocrpc` — `GiMock.vala` (`dispatch_new`, `mock_empty_interface`)

**Related:**

- ℹ️ Shipped: [`docs/plans/done/RPC-1.7-DONE-mock-dispatch-and-gi-mock.md`](../plans/done/RPC-1.7-DONE-mock-dispatch-and-gi-mock.md) — optional follow-up noted at Phase B (plain `GLib.Object` mint)
- ℹ️ Consumer blocked: gnome-shell-rpc [`0.7.8-gi-rpc-noop-server`](../../../../git/gnome-shell-rpc/docs/plans/0.7.8-gi-rpc-noop-server.md) Phase C (`gi-rpc-mock` + import smokes)
- ℹ️ Correct reference path: real `Gi.dispatch_function` object return (~511–521 in `Gi.vala`)

---

## Problem

🔷 After `Gi.register` + `Request.register_mock`, **mock servers** (`gi-rpc-mock`) resolve GI methods from GIR the same way as real `Gi`, but **object/interface return values** are minted as plain `new GLib.Object()`. That GType is **not** in `Bin.gtype_to_alias`, so the server cannot encode the reply on the live-handle wire.

🔷 Expected: `GiMock` mints leases whose **GType matches the GIR return type** (already registered by `Gi.register`), then `export` + `val("o", token)` — same bin guard as real `Gi`.

🔷 Actual: `Stream.write_reg_gtype` throws **Unregistered class type schema: GObject** (or GObject criticals building invalid `GValue`s). Client stubs receive null/invalid proxies and abort during early bootstrap (`Meta-Display.get_context`, `get_compositor`, …).

---

## Evidence

ℹ️ **Consumer repro** (gnome-shell-rpc `gi-rpc-mock` + `gnome-shell-rpc`):

```bash
# terminal 1
LD_LIBRARY_PATH=/usr/lib/gnome-shell \
MUTTER_RPC_SOCKET=$XDG_RUNTIME_DIR/mutter-rpc.sock \
  ./build/src/gi-rpc-mock --debug

# terminal 2
MUTTER_RPC_SOCKET=$XDG_RUNTIME_DIR/mutter-rpc.sock \
GI_TYPELIB_PATH=./build/src:$(pkg-config --variable=typelibdir libmutter-16) \
LD_LIBRARY_PATH=./build/src:/usr/lib/gnome-shell \
  ./build/src/gnome-shell-rpc --debug src/gjs-embed/register-class-trace-smoke.js
```

| Stage | Result |
| --- | --- |
| `RPC-Daemon.hello` | ✔️ |
| `RPC-Bootstrap.get_display` (consumer Ffi; `Object.new(Gi.types["Meta-Display"])`) | ✔️ |
| `Meta-Display.get_context` / `get_compositor` (`GiMock`) | ❌ |

ℹ️ **Server log:**

```
connection write error: Unregistered class type schema: GObject
```

or when encoding proceeds partially:

```
type id '0' is invalid
cannot initialize GValue with type '(null)'
```

ℹ️ **Client log:**

```
g_value_get_object: assertion 'G_VALUE_HOLDS_OBJECT (value)' failed
meta_context_get_backend: assertion 'self != NULL' failed
```

ℹ️ **Failing code** (`libocrpc/GiMock.vala`):

```vala
// dispatch_new (~171–175)
var token = new GLib.Object();
this.request.connection.export(token);

// mock_empty_interface (~426–428)
var token = new GLib.Object();
this.request.connection.export(token);
val = OLLMrpc.val("o", token);
```

ℹ️ **Working reference** (`libocrpc/Gi.vala` ~511–521): C invoke returns real instance; wire encode requires `Bin.gtype_to_alias.has_key(created.get_type())`.

---

## Root cause

✔️ `GiMock` has the **return type from GIR** (`fn.get_return_type()` / `mock_empty_interface`'s `type`) but ignores it for object minting. Plain `GObject` was a Phase B placeholder (RPC-1.7 optional follow-up). With `live_handles=true`, bin serialization requires a **registered wire alias** for the object's GType — supplied by `Gi.register`, not by `GObject`.

🚫 Fix does **not** belong in consumer repos (no `Bin.register` mock types, no HelperMock faking GI returns).

---

## Proposed fix

🔷 In `GiMock`, for OBJECT / INTERFACE returns (and `dispatch_new`):

1. From GIR return `GI.TypeInfo`, get `gtype = ((GI.RegisteredTypeInfo) type.get_interface()).get_g_type()`.
2. If `gtype == GLib.Type.INVALID` → `reply_error` (same as real `Gi`).
3. If `!Bin.gtype_to_alias.has_key(gtype)` → `reply_error` (same guard as `Gi.vala` ~515).
4. Else `token = (GLib.Object) Object.new(gtype)`, `export`, `val("o", token)`.

ℹ️ Nullable returns (`type.is_pointer()` / GIR `nullable`): leave unset retval (mirror null OBJECT handling in real `Gi` after RPC-1.7 null fix).

ℹ️ Abstract / non-instantiable GTypes: `Object.new` may fail — handle error or document; consumer may need `register_alias` for concrete subclasses (out of scope here).

#### Suggested helper (DRY)

Extract e.g. `mint_object_lease(GI.TypeInfo type, out GLib.Object? token)` used from `dispatch_new` and `mock_empty_interface`.

#### Replace `mock_empty_interface` object branch (~421–429) with

```vala
				case GI.InfoType.OBJECT:
				case GI.InfoType.INTERFACE:
					if (type.is_pointer()) {
						return true;
					}
					GLib.Object? token = null;
					if (!this.mint_object_lease(type, out token)) {
						return false;
					}
					if (token != null) {
						this.request.connection.export(token);
						val = OLLMrpc.val("o", token);
					}
					return true;
```

(Same pattern for `dispatch_new`.)

---

## Acceptance

| Check | Pass |
| --- | --- |
| `tests/rpc/gi-test.vala` (or mock-server integration) — GI method returning registered object type | typed lease on wire, no GObject schema error |
| gnome-shell-rpc `gi-rpc-mock` + `register-class-trace-smoke.js` | passes `get_context` / compositor chain after `get_display` |
| Real `mutter-rpc` + `Gi` (no `register_mock`) | unchanged |

---

## Attempts / changelog

- ✔️ 2026-09-03 — Found during gnome-shell-rpc `gi-rpc-mock` bring-up; hello + Ffi bootstrap OK; first nested GI object returns fail. Bug filed here (consumer cannot fix).

## Next

⏳ 🔷 Implement typed mint in `GiMock.vala` → run `tests/rpc/gi-test.vala` → verify gnome-shell-rpc mock smokes.
