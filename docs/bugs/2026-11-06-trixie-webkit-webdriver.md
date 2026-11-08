# Trixie has no WebDriver library built on Debian

**Status:** ⏳ Trixie job apt-installs `libwebkitgtk-6.0-webdriver-dev` from the roojs trixie suite. The next package build confirms the link.

## Problem

- 🔷 Debian 13 packages must link `libwebkitgtk-6.0-webdriver`, the same as the Ubuntu packages.
- 🔷 `libwebkitgtk-6.0-webdriver-dev` is not in the roojs trixie suite, and it is not a Debian package.
- 🔷 Disabling WebDriver for the Trixie job is a hold. It is not the package we ship.
- 🔷 The library has to be built on a Debian box, published, then downloaded from that GitHub release.

## Evidence

- ✔️ Release `v1.4.6` run `42189995538`, job **Trixie packages**: `E: Package 'libwebkitgtk-6.0-webdriver-dev' has no installation candidate`. Exit 100.
- ✔️ Release `v1.4.6` run `42186821962` installed the Ubuntu 25.04 debs (`2.50.4-0ubuntu0.25.04.1+webdriver6`) plus Ubuntu `libjpeg8`. The link failed. `libwebkitgtk-6.0-webdriver.so.4` has undefined references to `WTF::*`, `JSC::*`, `bmalloc::*`, and `Inspector::*`. Trixie's `libjavascriptcoregtk` does not provide those symbols.
- ℹ️ [webkitgtk-automation](https://github.com/roojs/webkitgtk-automation) release `webkit2gtk-2.54.0-1-deb13u3-webdriver1` (2026-11-07) is the Debian 13 build. Assets: `libwebkitgtk-6.0-webdriver4_2.54.0-1.deb13u3+webdriver1_amd64.deb` and `libwebkitgtk-6.0-webdriver-dev_2.54.0-1.deb13u3+webdriver1_amd64.deb`. Package version `2.54.0-1~deb13u3+webdriver1`. The `-dev` package depends on that runtime package, `libwebkitgtk-6.0-dev`, `libgtk-4-dev`, `libsoup-3.0-dev`, and `libjavascriptcoregtk-6.0-dev`.
- ℹ️ 2026-11-08 fetch of `dists/trixie/Release` (dated 2026-11-07 02:30 UTC) lists no `libwebkitgtk-6.0-webdriver` package. Plucky, questing, and resolute do. `roojs/repos` `config/repos.json` maps only the Ubuntu webdriver tags onto those three suites. The Debian tag `webkit2gtk-2.54.0-1-deb13u3-webdriver1` is not in that map.
- ℹ️ Ubuntu releases stay separate: 25.04 (`2.50.4`), 25.10 (`2.52.3`), 26.04 (`2.52.6`).
- ℹ️ Questing WebDriver depends on `libxml2-16` and a newer glibc than Trixie. Resolute depends on `libc6 >= 2.43` and `libicu78`. Those debs will not install on Debian 13.
- ℹ️ The hold was `.github/workflows/x-debian.yml` **Trixie packages**: `WEBKIT_WEBDRIVER=disabled`, and a delete of `libwebkitgtk-6.0-webdriver-dev` from the control files. That hold is removed. The job apt-installs `libwebkitgtk-6.0-webdriver-dev` after `scripts/ci/enable-roojs-apt.sh`, same as the Ubuntu jobs.

## Root cause

- ✔️ The WebDriver `.so` has to be built against the JavaScriptCore in the same distro. An Ubuntu build does not match Trixie's JavaScriptCore, so the Trixie package cannot download an Ubuntu `.deb` and link it.

## Proposed fix

- 🔷 Build WebDriver on Debian 13 in [webkitgtk-automation](https://github.com/roojs/webkitgtk-automation). Publish `libwebkitgtk-6.0-webdriver4` and `libwebkitgtk-6.0-webdriver-dev` on a GitHub release.
- 🔷 The Trixie job apt-installs `libwebkitgtk-6.0-webdriver-dev` from the roojs trixie suite. `WEBKIT_WEBDRIVER=disabled` and the control-file delete are gone.
- 🚫 Download the webkitgtk-automation release assets inside the OLLMchat job.
- 🚫 Keep `-Dwebkit_webdriver=disabled` once the Debian package is in the trixie suite.
- 🚫 Install the Ubuntu 25.04, 25.10, or 26.04 WebDriver `.so` into the Trixie root.

## Attempts / changelog

- ✔️ Tried the Ubuntu 25.04 GitHub/roojs debs. Link failed on `WTF` / `JSC` symbols.
- ✔️ Held the Trixie job on stock WebKit so the Ubuntu 26.04 package job still uploads.
- ✔️ `.github/workflows/x-debian.yml` **Trixie packages** apt-installs `libwebkitgtk-6.0-webdriver-dev`. The disable env, the control-file delete, and the GitHub asset download are gone.

## Next

- ⏳ ℹ️ The next Trixie package build is the check that `dpkg-buildpackage` links `webkitgtk-6.0-webdriver`.
