#!/usr/bin/env bash
# R05 — Root meson wraps redirect into gtk/subprojects/*; GTK must exist before setup.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

REDIRECT="$ROOT_DIR/subprojects/graphene.wrap"
[ -f "$REDIRECT" ] || cp "$ROOT_DIR/android/pixiewood-wraps/gtk/gtk.wrap" "$ROOT_DIR/subprojects/" 2>/dev/null || true
for wrap in "$ROOT_DIR/android/pixiewood-wraps"/*/*.wrap; do
  [ -f "$wrap" ] && cp -a "$wrap" "$ROOT_DIR/subprojects/"
done

grep -q 'gtk/subprojects/graphene.wrap' "$ROOT_DIR/subprojects/graphene.wrap" ||
  { echo "unexpected graphene.wrap format" >&2; exit 1; }

rm -rf "$ROOT_DIR/subprojects/gtk"

if meson subprojects download --sourcedir "$ROOT_DIR" >/dev/null 2>&1; then
  echo "meson subprojects download should fail when gtk/ is missing" >&2
  exit 1
fi

prepare_android_subprojects_before_meson
[ -f "$ROOT_DIR/subprojects/gtk/subprojects/graphene.wrap" ] ||
  { echo "GTK nested graphene.wrap still missing after bootstrap" >&2; exit 1; }

echo "R05 wrap-redirects-need-gtk: OK"
