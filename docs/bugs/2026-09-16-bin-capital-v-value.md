# Bin / args: capital-`V` Value (type + data → `GLib.Value`)

**Status:** ⏳ propose — await approval (no libocrpc code yet)  
**Hit:** 2026-09-16 — gnome-shell-rpc Transition / Interval / ease corridor  
**Component:** `libocrpc` — `Bin.StreamValue`, `args` / `val`, `Ffi.pack`, protocol § type bytes  
**Consumer gate:** `gnome-shell-rpc/tests/call-sync-repro/value-v-gate` (**FAIL** until this lands)  
**Consumer context:** nest chrome / `Helper-Transition.set_relay_value` (`bsid` kind casting); Gi pin path already green (`gvalue-in-gate`, `clutter-interval-gvalue-gate`)

---

## Problem

🔷 Consumers need to move a **typed value** across the RPC (fundamentals now; boxed `Graphene.*` / colors later) and rebuild a compositor-local `GLib.Value` for stock APIs (`set_to_value`, `set_final_value`, `child_set_property`, …).

🔷 Today they pick among three bad or incomplete options:

1. **Kind casting** — wire `bsid` (bool + kind letter + int + double); Helper `switch (kind)` rebuilds the `GValue`. Duplicated on client (`to_wire`) and server (`from_wire`). Does not scale to boxed.
2. **`ay` memcpy of the `GValue` struct** — generator default for `GObject.Value`; cannot work across processes.
3. **Flattened wire row + Gi pin** — `StreamValue` already writes type byte + payload; Gi pins that row for GIR `GValue*` (`gvalue-in-gate` PASS). Fine for typelib invoke; **not** a first-class Helper / generator / args letter, so consumers still invent (1).

🔷 Expected: one OPC **capital-`V` Value** — wrap that sends **Type + Data** on the wire and decodes to a `GLib.Value` on the peer. Helpers take `GLib.Value`; generator packs `V`, not `ay` / not `bsid`.

🔷 Actual: `args` / `Ffi` have lowercase **`v` = `GLib.Variant`** only. No capital-`V`. Protocol has no named Value wrap beyond “whatever fundamental `StreamValue` emitted.”

---

## Evidence

ℹ️ `OLLMrpc.args` / `to_value` (`libocrpc/namespace.vala`): letters include `v` → Variant; **no `V`**. Unknown tag → `GLib.error`.

ℹ️ `Ffi.pack` (`libocrpc/Ffi.vala`): same letter set; no `V` → falls through to int32 default.

ℹ️ `Bin.StreamValue.write` already encodes **type byte + payload** for fundamentals / `GLib.Bytes` / objects. That *is* Type+Data for a flattened row — but:

- Helper signatures cannot say `"V"` (D-Bus `VariantType.string_scan("V")` fails; not special-cased like `"f"` / `"S"`).
- Consumers therefore invent kind switches (`Helper-Transition` `bsid`) instead of `bV` / `V`.
- Boxed held types that are not `GLib.Bytes` → `unsupported bin value type` (no GType+payload path).

ℹ️ Consumer archive:
[`gnome-shell-rpc/docs/bugs/done/2026-09-16-transition-interval-gvalue-wire.md`](file:///home/alan/git/gnome-shell-rpc/docs/bugs/done/2026-09-16-transition-interval-gvalue-wire.md)
— chose `bsid` relay; explicitly rejected “hold `GLib.Value` in `Request.args`” as a *generator* design without a named OPC Value type.

ℹ️ Gi GObject.Value pin remains valid for typelib `GValue*` IN/OUT (`done/2026-09-11-FIXED-gi-gvalue-property-args.md`). This bug does **not** reopen that. Capital-`V` is the **intentional** API for Helpers + generator packing.

---

## Root cause

✔️ Missing first-class **Value** on the RPC layer: signature letter + Ffi pack + documented wire shape (Type + Data → `GLib.Value`). Flattened `StreamValue` rows and Gi pin are not a substitute for that API, so gnome-shell-rpc grows per-site casting.

---

## Proposed fix

💩 **Capital-`V`** (keep lowercase `v` = Variant).

### 1. API

```vala
var held = GLib.Value(typeof(float));
held.set_float(1.25f);
req.args = OLLMrpc.args("V", held);
// Helper:
//   add_class(..., "set_relay_value", "bV", null);
//   void set_relay_value(Request request, bool is_to, GLib.Value value)
```

`val("V", held)` for a single retval when needed.

### 2. Wire (Type + Data)

Reuse **`StreamValue.write` / `read`** for the held content:

- Fundamentals: existing type byte + payload (same as today’s flattened row).
- Objects / live: existing `write_gtype` path.
- **Later tier — typed boxed:** GType alias (or `TOKEN_REG_TYPE`) + payload bytes / fields — not naked `BOXED` without type identity.

Optional nesting: if a bare float row must stay distinguishable from “Value holding float”, introduce a reserved outer type byte for the wrap; **tier-1** may flatten (Gi pin + Helpers both accept a held float row). Document the choice in `docs/bin-rpc-protocol.md`.

### 3. `args` / `val` / `Ffi`

Special-case `"V"` like `"f"` / `"S"` (not D-Bus-complete):

| Site | Behavior |
| --- | --- |
| `to_value("V")` | `l.arg<GLib.Value>()` → that Value (copy into list) |
| `Ffi.pack("V")` | pin a `GLib.Value` copy; slot = `GValue*` (`Libffi.POINTER`) for Vala `GLib.Value` param |
| `Ffi.dispatch` signature scan | accept `"V"` as one wire arg / one slot |

### 4. Consumer migration (after PASS)

🚫 Do **not** edit gnome-shell-rpc from OLLMchat. After `value-v-gate` PASS:

- Replace `Helper-Transition` `bsid` + `to_wire` / `from_wire` with `"bV"` + `GLib.Value`.
- Generator: `GObject.Value` IN → pack `V`, never `ay` memcpy.
- Interval / LayoutManager property sites share the same letter.

### 5. Rejected

🚫 New Shared switch class in the consumer (`GValueFundamental` / per-Helper kind tables).  
🚫 Shipping raw `GValue` struct bytes (`ay`).  
🚫 Inventing more kind letters per fundamental forever.  
🚫 Replacing Gi pin for GIR `GValue*` (keep pin; `V` is the Helper/generator face).

---

## Gate (FAIL → PASS)

```bash
meson compile -C build value-v-gate
timeout 5 ./build/tests/call-sync-repro/value-v-gate
```

**FAIL today:** no capital-`V` args/Ffi support (gate exits 1 with this bug path).

**PASS when:** `OLLMrpc.args("V", held)` round-trips through a Live Helper `echo_value` / `set_relay_value` style method with signature `"V"` (or `"bV"`), peer sees correct `value.type()` and payload; no kind string.

In-tree follow-up (this repo, after approve): `tests/rpc/` smoke mirroring the consumer gate.

---

## Attempts / changelog

- ⏳ 2026-09-16 — Proposal from gnome-shell-rpc (Transition `bsid` vs Gi flatten vs `ay`). Gate filed consumer-side **FAIL**. No libocrpc edit until approve.

---

## Next

⏳ User approve wire + `"V"` letter shape (flatten vs nested outer type byte for tier-1).  
⏳ Implement `args` / `Ffi` / protocol note; turn `value-v-gate` green.  
⏳ Consumer drops `bsid` casting.
