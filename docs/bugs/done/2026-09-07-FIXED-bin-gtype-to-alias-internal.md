# FIXED: Bin.gtype_to_alias is internal — consumers cannot reverse-lookup

**Status:** ✔️ FIXED — `gtype_to_alias` public (parity with `alias_to_gtype`); await consumer re-smoke

**Reporter:** gnome-shell-rpc (2026-09-07)  
**Component:** `libocrpc` — `Bin.Stream` registration maps

## Need

🔷 Client lease-on-construct (gnome-shell-rpc L4) walks `get_type()` → parents and needs the **wire alias** for the first registered GType so it can call `alias + ".new"` (e.g. `St-Button.new` instead of a base stealing `Clutter-Actor.new`).

That reverse map already exists: `Bin.gtype_to_alias` (filled by `Bin.register` / `register_alias`). Forward map `Bin.alias_to_gtype` is **public**; reverse was **`internal`**, so out-of-tree consumers could not use it.

## Fix applied

✔️ Make `gtype_to_alias` **public** (parity with `alias_to_gtype`). No second registry; no new helper.

## Refs

- ℹ️ `libocrpc/Bin/Stream.vala` — both maps public  
- ℹ️ Related (done): `docs/bugs/done/2026-09-06-FIXED-gi-null-lease-id-zero-invalid-params.md`
