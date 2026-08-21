#!/usr/bin/env bash
# R15 — Local Android compile reused frozen wrap-git trees, so GitHub fetching
# `revision = main` (pango 1.58.2, libadwaita 1.10.rc) vs glib 2.84.0 was invisible.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

assert_pinned_wrap_git() {
  local wrap="$1" label="$2" rev
  [ -f "$wrap" ] || { echo "R15 missing wrap-git for $label: $wrap" >&2; exit 1; }
  if git -C "$ROOT_DIR" check-ignore -q "$wrap"; then
    echo "R15 $label wrap is gitignored (CI will not see it): $wrap" >&2
    exit 1
  fi
  grep -q '^\[wrap-git\]' "$wrap" ||
    { echo "R15 $label must be wrap-git: $wrap" >&2; exit 1; }
  rev="$(wrap_file_revision "$wrap")"
  case "$rev" in
    ''|main|master|HEAD)
      echo "R15 $label wrap-git tracks '$rev' — local checkouts hide Meson fetching today's tree vs glib 2.84.0" >&2
      exit 1
      ;;
  esac
}

assert_pinned_wrap_git \
  "$ROOT_DIR/android/pixiewood-wraps/glib/glib.wrap" glib
assert_pinned_wrap_git \
  "$ROOT_DIR/android/pixiewood-wraps/gtk/gtk.wrap" gtk
assert_pinned_wrap_git \
  "$ROOT_DIR/android/pixiewood-wraps/gtk/pango.wrap.pin" pango
assert_pinned_wrap_git \
  "$ROOT_DIR/android/pixiewood-wraps/libadwaita/libadwaita.wrap" libadwaita

mkdir -p "$ROOT_DIR/subprojects"
for dep_dir in "$ROOT_DIR/android/pixiewood-wraps"/*/; do
  for wrap in "$dep_dir"/*.wrap; do
    [ -f "$wrap" ] && cp -a "$wrap" "$ROOT_DIR/subprojects/"
  done
done

prepare_android_subprojects_before_meson
if glib_stack_wrap_git_is_floating; then
  echo "R15 glib/gtk/pango/libadwaita wrap-git still tracks main/master after overlay" >&2
  exit 1
fi

echo "R15 glib-stack-wrap-git-pinned: OK"
