# FIXED: Gi IN: lease id 0 (null Handle) → INVALID_PARAMS

**Status:** ✔️ FIXED — `convert_interface` accepts lease `0` / null object when `may_be_null`; await consumer re-smoke

**Reporter:** gnome-shell-rpc (2026-09-06)  
**Component:** `libocrpc` — `Gi.convert_interface`

## Hit

Nested `mutter-rpc` boot (T-030 / Layout):

`Clutter-Actor.set_child_below_sibling(child, null)` → RPC `-32602` (empty message).

Same pattern: any Gi method with a trailing nullable object IN.

## Cause

`gnome-shell-rpc` `call_value` packs a null `GLib.Object` as **`uint64` lease id `0`** (`src/namespace.vala`).

`Connection.export` never issues id `0` (`next_handle` starts at 1).

`Gi.convert_interface` treated the wire value as a lease lookup and rejected missing id `0`, even when `GI.ArgInfo.may_be_null()` is true.

## Fix applied

✔️ In `convert_interface` OBJECT/INTERFACE IN:

- lease id `0` + `may_be_null` → `v_pointer = null`
- lease id `0` + not nullable → `INVALID_PARAMS`
- object `Value` with `get_object() == null` → same nullable rule (avoids SEGV on `.get_type()`)

## Refs

- ℹ️ Plan: `gnome-shell-rpc` `docs/plans/0.7.7-thin-shell-bootstrap.md` T-030 L2  
- ℹ️ Related (done): `docs/bugs/done/2026-09-05-FIXED-ollmrpc-null-object-to-value.md` (encode side)  
