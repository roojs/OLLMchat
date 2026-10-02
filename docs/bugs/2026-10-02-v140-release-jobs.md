# v1.4.0 release jobs failed

**Status:** ✔️ fixes applied locally — not committed; CI not re-run

**Related:**

- **ℹ️** [Release - v1.4.0](https://github.com/roojs/OLLMchat/actions/runs/36973997569) (`2a342b99`)
- **ℹ️** Valadoc on the parent push: [run 36957364323](https://github.com/roojs/OLLMchat/actions/runs/36957364323)

---

## Problem

- **🔷** Tag `v1.4.0` started Release. Debian, openSUSE, Android, Windows, and AppImage failed. Fedora was still running when this log was written.
- **🔷** Valadoc on `main` failed before the tag: `PairingDialog` is missing from the docs input list.

## Evidence

- **ℹ️** Debian job `110733770635`: `dpkg-checkbuilddeps: unmet build dependencies: libwebkitgtk-6.0-webdriver-dev`. `debian/control` already requires it. `.github/workflows/x-debian.yml` apt list did not install it. Roojs APT was enabled.
- **ℹ️** AppImage job `110733770558` on `ubuntu-24.04`: `No WebKitGTK with WebDriver interactions found`. sqgipkg meson uses the sysroot (`scripts/release/meson-sqgipkg-setup.sh`). `sqgipkg.json` downloaded stock `libwebkitgtk-6.0-dev` only. Ubuntu 24.04 is not a roojs suite, so `libwebkitgtk-6.0-webdriver-dev` cannot be installed there.
- **ℹ️** openSUSE job `110733770363`: `libocrpc/meson.build:52: Dependency "gnutls" not found`. Desktop `libocrpc` always depends on gnutls. The spec had no `pkgconfig(gnutls)`.
- **ℹ️** Android job `110733770548`, test `test-r02-gtk-bootstrap-restore.sh`: `mkdir …/.pixiewood: File exists`, then `cp` into `.pixiewood/gtk-subproject-bootstrap` failed. Commit `2a342b99` added git symlinks `.pixiewood` → `/storage/Downloads/OLLMchat-build/.pixiewood` (and retargeted `.android-sdk`, added `.android-tools`). `.gitignore` used `.pixiewood/`, which does not ignore a symlink. CI checkout is a broken symlink, so `mkdir -p` refuses it.
- **ℹ️** Windows job `110733770551`, webview2gtk **0.5.9**: `main_document_response` is not on `WebView2Gtk.WebView`. `navigator_webdriver_active_policy` is not on `WebView2Gtk.WebViewSettings`. v0.5.9 already has `decide_policy`. `navigator_webdriver_active_policy` is in **0.6.7** (asset `mingw-w64-ucrt-x86_64-webview2gtk-0.6.7-1-any.pkg.tar.zst`).
- **ℹ️** Valadoc: `ConnectionsPage.vala:56: The type name PairingDialog could not be found`. `ollmapp/SettingsDialog/PairingDialog.vala` was not in `docs/meson.build`.

## Root cause

- **✔️** Release packaging and CI file lists were not updated when WebKit WebDriver, GnuTLS, and the Windows WebView API became required. The release commit also checked in machine-local build-dir symlinks.

## Fix applied

- **✔️** `x-debian.yml` and `remote-only-build.yml` install `libwebkitgtk-6.0-webdriver-dev` (remote-only also enables roojs APT).
- **✔️** AppImage job uses `ubuntu:25.04` with `ROOJS_APT_SUITE=plucky`. x86_64 `sqgipkg.json` lists `libwebkitgtk-6.0-webdriver-dev`. aarch64 does not: roojs has no arm64 package. `scripts/release/meson-sqgipkg-setup.sh` passes `-Dwebkit_webdriver=disabled` when `SQGI_LINUX_TRIPLET` is `aarch64-*`, and Meson then links stock `webkitgtk-6.0`.
- **✔️** RPM install list in `scripts/ci/build-rpm.sh` includes `pkgconfig(gnutls)`. The spec `BuildRequires` line does not install the package; `zypper`/`dnf` only see `pkgconfig_deps`.
- **✔️** `.android-sdk`, `.android-tools`, and `.pixiewood` removed from the index. Working-tree symlinks kept. `.gitignore` matches the symlink names.
- **✔️** `Cloudflare.vala`: Android keeps `main_document_response`. Linux and Windows use `decide_policy`. Windows pin is webview2gtk **0.6.7**.
- **✔️** `docs/meson.build` lists `PairingDialog.vala` before `ConnectionsPage.vala`.

## Next

- **⏳** **💩** Not committed and not pushed. Re-tag or re-run Release only after that commit.
- **⏳** **ℹ️** Fedora 44 job `110733770535` is still on "Build RPMs" (started 06:32 UTC). GitHub does not publish that log until the job finishes. openSUSE already failed on missing gnutls; the spec change covers both.
- **✔️** Local: `ninja -C build libocwebkit/libocwebkit.so` linked. `ninja -C build docs/valadoc` ended `Succeeded - 445 warning(s)`. `scripts/android/regression/test-r02-gtk-bootstrap-restore.sh` printed `R02 gtk-bootstrap-restore: OK` (this machine's `.pixiewood` symlink target exists; CI's copy of the committed symlink does not).
- **ℹ️** `dpkg-checkbuilddeps` here still wants `libopenblas-dev` and `libllama-dev`. `libwebkitgtk-6.0-webdriver-dev` is already installed (`pkg-config` 2.50.4). No full `.deb`, RPM, AppImage, or Windows build on this machine.
