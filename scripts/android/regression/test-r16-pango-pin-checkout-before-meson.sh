#!/usr/bin/env bash
# R16 — CI 32441247618 / 32441610454: discarded stale pango then Meson download
# died on wrap-redirect pango/subprojects/freetype2.wrap (tree was gone).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

PIN_REV=fa2ba89e7ed0907c8852add50cb13edefe93e66e
PANGO="$ROOT_DIR/subprojects/pango"

rm -rf "$PANGO"
ensure_pinned_wrap_git_checkouts
pango_checkout_matches_pin ||
  { echo "R16 pango checkout is not $PIN_REV after ensure" >&2; exit 1; }
[ -f "$PANGO/subprojects/freetype2.wrap" ] ||
  { echo "R16 pango pin tree missing subprojects/freetype2.wrap" >&2; exit 1; }

echo "R16 pango-pin-checkout-before-meson: OK"
