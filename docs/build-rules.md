# Build Instructions

Canonical build workflow for this project. Written for **AI agents** — **mandatory** for agents building or changing the project. Human contributors may treat this as a helpful guide. See also **`docs/coding-standards.md`**. Humans installing dependencies and running Meson for the first time should start at **[`docs/BUILD.md`](BUILD.md)**.

## Building the Project

**IMPORTANT:** Always use `ninja -C build` to build this project. Do NOT use `valac` directly - the build system handles all compilation through Meson/Ninja.

### Standard Build

Plain `meson setup build` builds the RPC client stack, **`ollmfilesd`**, and the GTK app.

```bash
ninja -C build
```

Wrapper scripts in the build directory (e.g. `build/ollmchat.bin`) set `LD_LIBRARY_PATH` and `OLLM_OLLMFILESD` to the build-tree daemon.

### Rebuilding After Changes

If the build system doesn't detect file changes, reconfigure and rebuild:
```bash
meson setup --reconfigure build
ninja -C build
```

### Initial Setup
```bash
meson setup build --prefix=/usr
ninja -C build
```

## Notes
- The build system uses Meson and Ninja
- All Vala files are compiled through the Meson build system
- Never call `valac` directly - always use `ninja -C build`

## Debian packages

A `.deb` for a suite is built on that suite. `dpkg-shlibdeps` records the libraries it linked, and that line is what apt will require.

This host is Ubuntu 25.04. Its apt sources stay Ubuntu. A Trixie package is built inside Debian 13.

### GitHub

Four jobs. LXC is not used on GitHub. Each suite is built on that suite. Trixie is `continue-on-error`. Its failure does not drop the Ubuntu artifacts.

- **Plucky packages:** `container: ubuntu:25.04`, `ROOJS_APT_SUITE=plucky`, `libgirepository1.0-dev`. Plucky girepository 2.0 is 2.84.1, so the Meson probe `girepository-2.0 >= 2.86` fails and `libocrpc` links `libgirepository-1.0`. Versions end in `+plucky`. Artifact `ollmchat-debian-plucky`.
- **Questing packages:** `container: ubuntu:25.10`, `ROOJS_APT_SUITE=questing`, `libgirepository-2.0-dev`, `pkg-config --atleast-version=2.86 girepository-2.0`. Versions end in `+questing`. Artifact `ollmchat-debian-questing`.
- **Resolute packages:** `container: ubuntu:26.04`, `ROOJS_APT_SUITE=resolute`, `libgirepository-2.0-dev`, same `>= 2.86` gate. Plain revision (`1.4.6-1`). That binary calls `gi_repository_dup_default()`. Artifact `ollmchat-debian`.
- **Trixie packages:** `container: debian:trixie`, `libgirepository1.0-dev`. The Meson probe fails on 2.84.4, so `libocrpc` links `libgirepository-1.0`. Versions end in `+trixie` (`libocrpc1_1.4.6-1+trixie_amd64.deb`). Artifact `ollmchat-debian-trixie`. The icon theme is the Ubuntu `humanity-icon-theme` all.deb. The roojs trixie suite has no `libwebkitgtk-6.0-webdriver-dev`, and an Ubuntu WebDriver `.so` does not link against Trixie JavaScriptCore. Until a Debian build is published (`docs/bugs/2026-11-06-trixie-webkit-webdriver.md`), the job sets `WEBKIT_WEBDRIVER=disabled` and drops that build dependency, so Trixie links stock `webkitgtk-6.0`.

The repos ingest puts a `+<codename>` file in that suite only, and keeps the plain revision off suites that have their own build. There is no roojs suite for Ubuntu 26.10 (`stonking`).

### This machine

System container `lxc-reference-trixie` (`/var/lib/lxc/lxc-reference-trixie`). Build with `lxc-attach`. Chroot the container rootfs only when the container cannot be started.

```bash
sudo lxc-start -n lxc-reference-trixie
sudo lxc-attach -n lxc-reference-trixie -- bash -lc 'cat /etc/os-release'
```

Bind-mount the git tree into the container rootfs, then attach:

```bash
rootfs=$(sudo lxc-info -n lxc-reference-trixie -c lxc.rootfs.path -H)
rootfs=${rootfs#dir:}
sudo mkdir -p "$rootfs/tmp/ollmchat-src"
sudo mountpoint -q "$rootfs/tmp/ollmchat-src" || sudo mount --bind "$PWD" "$rootfs/tmp/ollmchat-src"
sudo lxc-attach -n lxc-reference-trixie -- bash -lc '
  set -euo pipefail
  cd /tmp/ollmchat-src
  export DEBIAN_FRONTEND=noninteractive ROOJS_APT_SUITE=trixie
  ./scripts/ci/enable-roojs-apt.sh
  apt-get install -y --no-install-recommends \
    build-essential devscripts debhelper meson ninja-build pkg-config valac \
    gobject-introspection libgirepository1.0-dev \
    libglib2.0-dev libgee-0.8-dev libjson-glib-dev libsoup-3.0-dev \
    libgnutls28-dev libxml2-dev libsqlite3-dev libgtk-4-dev \
    libgtksourceview-5-dev libadwaita-1-dev libsecret-1-dev humanity-icon-theme \
    libwebkitgtk-6.0-dev libwebkitgtk-6.0-webdriver-dev libatspi2.0-dev \
    libavahi-gobject-dev libtree-sitter-dev libseccomp-dev libgit2-glib-1.0-dev \
    libopenblas-dev liblapack-dev libfaiss-dev libllama-dev
  sed -i "1s/(\([^)]*\))/(\1+trixie)/" debian/changelog
  dpkg-buildpackage -us -uc -b
'
```

`/etc/os-release` inside the attach must say Debian 13 (`trixie`) before `dpkg-buildpackage` runs. The `.deb` files land in the parent of the bind mount, on the host.
