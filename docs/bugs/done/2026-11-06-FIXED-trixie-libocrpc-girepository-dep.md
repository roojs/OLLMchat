# Trixie cannot install libocrpc1: girepository 2.0 >= 2.85.1

**Status:** ✅ 2026-11-07. User closed it. Trixie `libocrpc1` is `1.4.6-1+trixie` and depends on `libgirepository-1.0-1`. WebDriver is [`2026-11-06-CLOSED-trixie-webkit-webdriver.md`](2026-11-06-CLOSED-trixie-webkit-webdriver.md).

## Problem

- 🔷 On Debian 13 (trixie), `libocrpc1` will not install.
- 🔷 The package depends on `libgirepository-2.0-0` greater than 2.85.1.
- 🔷 Trixie only has 2.84.4-3.

## Evidence

- ✔️ Published Trixie index `libocrpc1` 1.4.3-1 (`pool/main/o/ollmchat/libocrpc1_1.4.3-1_amd64.deb`, SHA256 `0295ebe79812ce4ebbc9b6abc33cb571e4535eee634483a397ecf6ee66462b6c`):

```text
Depends: libavahi-gobject0 (>= 0.6.22), libc6 (>= 2.27), libffi8 (>= 3.4), libgee-0.8-2 (>= 0.14.0), libgirepository-2.0-0 (>= 2.85.1), libglib2.0-0t64 (>= 2.76.0), libgnutls30t64 (>= 3.7.2), libjson-glib-1.0-0 (>= 1.5.2), libsoup-3.0-0 (>= 3.1.1)
```

- ✔️ The same filename and SHA256 are in plucky, questing, and resolute.
- ✔️ Debian trixie `glib2.0` is 2.84.4-3~deb13u2. That is the 2.84.4-3 the archive can offer. It does not export `gi_repository_dup_default`.
- ℹ️ `gi_repository_dup_default` is `GI_AVAILABLE_IN_2_86`. GJS 1.85.2 started requiring GLib 2.85.1 for that symbol. `dpkg-shlibdeps` records `(>= 2.85.1)` from the Ubuntu 26.04 link.
- ℹ️ Trixie GJS is 1.82.3-1 and depends on `libgirepository-1.0-1`. Trixie GNOME Shell is 48.7. It does not link `libgirepository-2.0`.
- ℹ️ The later Shell is 49+. Debian forky ships Shell 50.5 with GJS 1.87.2 and glib 2.87. GJS 1.85.2 is where Shell moved onto girepository 2.0, and that GJS requires GLib >= 2.85.1. Trixie's `libgirepository-2.0-0` 2.84.4 cannot satisfy that.
- 🔷 `libocrpc` matches the Shell it is loaded into. Stock Trixie Shell 48 stays on girepository 1.0. The later Shell gets the 2.0 build on a suite that has GLib >= 2.86.
- ℹ️ `.github/workflows/x-debian.yml` builds one `.deb` set on `ubuntu:26.04` and gates `pkg-config --atleast-version=2.86 girepository-2.0`. `libocrpc/meson.build` selects 2.0 only when `girepository-2.0 >= 2.86`, then `Gi2.vala` calls `GI.Repository.dup_default()`.
- ℹ️ Questing and resolute ship GLib >= 2.86 and GJS on girepository 2.0. That binary is the one those suites need. Plucky is the same GLib 2.84 / GJS 1.0 generation as trixie.

## Root cause

- ✔️ One binary is published into every suite. It was linked on Resolute against `gi_repository_dup_default`, so the shlib dependency is `libgirepository-2.0-0 (>= 2.85.1)`. Trixie cannot satisfy that, and its GJS still loads girepository 1.0.

## Proposed fix

- 💩 Build two `.deb` sets. Do not lower the Depends line on the Resolute binary. That symbol is absent from 2.84, so the library would fail to load.
- 💩 Trixie: build on `debian:trixie`. Install `libgirepository1.0-dev`. Leave the Meson `>= 2.86` probe in place so 2.84 is rejected and the link stays `libgirepository-1.0`.
- 🚫 Plucky installs that same Trixie binary. `+trixie` is the Debian suite only, and that build has WebDriver disabled. Plucky needs its own Ubuntu build ([`2026-11-07-FIXED-ubuntu-one-deb-every-suite.md`](2026-11-07-FIXED-ubuntu-one-deb-every-suite.md)).
- 🚫 Questing and resolute share the `ubuntu:26.04` build. Questing libc is 2.42 and its WebDriver is `2.52.3`. The Resolute binary requires `libc6 (>= 2.43)` and WebDriver `2.52.6`.
- 🔷 Trixie filenames use the suite codename: version `1.4.3-1+trixie`, file `libocrpc1_1.4.3-1+trixie_amd64.deb`. The Ubuntu 26.04 job keeps the plain revision. No `26.04` or `26.10` in the name.
- 🚫 Do not switch `Gi2.vala` to `gi_repository_new()` to drop the version. Resolute GJS needs the process singleton from `dup_default`. A 2.0-linked library still cannot sit in a Trixie process whose GJS loaded girepository 1.0.
- 🚫 🔷 Point the Ubuntu host apt sources at Debian Trixie and upgrade the host. This machine stays on Ubuntu 25.04. Trixie is glib 2.84, the same generation as plucky, so that upgrade does not provide `libgirepository-2.0-0 (>= 2.85.1)` and it is not a Debian build root.
- 🔷 Trixie packages are built inside Debian 13. GitHub uses `container: debian:trixie`. This machine uses `lxc-attach -n lxc-reference-trixie`. Rule: `docs/build-rules.md` section Debian packages.

## Attempts / changelog

- ✔️ Read the four suite indexes and the Debian glib / GJS package facts.
- ✔️ Release `v1.4.6` run `42185644147`: job `Debian / Trixie packages` failed in apt. `humanity-icon-theme` is not in Debian. `libwebkitgtk-6.0-webdriver-dev` is not in the roojs trixie suite (`E: Package has no installation candidate`). The matrix had split that job away from the Ubuntu 26.04 package build.
- ✔️ One **Debian packages** job ran `scripts/ci/build-debian-packages.sh` in `ubuntu:26.04`, then in `debian:trixie`, and the collect step required both. Release `v1.4.6` run `42186821962` linked the Ubuntu 25.04 WebDriver library into the Trixie root. `libwebkitgtk-6.0-webdriver.so.4` has undefined `WTF` / `JSC` references against Trixie's JavaScriptCore. The Ubuntu `.deb` files were already built and were not uploaded.
- ✔️ That combined job replaced the `ubuntu:26.04` container job. The container job is restored as **Debian packages** (plain revision, artifact `ollmchat-debian`). **Trixie packages** is a second job (`continue-on-error`).
- ✔️ Release `v1.4.6` run `42189995538`: **Trixie packages** failed at apt with `libwebkitgtk-6.0-webdriver-dev` has no installation candidate. The job now sets `WEBKIT_WEBDRIVER=disabled` and drops that build dependency. Trixie links stock `webkitgtk-6.0`.
- ✅ 2026-11-07. User closed the girepository split. WebDriver is closed in [`2026-11-06-CLOSED-trixie-webkit-webdriver.md`](2026-11-06-CLOSED-trixie-webkit-webdriver.md).

## Next

- ✅ Closed. Repos ingest `a9a6a19` files `+trixie` into trixie only. The published trixie index is `1.4.6-1+trixie` (`libgirepository-1.0-1`). The Ubuntu suites are [`2026-11-07-FIXED-ubuntu-one-deb-every-suite.md`](2026-11-07-FIXED-ubuntu-one-deb-every-suite.md).
