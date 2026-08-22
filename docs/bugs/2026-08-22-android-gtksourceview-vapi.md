# Android CI: `gtksourceview-5` vapi missing on the runner

**Status:** ✔️ local `ollmchat-android-poc` linked — not user-verified on GitHub

**Opened:** 2026-08-22  
**CI:** [32547800217](https://github.com/roojs/OLLMchat/actions/runs/32547800217)

## Problem

- 🔷 GitHub **Build chat APK** fails after R14–R16 configure.
- 🔷 Expected: Vala compile of `libocmarkdowngtk` succeeds like a local laptop.
- 🔷 Actual:

```text
FAILED: libocmarkdowngtk/libocmarkdowngtk.so.p/…
error: Package `gtksourceview-5' not found in specified Vala API directories
```

## Evidence

- ℹ️ Previous run [32546682700](https://github.com/roojs/OLLMchat/actions/runs/32546682700) died on `ocrpc.vapi` / `gee-0.8` (fixed by `gee_vapi_dir` on the custom_target).
- ℹ️ This run compiled `libocrpc` then died on `--pkg=gtksourceview-5`.
- ℹ️ `gtk4.vapi` is in `valac`'s versioned vapidir (`/usr/share/vala-0.56/vapi`). `gtksourceview-5.vapi` is only in `/usr/share/vala/vapi` from `libgtksourceview-5-dev`.
- ℹ️ `.github/workflows/x-android.yml` installed `libgtk-4-dev` and `libadwaita-1-dev`, not `libgtksourceview-5-dev`.
- ℹ️ `scripts/android/verify-cross-compile.sh` compiled a library subset that omitted `libocmarkdowngtk` / `libocrpc` / the app, so local smoke never hit this valac line. Even with that target, a desktop already has the vapi.

## Root cause

- ✔️ Android wraps do not generate GtkSourceView vapi (introspection off; `generate_vapi` follows GIR).
- ✔️ `--pkg=gtksourceview-5` therefore needs the **host** vapi package. CI did not install it. Local developers do.

## Proposed fix

- 🔷 Add `libgtksourceview-5-dev` next to `libgtk-4-dev` in `x-android.yml` and `docs/android-build.md`.
- 🔷 R17: fail if that package is missing from the workflow/docs while meson still uses `--pkg=gtksourceview-5`.
- 🔷 `verify-cross-compile.sh` always builds `ollmchat-android-poc` (and the libs CI compiles). `--full` runs it.

## Attempts / changelog

- ✔️ 2026-08-22 — apt line + R17 + compile-script expansion.
- ✔️ 2026-08-22 — local `ninja ollmchat-android-poc` after Meson 1.11 reconfigure: `libollmchat-android-poc.so` linked.
- ✔️ Local compile reached the app: `OLLMcoder.AgentPi` missing because Android meson omitted `subdir('liboccoder')` (full occoder needs ocfiles / SourceView). Catalog-only `liboccoder` on Android (`Skill.vala` + `SkillSet.vala`); POC links `--pkg=occoder`. 🚫 Do not copy those sources into `ollmapp`.
