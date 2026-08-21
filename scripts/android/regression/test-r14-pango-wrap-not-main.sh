#!/usr/bin/env bash
# R14 — CI run 32241554256: pango.wrap revision=main fetched 1.58.2 (glib >= 2.88).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

PIN="$ROOT_DIR/android/pixiewood-wraps/gtk/pango.wrap.pin"
NESTED="$ROOT_DIR/subprojects/gtk/subprojects/pango.wrap"
PIN_REV=fa2ba89e7ed0907c8852add50cb13edefe93e66e

[ -f "$PIN" ] || { echo "missing pinned pango wrap: $PIN" >&2; exit 1; }
case "$PIN" in
  *.wrap)
    echo "pango pin must not be named *.wrap (copied into subprojects/; Meson duplicate pango)" >&2
    exit 1
    ;;
esac
if git -C "$ROOT_DIR" check-ignore -q "$PIN"; then
  echo "pinned pango wrap is gitignored (CI will not see it): $PIN" >&2
  exit 1
fi
grep -qE "revision[[:space:]]*=[[:space:]]*$PIN_REV" "$PIN" ||
  { echo "pinned pango.wrap must use $PIN_REV (glib 2.84.0)" >&2; exit 1; }
grep -qE 'revision[[:space:]]*=[[:space:]]*main' "$PIN" &&
  { echo "pinned pango.wrap must not track main" >&2; exit 1; }

for wrap in "$ROOT_DIR/android/pixiewood-wraps/"*/*.wrap; do
  [ -f "$wrap" ] || continue
  grep -q '^\[wrap-redirect\]' "$wrap" && continue
  if grep -qE '^pango[[:space:]]*=' "$wrap"; then
    echo "pixiewood-wraps must not ship a pango wrap-git: $wrap" >&2
    exit 1
  fi
done

mkdir -p "$ROOT_DIR/subprojects"
for dep_dir in "$ROOT_DIR/android/pixiewood-wraps"/*/; do
  for wrap in "$dep_dir"/*.wrap; do
    [ -f "$wrap" ] && cp -a "$wrap" "$ROOT_DIR/subprojects/"
  done
done

# CI run 32325671306: restored subprojects cache still had nested-pango.wrap.
cat > "$ROOT_DIR/subprojects/nested-pango.wrap" <<'EOF'
[wrap-git]
directory = pango
url = https://gitlab.gnome.org/GNOME/pango.git
revision = main
depth = 1

[provide]
pango = libpango_dep
EOF

prepare_android_subprojects_before_meson
[ -f "$ROOT_DIR/subprojects/nested-pango.wrap" ] &&
  { echo "prepare left extra top-level pango wrap-git" >&2; exit 1; }
[ -f "$NESTED" ] || { echo "GTK nested pango.wrap missing after prepare" >&2; exit 1; }
grep -qE "revision[[:space:]]*=[[:space:]]*$PIN_REV" "$NESTED" ||
  { echo "GTK nested pango.wrap was not pinned (still tracks main?)" >&2; exit 1; }
grep -qE 'revision[[:space:]]*=[[:space:]]*main' "$NESTED" &&
  { echo "GTK nested pango.wrap still tracks main" >&2; exit 1; }

# Bootstrap restore must re-apply the pin (cached GTK ships upstream revision=main).
rm -rf "$ROOT_DIR/subprojects/gtk"
mkdir -p "$ROOT_DIR/subprojects/gtk"
echo '# broken stub' > "$ROOT_DIR/subprojects/gtk/meson.build"
prepare_android_subprojects_before_meson
grep -qE "revision[[:space:]]*=[[:space:]]*$PIN_REV" "$NESTED" ||
  { echo "pango pin missing after GTK bootstrap restore" >&2; exit 1; }

echo "R14 pango-wrap-not-main: OK"
