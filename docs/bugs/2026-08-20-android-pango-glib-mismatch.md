# Android CI: pango `main` needs glib >= 2.88

**Status:** ⏳ wrap pin was gitignored; moved off `subprojects/` — await GitHub Android re-run

**Opened:** 2026-08-20  
**CI:** [Release - Android 32241554256](https://github.com/roojs/OLLMchat/actions/runs/32241554256) (glib mismatch), [32322629999](https://github.com/roojs/OLLMchat/actions/runs/32322629999) (R14 missing wrap)

## Problem

- 🔷 GitHub Android configure fails in `--full` CI preflight (`verify-android-ci-preflight.sh`).
- 🔷 Expected: Meson configure succeeds with the same glib 2.84.0 pin used locally.
- 🔷 Actual:

```text
Dependency glib-2.0 for host machine found: NO found 2.84.0 but need: '>= 2.88' (overridden)
subprojects/pango/meson.build:233:11: ERROR: Dependency 'glib-2.0' is required but not found.
```

## Evidence

- ℹ️ Fast tests R01–R13 passed; failure is R06 / preflight configure.
- ℹ️ CI cloned **pango 1.58.2** from GTK nested wrap `revision = main`.
- ℹ️ Local `subprojects/pango` is **1.57.2** (`fa2ba89e7ed0907c8852add50cb13edefe93e66e`, 2026-06-14) and only needs glib **>= 2.82**.
- ℹ️ Local APK `.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk` is from **2026-07-23**.
- ℹ️ `android/pixiewood-wraps/glib/glib.wrap` and R13 pin glib at **2.84.0** for the TLS patch.
- ℹ️ Top-level `subprojects/pango.wrap` is a wrap-redirect into `gtk/subprojects/pango.wrap`.

## Root cause

- ✔️ GTK’s nested `pango.wrap` tracks `main`. A clean CI checkout clones current pango; a local tree reuses the old checkout. `--full` locally does not re-clone (`PIXIEWOOD_SKIP_SUBPROJECTS_DOWNLOAD=1` plus an existing `subprojects/pango`).

## Proposed fix

- 🔷 Pin GTK nested pango to the 1.57.2 commit that already built with glib 2.84.0.
- 🔷 Overlay that wrap after every GTK bootstrap/restore so GitHub cache restore cannot put `revision = main` back.
- 🚫 Do not bump glib (would need TLS patch rebase).

#### Add `android/pixiewood-wraps/gtk/nested-pango.wrap`

Pinned `wrap-git` (same `[provide]` as upstream GTK wrap; `revision` is `fa2ba89e7ed0907c8852add50cb13edefe93e66e`).
Not under a `subprojects/` directory: root `.gitignore` matches any path named `subprojects/`.

#### Replace `scripts/android/gtk-subproject.sh` — after GTK is patched, copy the pin onto `subprojects/gtk/subprojects/pango.wrap` before bootstrap save.

#### Add `scripts/android/regression/test-r14-pango-wrap-not-main.sh` and a row in `docs/android-build-regression-tests.md`.

## Attempts / changelog

- ✔️ 2026-08-20 — pinned wrap + copy after GTK patch + R14.
- ✔️ 2026-08-20 — [32322629999](https://github.com/roojs/OLLMchat/actions/runs/32322629999) died in 43s: `pinned pango.wrap missing`. Tracked path was `android/pixiewood-wraps/gtk/subprojects/pango.wrap`, ignored by `.gitignore` `subprojects/`. Moved to `nested-pango.wrap`; R14 now fails if `git check-ignore` matches the pin.
- ⏳ GitHub `Release - Android` re-run after this path fix.
