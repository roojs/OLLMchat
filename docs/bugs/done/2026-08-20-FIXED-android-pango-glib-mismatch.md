# FIXED: Android CI pango `main` needs glib >= 2.88

**Status:** ✅ FIXED — pango / libadwaita wrap-git pinned; R14–R16. User closed.

**CI:** [32241554256](https://github.com/roojs/OLLMchat/actions/runs/32241554256) (glib mismatch) through [32441610454](https://github.com/roojs/OLLMchat/actions/runs/32441610454) (clone pin before Meson download)

---

## Problem

GitHub Android configure failed: pango from GTK nested wrap `revision = main` needed glib `>= 2.88` (then 1.58.2) while Android glib is pinned at 2.84.0. Same class of hole then fetched libadwaita `main` needing glib `>= 2.89.3`. Local `--full` reused frozen checkouts (`PIXIEWOOD_SKIP_SUBPROJECTS_DOWNLOAD=1`).

## Fix

- Pin GTK nested pango to `fa2ba89e` (1.57.2) via `android/pixiewood-wraps/gtk/pango.wrap.pin` (not `*.wrap`, not under gitignored `subprojects/`).
- Overlay that wrap after GTK bootstrap; discard checkout unless `HEAD` is the pin.
- Pin libadwaita to `dc468f08`.
- Clone pango/libadwaita at their pins before Meson download (`freetype2.wrap` wrap-redirect).
- R14 / R15 / R16 in `docs/android-build-regression-tests.md`.

🚫 Do not bump glib for this cut.
