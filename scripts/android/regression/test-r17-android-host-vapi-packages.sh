#!/usr/bin/env bash
# R17 — Android valac --pkg=gtksourceview-5 uses the host vapi. gtk4.vapi
# ships with valac; gtksourceview-5.vapi does not. CI must install
# libgtksourceview-5-dev or "Build chat APK" dies after local compile
# succeeds (desktop machines already have that package).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/x-android.yml"
DOCS="$ROOT_DIR/docs/android-build.md"

need_pkg_in() {
  local file="$1" pkg="$2"
  grep -q "$pkg" "$file" || {
    echo "R17 missing $pkg in $file" >&2
    exit 1
  }
}

grep -q -- '--pkg=gtksourceview-5' "$ROOT_DIR/libocmarkdowngtk/meson.build" || {
  echo "R17 expected --pkg=gtksourceview-5 in libocmarkdowngtk/meson.build" >&2
  exit 1
}

need_pkg_in "$WORKFLOW" libgtksourceview-5-dev
need_pkg_in "$DOCS" libgtksourceview-5-dev
need_pkg_in "$WORKFLOW" libadwaita-1-dev
need_pkg_in "$WORKFLOW" libgtk-4-dev

echo "R17 android-host-vapi-packages: OK"
