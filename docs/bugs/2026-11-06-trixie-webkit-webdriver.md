# Trixie has no WebDriver library built on Debian

**Status:** ⏳ open. Trixie packages link stock WebKit until a Debian build exists.

## Problem

- 🔷 Debian 13 packages must link `libwebkitgtk-6.0-webdriver`, the same as the Ubuntu packages.
- 🔷 `libwebkitgtk-6.0-webdriver-dev` is not in the roojs trixie suite, and it is not a Debian package.
- 🔷 Disabling WebDriver for the Trixie job is a hold. It is not the package we ship.
- 🔷 The library has to be built on a Debian box, published, then downloaded from that GitHub release.

## Evidence

- ✔️ Release `v1.4.6` run `42189995538`, job **Trixie packages**: `E: Package 'libwebkitgtk-6.0-webdriver-dev' has no installation candidate`. Exit 100.
- ✔️ Release `v1.4.6` run `42186821962` installed the Ubuntu 25.04 debs (`2.50.4-0ubuntu0.25.04.1+webdriver6`) plus Ubuntu `libjpeg8`. The link failed. `libwebkitgtk-6.0-webdriver.so.4` has undefined references to `WTF::*`, `JSC::*`, `bmalloc::*`, and `Inspector::*`. Trixie's `libjavascriptcoregtk` does not provide those symbols.
- ℹ️ [webkitgtk-automation](https://github.com/roojs/webkitgtk-automation) releases are Ubuntu builds only: 25.04 (`2.50.4`), 25.10 (`2.52.3`), 26.04 (`2.52.6`). Workflows: `build-plucky.yml`, `build-questing.yml`, `build-resolute.yml`, `build-stonking.yml`. No Debian workflow. No `trixie` release.
- ℹ️ Latest release assets (25.10): `libwebkitgtk-6.0-webdriver4_2.52.3-0ubuntu0.25.10.1+webdriver5_amd64.deb` and `libwebkitgtk-6.0-webdriver-dev_2.52.3-0ubuntu0.25.10.1+webdriver5_amd64.deb`.
- ℹ️ Questing WebDriver depends on `libxml2-16` and a newer glibc than Trixie. Resolute depends on `libc6 >= 2.43` and `libicu78`. Those debs will not install on Debian 13.
- ℹ️ The hold in this repo: `.github/workflows/x-debian.yml` **Trixie packages** sets `WEBKIT_WEBDRIVER=disabled`, and `debian/rules` passes `-Dwebkit_webdriver=disabled`. The job also deletes `libwebkitgtk-6.0-webdriver-dev` from the control files so `dpkg-checkbuilddeps` passes. `config/meson.build` then links stock `webkitgtk-6.0`.

## Root cause

- ✔️ The WebDriver `.so` has to be built against the JavaScriptCore in the same distro. An Ubuntu build does not match Trixie's JavaScriptCore, so the Trixie package cannot download an Ubuntu `.deb` and link it.

## Proposed fix

- 🔷 Build WebDriver on Debian 13 in [webkitgtk-automation](https://github.com/roojs/webkitgtk-automation). Publish `libwebkitgtk-6.0-webdriver4` and `libwebkitgtk-6.0-webdriver-dev` on a GitHub release.
- 💩 After those assets exist, the Trixie job downloads both `.deb` files from that release and `apt-get install`s them. Remove `WEBKIT_WEBDRIVER=disabled` and the control-file delete.
- 🚫 Keep `-Dwebkit_webdriver=disabled` once the Debian debs exist.
- 🚫 Install the Ubuntu 25.04, 25.10, or 26.04 WebDriver `.so` into the Trixie root.

## Attempts / changelog

- ✔️ Tried the Ubuntu 25.04 GitHub/roojs debs. Link failed on `WTF` / `JSC` symbols.
- ✔️ Held the Trixie job on stock WebKit so the Ubuntu 26.04 package job still uploads.

## Next

- ⏳ 🔷 Build and publish the Debian 13 WebDriver packages.
- ⏳ 💩 Point the Trixie job at those release assets and turn the WebDriver link back on.
