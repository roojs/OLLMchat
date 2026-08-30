#!/usr/bin/env bash
# Build ollmchat RPMs from the repository checkout (Fedora 44 / openSUSE).
# Usage: scripts/ci/build-rpm.sh [version]
# Version defaults to CHANGELOG.md (packaging-version), or GITHUB_REF_NAME
# with leading v stripped on a tag.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
chmod +x "$ROOT/scripts/release/changelog.sh"

if [ "$#" -ge 1 ] && [ -n "$1" ]; then
  ver="$1"
elif [ -n "${GITHUB_REF_NAME:-}" ] && [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  ver="${GITHUB_REF_NAME#v}"
  cl_ver="$("$ROOT/scripts/release/changelog.sh" version)"
  if [ "$cl_ver" != "$ver" ]; then
    echo "CHANGELOG.md version ${cl_ver} != tag ${ver}" >&2
    exit 1
  fi
else
  ver="$("$ROOT/scripts/release/changelog.sh" packaging-version)"
fi
if [ -z "$ver" ]; then
  echo "Could not determine package version" >&2
  exit 1
fi

rpm_ver="${ver//-/\~}"
echo "Building ollmchat RPM version ${ver} (RPM ${rpm_ver})"

run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

. /etc/os-release

install_roojs_fedora_repo() {
  run_root install -d -m 0755 /etc/pki/rpm-gpg
  run_root curl -fsSL https://roojs.github.io/repos/key.gpg \
    -o /etc/pki/rpm-gpg/RPM-GPG-KEY-roojs
  run_root rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-roojs
  run_root curl -fsSL https://roojs.github.io/repos/repo \
    -o /etc/yum.repos.d/roojs.repo
  run_root sed -i \
    's|^gpgkey=.*|gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-roojs|' \
    /etc/yum.repos.d/roojs.repo
}

pkgconfig_deps=(
  'pkgconfig(gee-0.8)'
  'pkgconfig(glib-2.0)'
  'pkgconfig(json-glib-1.0)'
  'pkgconfig(libsoup-3.0)'
  'pkgconfig(libxml-2.0)'
  'pkgconfig(sqlite3)'
  'pkgconfig(gtk4)'
  'pkgconfig(gtksourceview-5)'
  'pkgconfig(libadwaita-1)'
  'pkgconfig(libsecret-1)'
  'pkgconfig(webkitgtk-6.0)'
  'pkgconfig(atspi-2)'
  'pkgconfig(tree-sitter)'
  'pkgconfig(libseccomp)'
  'pkgconfig(libgit2-glib-1.0)'
  'pkgconfig(lapack)'
  'pkgconfig(llama)'
)

case "${ID}" in
  fedora)
    install_roojs_fedora_repo
    pkgconfig_deps+=('pkgconfig(flexiblas)')
    run_root dnf -y install --setopt=install_weak_deps=False \
      rpm-build rpmdevtools \
      meson ninja-build gcc gcc-c++ vala desktop-file-utils \
      gobject-introspection gobject-introspection-devel \
      faiss-devel bubblewrap \
      "${pkgconfig_deps[@]}"
    rpm_dist_args=()
    ;;
  opensuse* | opensuse-tumbleweed | slfo)
    # desktop-file-utils needs gawk; Tumbleweed images ship busybox-gawk.
    # --force-resolution is an install option, not a global zypper flag.
    run_root zypper --non-interactive install --force-resolution \
      --no-recommends gawk
    pkgconfig_deps+=('pkgconfig(openblas)')
    # ggml-devel / llamacpp-devel ship dangling .so → .so.0 symlinks;
    # the real libs are in libllama0 / libggml0 / libggml-base0.
    run_root zypper --non-interactive install --force-resolution \
      --no-recommends \
      rpm-build rpmdevtools \
      meson ninja gcc gcc-c++ vala desktop-file-utils \
      gobject-introspection gobject-introspection-devel \
      faiss-devel bubblewrap ggml-devel \
      libllama0 libggml0 libggml-base0 \
      "${pkgconfig_deps[@]}"
    # Repos publish openSUSE packages under rpm/tumbleweed/; omit %{dist}
    # so the filename has no .fc tag (see scripts/fetch-upstream.sh).
    rpm_dist_args=(--define 'dist %{nil}')
    ;;
  *)
    echo "Unsupported distro for RPM build: ${ID}" >&2
    exit 1
    ;;
esac

TOPDIR="${ROOT}/.rpmbuild"
rm -rf "$TOPDIR"
mkdir -p "$TOPDIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

tar --exclude='./.git' \
  --exclude='./.rpmbuild' \
  --exclude='./.sqgipkg' \
  --exclude='./.ci-cache' \
  --exclude='./build' \
  --exclude='./build-*' \
  --exclude='./dist-*' \
  --exclude='./artifacts' \
  --exclude='./android' \
  --transform "s|^\\./|ollmchat-${rpm_ver}/|" \
  -czf "${TOPDIR}/SOURCES/ollmchat-${rpm_ver}.tar.gz" \
  .

build_one() {
  local extra_args=("$@")
  cp packaging/rpm/ollmchat.spec "${TOPDIR}/SPECS/ollmchat.spec"
  "$ROOT/scripts/release/changelog.sh" sync \
    --splice-spec "${TOPDIR}/SPECS/ollmchat.spec"

  rpmbuild -bb \
    --define "_topdir ${TOPDIR}" \
    --define "ollmchat_version ${rpm_ver}" \
    "${rpm_dist_args[@]}" \
    "${extra_args[@]}" \
    "${TOPDIR}/SPECS/ollmchat.spec"
}

build_one
rm -rf "${TOPDIR}/BUILD" "${TOPDIR}/BUILDROOT"
build_one --without local_gguf

mkdir -p "${ROOT}/artifacts"
find "${TOPDIR}/RPMS" -type f -name '*.rpm' ! -name '*.src.rpm' \
  ! -name '*debuginfo*' ! -name '*debugsource*' \
  -exec cp -v {} "${ROOT}/artifacts/" \;
ls -lh "${ROOT}/artifacts"
