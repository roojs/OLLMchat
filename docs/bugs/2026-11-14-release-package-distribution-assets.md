# Release assets belong on the packages GitHub Release

**Status:** ⏳ open — packaging / release layout. No code changes yet.

**Pointer:** `docs/bug-fix-process.md`

ℹ️ Related: [`done/2026-11-07-CLOSED-windows-redistributable-libraries.md`](done/2026-11-07-CLOSED-windows-redistributable-libraries.md) (Windows `.pkg.tar.zst` exist; this log is **where** they ship).

## Problem

- 🔷 **Windows library pacman packages** (`mingw-w64-ucrt-x86_64-lib*-any.pkg.tar.zst`) should live on the **`vX.Y.Z-packages`** GitHub Release with `.deb` / `.rpm`, not mixed into the version tag beside the installer.
- 🔷 **Android `.pixie` library packages** (`<name>-arm-v31-<version>.pixie`) should ship on **`vX.Y.Z-packages`** as well — same “package distribution” bucket as distro packages.
- 🔷 The published **Android APK** is named `ollmchat-android-v*-debug.apk` and is built from Gradle’s **`debug`** output. Release builds should not say “debug” unless we deliberately ship a debuggable APK and document why.

## Evidence

- ✔️ Publish (`.github/workflows/release.yml`) splits assets into `artifacts/main` (version tag) and `artifacts/packages` (`-packages` tag):
  - `*.deb|*.rpm` → packages
  - `*.pkg.tar.zst`, `*.pixie`, `*.apk`, `*.exe` → main
- ✔️ `docs/creating-releases.md` documents the same split: version tag has Setup.exe, all 15 Windows lib packages, APK, and per-library `.pixie` files; `v*-packages` is Debian/RPM only.
- ✔️ `scripts/release/render-release-notes.sh` tells users `.deb` / `.rpm` are on `${TAG}-packages` and calls the version tag “Windows and Android.”
- ✔️ Android CI (`.github/workflows/x-android.yml`) always copies  
  `.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk`  
  to `ollmchat-android-${GITHUB_REF_NAME}-debug.apk`.
- ✔️ `scripts/android/build-pixiewood-apk.sh` configures Meson with **`--buildtype debug`** always. Tag releases set `PIXIEWOOD_STRIP_DEBUG=1`, which only enables **`-Dstrip=true`** on install (smaller native libs); it does not change Gradle variant or the APK filename.
- ℹ️ There is **no** `assembleRelease` / `release` APK path in this tree (grep is empty). Pixiewood/Gradle may only expose a debug APK today.

## Root cause

- ⏳ Not fully confirmed for “why debug only.” Layout cause is explicit: **publish sorts library packages into the version tag** by design in `release.yml` and `creating-releases.md`.
- 💩 Android “debug” in the release filename is **intentional given current build scripts** (debug Meson buildtype + Gradle `debug` folder), not a mis-label of a release Gradle variant we never build.

## Proposed fix

### Package distribution (`v*-packages`)

- 🔷 Move **`*.pkg.tar.zst`** and **`*.pixie`** from `artifacts/main` to **`artifacts/packages`** in the publish `case` statement (keep `*.exe`, `*.apk`, optional AppImage on the version tag).
- 🔷 Update **`docs/creating-releases.md`**, **`scripts/release/render-release-notes.sh`**, and release notes copy so “packages” means Debian, RPM, **Windows UCRT64 libs**, and **Android pixies**.
- 💩 Confirm **[roojs package repositories](https://roojs.github.io/repos/)** ingest watches **`v*-packages`** for any new asset types (doc already hints ingest may need `-packages`).

### Android APK naming / build type

- 🔷 **User direction (2026-11-14):** ship a **proper release APK** on the version tag (option **B**), not a renamed debug artifact.
- 🔷 Tag / **Release** path: Meson **`--buildtype release`** (or `minsize` if we document why), Gradle **`assembleRelease`**, asset name **`ollmchat-android-<tag>.apk`** (no `-debug`). **`PIXIEWOOD_STRIP_DEBUG`** may fold into that path or go away once release install rules own stripping.
- 🔷 **Release signing** is still missing (`docs/android-build.md` lists it under “does not yet run”). Need a CI keystore (GitHub secret) or an explicit sideload policy (unsigned release is not installable on most devices).
- 🔷 **Do not publish both variants on tag builds by default** — one native compile + one Gradle variant keeps CI time sane. Keep full **debug** for manual **Release - Android** and local dev.
- ℹ️ **Build time (dual vs single):**
  - **Release-only on tags** (replace today’s debug+strip): one Meson configure/compile. Release objects cost more CPU than debug, but it is still **one** pass — typically **not** a doubling; often modestly **slower** than debug on a cold cache, sometimes similar when the compile cache hits.
  - **Both APKs from one native tree** (`assembleDebug` then `assembleRelease` with the same `jniLibs`): Gradle-only second step — usually **minutes**, not hours.
  - **Both APKs with different Meson buildtypes** (debug tree + release tree): **two full native rebuilds** — that **does** approach **2×** the expensive part of the Android job (Pixiewood/Meson compile dominates when caches miss).

## Next

- ⏳ 🔷 User confirms: libraries + pixies **only** on `-packages` (installer + APK stay on version tag), or a different split.
- ⏳ 💩 Implement Android **B** + signing before the next tag publish.
- ⏳ 💩 After approval, adjust `release.yml` publish step and docs; re-run a manual **Release - …** smoke or wait for next tag.

## Attempts / changelog

- ✔️ 2026-11-14 — opened this log from release-field review (Windows libs, pixies, APK `-debug`).
- ✔️ 2026-11-14 — user chose proper release APK on tags; dual publish optional, dual native buildtypes would hurt CI most.