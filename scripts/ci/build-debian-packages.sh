#!/usr/bin/env bash
# Build the split .debs and the remote-only .deb in the current distro.
# Release runs this twice, inside ubuntu:26.04 and debian:trixie.
# Caller exports ROOJS_APT_SUITE, OLL_GIR_DEV, and optionally
# OLL_GIR_GATE=1 and OLL_VERSION_SUFFIX=+trixie.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

: "${ROOJS_APT_SUITE:?ROOJS_APT_SUITE is required}"
: "${OLL_GIR_DEV:?OLL_GIR_DEV is required}"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends git ca-certificates curl

chmod +x scripts/ci/enable-roojs-apt.sh \
  scripts/release/changelog.sh \
  scripts/release/sync-debian-changelog.sh
./scripts/ci/enable-roojs-apt.sh

apt-get install -y --no-install-recommends \
  build-essential cmake ninja-build pkg-config file \
  meson valac gobject-introspection devscripts debhelper \
  libglib2.0-dev "${OLL_GIR_DEV}" libffi-dev libcairo2-dev \
  libgee-0.8-dev libjson-glib-dev libsoup-3.0-dev libgnutls28-dev libxml2-dev \
  libsqlite3-dev libgtk-4-dev libgtksourceview-5-dev libadwaita-1-dev libsecret-1-dev \
  libwebkitgtk-6.0-dev libatspi2.0-dev \
  libtree-sitter-dev libseccomp-dev libgit2-glib-1.0-dev libavahi-gobject-dev \
  libopenblas-dev liblapack-dev libfaiss-dev libllama-dev

if [[ "$ROOJS_APT_SUITE" == "trixie" ]]; then
  # humanity-icon-theme is not in Debian. The icon payload is arch-independent.
  apt-get install -y --no-install-recommends hicolor-icon-theme
  curl -fsSL -o /tmp/humanity-icon-theme.deb \
    http://archive.ubuntu.com/ubuntu/pool/universe/h/humanity-icon-theme/humanity-icon-theme_0.6.16build1_all.deb
  apt-get install -y /tmp/humanity-icon-theme.deb

  # The roojs trixie suite has no WebDriver build. The Ubuntu 25.04 build is
  # the glib 2.84 / ICU 76 generation. It needs libjpeg.so.8, which Trixie
  # does not ship (Trixie has libjpeg.so.62).
  printf 'deb [trusted=yes] http://archive.ubuntu.com/ubuntu plucky main\n' \
    > /etc/apt/sources.list.d/ubuntu-libjpeg.list
  cat > /etc/apt/preferences.d/ubuntu-libjpeg <<'EOF'
Package: libjpeg8 libjpeg-turbo8
Pin: origin archive.ubuntu.com
Pin-Priority: 500

Package: *
Pin: origin archive.ubuntu.com
Pin-Priority: 1
EOF
  apt-get update
  apt-get install -y libjpeg8
  curl -fsSL -o /tmp/libwebkitgtk-6.0-webdriver4.deb \
    https://roojs.github.io/repos/pool/main/w/webkit2gtk/libwebkitgtk-6.0-webdriver4_2.50.4-0ubuntu0.25.04.1+webdriver6_amd64.deb
  curl -fsSL -o /tmp/libwebkitgtk-6.0-webdriver-dev.deb \
    https://roojs.github.io/repos/pool/main/w/webkit2gtk/libwebkitgtk-6.0-webdriver-dev_2.50.4-0ubuntu0.25.04.1+webdriver6_amd64.deb
  apt-get install -y /tmp/libwebkitgtk-6.0-webdriver4.deb /tmp/libwebkitgtk-6.0-webdriver-dev.deb
else
  apt-get install -y --no-install-recommends \
    humanity-icon-theme \
    libwebkitgtk-6.0-webdriver-dev
fi

if [[ "${OLL_GIR_GATE:-0}" == "1" ]]; then
  pkg-config --atleast-version=2.86 girepository-2.0
fi

if [[ "${GITHUB_REF:-}" == refs/tags/* ]]; then
  if cl_ver="$(./scripts/release/changelog.sh version 2>/dev/null)"; then
    tag_ver="${GITHUB_REF_NAME#v}"
    if [[ "${cl_ver}" != "${tag_ver}" ]]; then
      echo "CHANGELOG.md version ${cl_ver} != tag ${tag_ver}" >&2
      exit 1
    fi
    ./scripts/release/sync-debian-changelog.sh
  else
    ./scripts/release/sync-debian-changelog.sh --release "$GITHUB_REF_NAME"
  fi
else
  ./scripts/release/sync-debian-changelog.sh
fi

suffix="${OLL_VERSION_SUFFIX:-}"
if [[ -n "$suffix" ]]; then
  sed -i "1s/(\([^)]*\))/(\1${suffix})/" debian/changelog
fi
head -n 1 debian/changelog

rm -rf build
export DEBFULLNAME="${DEBFULLNAME:-GitHub Actions}"
export DEBEMAIL="${DEBEMAIL:-actions@users.noreply.github.com}"
./debian/use-split-packages.sh
dpkg-buildpackage -us -uc -b
rm -rf build
./debian/use-monolithic-remote-only-package.sh
dpkg-buildpackage -us -uc -b
./debian/use-split-packages.sh
