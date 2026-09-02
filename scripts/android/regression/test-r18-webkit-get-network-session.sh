#!/usr/bin/env bash
# R18 — CI clones webkitgtk-android from the wrap pin, not the laptop
# subprojects/ tree. 31fd762d shipped get_network_session() only; OLLMchat
# uses WebView.network_session (WebKitGTK / webview2-gtk). Pin must be
# release tag v0.1.5 (network_session property; navigator_webdriver_active_policy).
# CI 32552806663 / 32567946821: restore-keys can leave the getter-only checkout;
# discard and clone the pin (same as R16 pango) so skip-download later does not
# keep the stale tree.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

WRAP="$ROOT_DIR/android/pixiewood-wraps/webkitgtk-android/webkitgtk-android.wrap"
BROWSER="$ROOT_DIR/libocwebkit/Browser.vala"
PIN_REV=v0.1.5
OLD_REV=31fd762d87f200f6a087f772681accc3cc58a11a
SRC="$ROOT_DIR/subprojects/webkitgtk-android/lib/webkitgtkandroid/WebView.vala"
CHECKOUT="$ROOT_DIR/subprojects/webkitgtk-android"

[ -f "$WRAP" ] || {
  echo "R18 missing $WRAP" >&2
  exit 1
}
[ -f "$BROWSER" ] || {
  echo "R18 missing $BROWSER" >&2
  exit 1
}

grep -qE "revision[[:space:]]*=[[:space:]]*$OLD_REV" "$WRAP" && {
  echo "R18 wrap still pins getter-only webkitgtk-android $OLD_REV" >&2
  exit 1
}
grep -qE "revision[[:space:]]*=[[:space:]]*$PIN_REV" "$WRAP" || {
  echo "R18 wrap must pin webkitgtk-android $PIN_REV (network_session property)" >&2
  exit 1
}

grep -q 'web_view.network_session' "$BROWSER" || {
  echo "R18 expected web_view.network_session in libocwebkit/Browser.vala" >&2
  exit 1
}
if grep -nE 'get_network_session\(\)' "$BROWSER"; then
  echo "R18 libocwebkit must use .network_session (webkitgtk-android $PIN_REV has the property)" >&2
  exit 1
fi

if [ -f "$SRC" ] && ! grep -q 'public NetworkSession network_session' "$SRC"; then
  echo "Discarding stale webkitgtk-android checkout (want $PIN_REV)." >&2
  rm -rf "$CHECKOUT"
fi

if [ ! -f "$SRC" ]; then
  ensure_git_checkout_at_revision \
    "$CHECKOUT" \
    "$(wrap_file_url "$WRAP")" \
    "$(wrap_file_revision "$WRAP")"
fi

[ -f "$SRC" ] || {
  echo "R18 missing $SRC after checkout of $PIN_REV" >&2
  exit 1
}
grep -q 'public NetworkSession network_session' "$SRC" || {
  echo "R18 $SRC still lacks network_session property after $PIN_REV checkout" >&2
  exit 1
}

echo "R18 webkit-network-session-property: OK"
