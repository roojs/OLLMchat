# RPC-1.7 — Mock dispatch (`register_mock` + `GiMock`)

> **Unblocks:** gnome-shell-rpc [`0.7.8-gi-rpc-noop-server`](../../../../git/gnome-shell-rpc/docs/plans/0.7.8-gi-rpc-noop-server.md) — fast import / registerClass smokes without nested Mutter.
>
> Landed. Index: [`RPC-1.0-summary.md`](../RPC-1.0-summary.md).

**Status:** **✔️** **done** — `libocrpc/MockDispatch.vala`, `libocrpc/GiMock.vala`, `libocrpc/Request.vala` (`register_mock` + dispatch branch), `libocrpc/Gi.vala` (protected virtual `dispatch_new` / `dispatch_function`, `skip_wire` for subclass).

**Prefix:** `RPC` (`libocrpc`) · see [`RPC-1.0-summary.md`](../RPC-1.0-summary.md)

**Depends on:** [`RPC-1.5-DONE-base-level-function-dispatch.md`](RPC-1.5-DONE-base-level-function-dispatch.md) **✔️**; [`RPC-1.6-DONE-live-handle-interface.md`](RPC-1.6-DONE-live-handle-interface.md) **✔️**

**🚫** Real compositor / `mutter-rpc` must **never** call `register_mock`.

---

## Purpose (shipped)

- **🔷** Test-only helper hook: {@link Request.register_mock} → {@link MockDispatch.dispatch}; return **true** when handled, **false** → {@link GiMock}.
- **🔷** {@link GiMock} extends {@link Gi}; inherits {@link Gi.dispatch} lookup; overrides {@link dispatch_new} / {@link dispatch_function} for typed empties (no invoke).
- **ℹ️** Mock server boot calls {@link Gi.register} (same static `types` / `namespaces` as real {@link Gi}) — not a separate `GiMock.register`.

**🚫** Not a production fallback. **🚫** Helper-* and client stubs live in the consumer repo.

---

## Dispatch order (shipped)

| Server | After `Ffi` |
| --- | --- |
| **Real** (`mutter-rpc`) | `new Gi(request).dispatch()` → invoke |
| **Mock** (`gi-rpc-mock`) | `register_mock` helper; if false → `return new GiMock(request).dispatch()` |

When `mock_handler == null`: Ffi → Gi → critical.

---

## Phase A — `MockDispatch` + `register_mock` **✔️**

- `libocrpc/MockDispatch.vala` — `bool dispatch(Request request)`; false falls through to {@link GiMock}.
- `Request.register_mock(MockDispatch handler)` — static `mock_handler`; replaces prior with debug log.

---

## Phase B — `GiMock` **✔️**

- `libocrpc/GiMock.vala` — `public class GiMock : Gi`
- Overrides {@link dispatch_new} (mint {@link GLib.Object}, export, reply) and {@link dispatch_function} (typed empty retval + OUT).
- {@link Gi}: `protected virtual dispatch_new` / `dispatch_function`; `protected skip_wire`.

---

## Phase C — Wire aliases **🚫 consumer**

Not libocrpc. Consumer mock boot:

- `Gi.register("Meta"|"Clutter"|"St", "16")` before `register_mock`
- Client {@link Live.Handle} stubs via {@link Bin.register} (see `tests/rpc/gi-test.vala`)
- Optional {@link Bin.register_alias} for X11/Wayland concrete GTypes

**ℹ️ Optional lib follow-up:** `GiMock.dispatch_new` mints plain {@link GLib.Object}; may encode as `GLib.Object` instead of wire alias until mint uses `Object.new(Gi.types.get(prefix))`.

---

## Phase D — Consumer (gnome-shell-rpc) **ℹ️**

```vala
Gi.register("Meta", "16");
Gi.register("Clutter", "16");
Gi.register("St", "16");
Request.register(RPC-Daemon, …);
Request.register_mock(new HelperMock());  // Helper-* switch; false → GiMock via Request.dispatch
```

---

## Phase E — Tests **🚫 consumer / out of scope here**

Mock-path smokes (`St-Widget.new`, namespace fn empties) belong in gnome-shell-rpc **0.7.8** or consumer CI — not required in libocrpc for this plan.

---

## Files

| Path | Role |
| --- | --- |
| `libocrpc/MockDispatch.vala` | Helper interface |
| `libocrpc/GiMock.vala` | Gi subclass — typed empty replies |
| `libocrpc/Gi.vala` | Protected virtual dispatch hooks |
| `libocrpc/Request.vala` | `register_mock` + dispatch branch |
| `libocrpc/meson.build` | `GiMock.vala` in `gi_src` |
