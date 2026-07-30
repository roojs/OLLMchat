# FIXED: Clean Linux build fails — `Failed to parse included gir OLLMfiles-1.0`

**Status:** ✔️ fixed (typelibs build on clean tree)

## Problem

🔷 On a fresh machine / clean `ninja -C build`:

```text
error parsing file …/OLLMchatGtk-1.0.fixed.gir: Failed to parse included gir OLLMfiles-1.0
error parsing file …/OLLMcoder-1.0.fixed.gir: Failed to parse included gir OLLMfiles-1.0
```

## Evidence

- ✔️ `scripts/compile-gir-typelib.sh` injects `<include name="OLLMfiles" version="1.0"/>`.
- ✔️ `libocfiles` had no `vala_gir` (Windows Meson rejects `vala_gir: []`).
- ✔️ Library `vala_gir` cannot be restored: `CallParam.vala` is top-level `OLLMfilesd` → Vala *Secondary top-level namespace not supported by GIR format*.

## Root cause

✔️ Dependents need `OLLMfiles-1.0.gir`, but `vala_gir` on `libocfiles` is impossible while CallParam (`OLLMfilesd`) is in the same compile unit.

## Fix

🔷 On Linux, generate GIR out-of-band:

1. `ollmfilesd-callparam.vapi` from `CallParam.vala`
2. `scripts/generate-ollmfiles-gir.sh` — Valac in a temp dir (avoids clobbering `ocfiles.vapi`) with sources **minus** CallParam + `--pkg=ollmfilesd-callparam`
3. Compile typelib; occoder / ollmchatgtk / octools typelib `depends` include that GIR
