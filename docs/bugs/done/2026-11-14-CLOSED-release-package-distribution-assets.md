# Release assets belong on the packages GitHub Release

**Status:** ✅

- ✅ Closed 2026-11-26. The GitHub release these assets belong on is done.

**Pointer:** `docs/bug-fix-process.md`

ℹ️ Related: [`2026-11-07-CLOSED-windows-redistributable-libraries.md`](2026-11-07-CLOSED-windows-redistributable-libraries.md) (Windows `.pkg.tar.zst` exist; this log is **where** they ship).

## Problem

- 🔷 **Windows library pacman packages** (`mingw-w64-ucrt-x86_64-lib*-any.pkg.tar.zst`) should live on the **`vX.Y.Z-packages`** GitHub Release with `.deb` / `.rpm`, not mixed into the version tag beside the installer.
- 🔷 **Android `.pixie` library packages** (`<name>-arm-v31-<version>.pixie`) should ship on **`vX.Y.Z-packages`** as well — same “package distribution” bucket as distro packages.
- 🔷 The published **Android APK** should not use `ollmchat-android-` in the filename (`.apk` is enough). Tag builds should ship a **release** Gradle APK; **debug** may stay for now until evaluated.

## Evidence

- ✔️ Publish (`.github/workflows/release.yml`) splits assets into `artifacts/main` (version tag) and `artifacts/packages` (`-packages` tag):
  - `*.deb|*.rpm` → packages
  - `*.pkg.tar.zst`, `*.pixie`, `*.apk`, `*.exe` → main
- ✔️ `docs/creating-releases.md` documents the same split: version tag has Setup.exe, all 15 Windows lib packages, APK, and per-library `.pixie` files; `v*-packages` is Debian/RPM only.
- ✔️ Prior tag builds: `ollmchat-android-${tag}-debug.apk` only, Meson `--buildtype debug`, `assembleDebug` only.

## Root cause

- ⏳ Layout: **publish sorts library packages into the version tag** by design in `release.yml` and `creating-releases.md`.
- ✔️ Android: no `assembleRelease` path or release asset name before 2026-11-15.

## Proposed fix

### Package distribution (`v*-packages`)

- 🔷 Move **`*.pkg.tar.zst`** and **`*.pixie`** from `artifacts/main` to **`artifacts/packages`** in the publish `case` statement (keep `*.exe`, `*.apk`, optional AppImage on the version tag).
- 🔷 Update **`docs/creating-releases.md`**, **`scripts/release/render-release-notes.sh`**, and release notes copy so “packages” means Debian, RPM, **Windows UCRT64 libs**, and **Android pixies**.
- 💩 Confirm **[roojs package repositories](https://roojs.github.io/repos/)** ingest watches **`v*-packages`** for any new asset types.

### Android APK (user 2026-11-14 / 2026-11-15)

- 🔷 **Filename:** `ollmchat-<tag>.apk` and `ollmchat-<tag>-debug.apk` (no `android` infix). Manual workflow: `ollmchat-poc-debug.apk`.
- 🔷 **Tag builds:** one native compile; **`assembleDebug` + `assembleRelease`** (`PIXIEWOOD_ASSEMBLE_RELEASE=1` when `upload_to_release`). User will decide later whether to drop the debug attachment.
- 🔷 **Signing:** release variant uses **`signingConfigs.debug`** until a release keystore is wired in CI (`OLLMCHAT_SIDLOAD_RELEASE_SIGNING` in generated `build.gradle`).
- 💩 **Later:** Meson `release` buildtype for the release APK’s native libs; proper release signing.

## Next

- ⏳ 🔷 User confirms: libraries + pixies **only** on `-packages` (installer + APK stay on version tag).
- ⏳ 💩 Ship `release.yml` publish split for Windows libs + pixies.
- ⏳ 💩 Smoke **Release - Android** with `upload_to_release` on a branch (or wait for next tag).

## Attempts / changelog

- ✔️ 2026-11-14 — opened this log from release-field review (Windows libs, pixies, APK `-debug`).
- ✔️ 2026-11-14 — user chose proper release APK on tags; dual Gradle build acceptable.
- ✔️ 2026-11-15 — user: drop `android` from tag APK names; publish debug + release on tags for now.
- ✔️ 2026-11-15 — `build-pixiewood-apk.sh`: `PIXIEWOOD_ASSEMBLE_RELEASE`, release signing patch, dual `gradlew`. `x-android.yml`: collect `ollmchat-<tag>.apk` + `-debug.apk`; verify all artifacts. Docs + `CHANGELOG.md` updated.