#!/usr/bin/env bash
# R19 — Android custom_target vapi generation uses host valac. A laptop with
# libgee-0.8-dev finds gee-0.8 in /usr/share/vala/vapi; CI does not install
# that package. library() gets the subproject vapi from dependency('gee-0.8');
# custom_target does not. Every Android meson.build that passes --pkg gee-0.8
# to a custom_target must also pass --vapidir gee_vapi_dir (CI 32568270350).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

files=(
  "$ROOT_DIR/libocmarkdown/meson.build"
  "$ROOT_DIR/libocmarkdowngtk/meson.build"
  "$ROOT_DIR/libocsqlite/meson.build"
  "$ROOT_DIR/libocrpc/meson.build"
  "$ROOT_DIR/libollamaweb/meson.build"
  "$ROOT_DIR/libocwebkit/meson.build"
  "$ROOT_DIR/liboccoder/meson.build"
)

fail=0
for f in "${files[@]}"; do
  [ -f "$f" ] || {
    echo "R19 missing $f" >&2
    exit 1
  }
  grep -qE -- "--pkg[', ]+gee-0.8" "$f" || continue
  grep -q 'gee_vapi_dir' "$f" || {
    echo "R19 $f uses --pkg gee-0.8 without gee_vapi_dir (host gee hides this locally)" >&2
    fail=1
  }
done

[ "$fail" -eq 0 ] || exit 1
echo "R19 android-custom-vapi-gee-vapidir: OK"
