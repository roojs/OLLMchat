# RPC-1.8 — Vfunc relay: `Gi.vfunc_*` offset lookups; container = plain map field

**Status:** **✔️** agent implemented — `test-rpc-gi` green; awaiting user verify.

**Files:** `libocrpc/Gi.vala` (edit), `libocrpc/windows/Gi.vala` (edit — stub statics), `tests/rpc/gi-test.vala`. **No new files, no new types, no meson change.**

**Prefix:** `RPC` (`libocrpc`) · see [`RPC-1.0-summary.md`](RPC-1.0-summary.md)

**Unblocks:** gnome-shell-rpc `0.8.2-vfunc-hook-registry` — consumer relays
GObject vfuncs (`get_preferred_width`, `allocate`, `event`, …) over live
callbacks. With this plan its share shrinks to: minting peers (`create`)
and `add_hook`, the sentinel protocol, and per-signature arg packing.

**Related:** [`done/RPC-8.3.6-rpc-live-callbacks.md`](done/RPC-8.3.6-rpc-live-callbacks.md) (Live.Hook round-trip) · [`done/RPC-1.6-DONE-live-handle-interface.md`](done/RPC-1.6-DONE-live-handle-interface.md) (interface-for-peers precedent) · [`done/RPC-8.4.2-DONE-rpc-ffi-typelib-invoke.md`](done/RPC-8.4.2-DONE-rpc-ffi-typelib-invoke.md) (Gi typelib engine).

**🚫** No library wire methods — `create` **and** `add_hook` are
consumer-registered (the consumer casts the lease to its own peer type);
this plan provides only the offset lookups.  
**🚫** No new types — the lookups land on the existing `Gi`; the
container is a plain `Gee.HashMap<string, Live.Hook>` field on the
consumer's peer.  
**🚫** No shared `add_hook` body / delegate — the consumer's wire method
validates / inserts / replies inline (user call 2026-09-13: "no way we
will accept a delegate").  
**🚫** No dict / array args support — scalar `st` per hook is enough.  
**🚫** No per-signature vfunc invoke (see Future) — arg packing stays
consumer-side for now.

Edits are **Keep** / **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying. Each edited method is shown **top → bottom in full**.

**Slugs read for proposed Vala:** `temporary-variables`, `this-prefix`, `reducing-nesting`, `defensive-code-null-checks`, `method-names-new-methods`, `line-length-breaking`, `docblocks`, `underscore-prefix`, `property-initialization`, `brace-placement`, `agent-compliance-gate` (+ `docs/code-documentation.md`); Meson: `docs/build-rules.md`

---

## Purpose

- **🔷** `Gi.vfunc_offset` / `Gi.vfunc_slot` / `Gi.vfunc_names` — three
  statics on the **existing** typelib engine: vfunc slot lookup **by
  name** via `class_struct` field offsets, so no consumer hand-maintains
  C struct prefixes of some toolkit's class ABI; and vfunc **name
  enumeration** from the typelib, so consumer override detection walks
  the real vfunc list instead of a hardcoded string array. The cache is
  nested with **real keys** (ns → class → vfunc name) — no composite
  string keys.
- **🔷** The container is **not a class** — a plain, eager-initialized
  `Gee.HashMap<string, Live.Hook>` field on the consumer's peer;
  `map.get(name)` returning `null` **is** the capability check. No
  per-vfunc fields, no flag bits, no wrapper.

**ℹ️** Structure — user calls 2026-09-13: **zero new types, zero new
methods beyond the lookups**. Drafted and dropped: `Live.Vfuncs`
(pointless wrapper — `get` is trivial; the map field lives on the
peer), `VfuncPeer` + library ''RPC-Live-Vfuncs'' wire class
(''add_hook'' is consumer-owned — the consumer casts the lease to its
own peer type, so the library needs no lease→container bridge),
`GiVfunc` ("mostly part of another class" — the offsets belong on
`Gi`, the girepository home), and a shared `add_hook` body on
`Live.Callback` (no delegate — the consumer's wire method does the
validate/insert/reply inline). Statics on `Gi` match its existing idiom
(`types` / `namespaces` are static registries; the per-request instance
dispatch is untouched).

---

## Why

A consumer relaying GObject vfuncs over {@link Live.Hook} today hand-rolls
all of it. gnome-shell-rpc's `LayoutHooks` grew four nullable `Hook` fields
+ a `uint32` flag map + positional `create` args + a hand-counted C struct
mirroring `ClutterActorClass`; adding one vfunc (`event`) touched nine
places across four files, and ~15 LayoutManager subclasses need the same
relay next. The intended shape was always: look the vfunc up **by name** —

```
peer → HashMap<string, Live.Hook>
```

Everything in this plan compiles against types libocrpc already has
(`GI.Repository` via `Gi`) — zero consumer deps, no new library
dependency, no new types.

**ℹ️** What deliberately does **not** move (stays with the consumer):

| Piece | Why |
| ----- | --- |
| `create` / peer minting | consumer picks the peer type (`Request.add_class` is consumer policy) |
| `add_hook` wire method | consumer casts the lease to its own peer type; validate/insert/reply inline — no library bridge, no shared body |
| Sentinel / fallthrough protocol (`use_base` mid-ask base calls) | consumer correctness contract |
| Per-signature bind + emit arg packing | Clutter types on the wire — see Future |
| Which vfuncs to relay + baseline compare policy | consumer knows its stub classes |

---

## Fix

### 1. `libocrpc/Gi.vala` — add vfunc offset statics **✔️**

**Why:** Vfunc slot lookup **by name** from typelib metadata
(`class_struct` field offsets) — replaces consumer C structs that
hand-count padding to mirror a toolkit class ABI. `Gi` is the
girepository home and already platform-conditional; the statics ride
along. No new class, no new file, no new dep.

**Where:** see `OLLMrpc.Gi.vfunc_offset` / `vfunc_slot` / `vfunc_names`
(and `vfunc_offsets` cache) in `libocrpc/Gi.vala`; matching
`GLib.error` stubs in `libocrpc/windows/Gi.vala`.

**Depends on:** nothing new.

### 2. Tests — `tests/rpc/gi-test.vala` **✔️**

**Why:** Prove the offset lookup on the existing harness.

**Where:** after `Gi.register("Gio", "2.0")` — `Application` `startup` /
`activate` offsets, cache hit, `vfunc_slot` vs direct class-struct
read, `vfunc_names` contains those names.

**Depends on:** 1.

**Done when (agent):** `meson test -C build test-rpc-gi` green.

---

## Future (not this plan) **💩**

Generic vfunc **invoke** via `g_vfunc_info_invoke` — would replace the
consumer's per-signature client binders (and possibly server emit packing)
with typelib-driven marshalling, reusing the `Gi.convert` / `scalar`
machinery. Needs `Gi.convert` decoupled from `Request`, plus integration
with the consumer's fallthrough sentinel protocol. Separate `RPC-1.9` if
the per-signature trampolines ever become the bottleneck.

---

## Not this

| | |
| - | - |
| New container / wire / peer / offsets classes (`Vfuncs`, `VfuncPeer`, `RPC-Live-Vfuncs`, `GiVfunc`) | all dropped — the lookups land on the existing `Gi` (user calls 2026-09-13) |
| Shared `add_hook` body on `Live.Callback` | dropped — no delegate; the consumer's wire method validates/inserts/replies inline (same user call) |
| Library-owned wire methods | consumer owns `create` + `add_hook` |
| Sentinel / fallthrough protocol | consumer correctness contract |
| Per-signature arg packing | consumer-side (see Future) |
| Dict/array wire types | unneeded; scalar `st` per hook is enough |
| Windows/Android offsets | no girepository there — `windows/Gi.vala` stubs |

**Done when:** gi-test green; gnome-shell-rpc 0.8.2 consumes
`Gi.vfunc_*` — no new library types, no C slot reader.
