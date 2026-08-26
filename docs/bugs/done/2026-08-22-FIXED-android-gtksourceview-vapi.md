# FIXED: Android CI — `gtksourceview-5` vapi missing on the runner

**Status:** ✅ FIXED — host `libgtksourceview-5-dev` + R17. User closed.

**CI:** [32547800217](https://github.com/roojs/OLLMchat/actions/runs/32547800217)

---

## Problem

GitHub **Build chat APK** died compiling `libocmarkdowngtk`:

```text
error: Package `gtksourceview-5' not found in specified Vala API directories
```

Android wraps do not generate GtkSourceView vapi. `--pkg=gtksourceview-5` needs the **host** package. CI installed `libgtk-4-dev` / `libadwaita-1-dev` only. Local laptops already had `libgtksourceview-5-dev`. `verify-cross-compile.sh` used to omit `libocmarkdowngtk`, so local smoke never hit the line.

## Fix

- `libgtksourceview-5-dev` in `.github/workflows/x-android.yml` and `docs/android-build.md`.
- R17: fail if that package is missing from workflow/docs while meson still uses `--pkg=gtksourceview-5`.
- `verify-cross-compile.sh` builds `ollmchat-android-poc`.

ℹ️ Neighbor compile holes (same week, no separate open log): `gee_vapi_dir` on custom_targets (R19), WebKit wrap `v0.1.3` `network_session` (R18).
