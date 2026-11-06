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

The Trixie job runs on `ubuntu-24.04` with `container: image: debian:trixie`. The runner can do that. LXC is not used on GitHub.

`ROOJS_APT_SUITE=trixie`. Install `libgirepository1.0-dev`. The Meson probe `girepository-2.0 >= 2.86` fails on Trixie (2.84.4), so `libocrpc` links `libgirepository-1.0`. That matches Trixie GNOME Shell 48 (GJS 1.82). Shell 49 and later (Debian forky ships Shell 50, GJS 1.87) load girepository 2.0 and need GLib >= 2.85.1, which Trixie does not have. `libocrpc` has to be the same major as the Shell in that process.

Questing and resolute stay on the Ubuntu 26.04 job (`ROOJS_APT_SUITE=resolute`, `libgirepository-2.0-dev`, `pkg-config --atleast-version=2.86 girepository-2.0`). That binary calls `gi_repository_dup_default()` and depends on `libgirepository-2.0-0 (>= 2.85.1)`.

Trixie package versions end in `+trixie`, so the file is `libocrpc1_1.4.3-1+trixie_amd64.deb`. The label is the suite codename. The Ubuntu 26.04 job keeps the plain revision (`1.4.3-1`) and is the questing / resolute binary. The repos ingest has to put `+trixie` files in the trixie suite only.

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
