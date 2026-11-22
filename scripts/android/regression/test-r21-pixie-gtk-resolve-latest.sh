#!/usr/bin/env bash
# R21: Knowles GTK pixie pin resolves latest generic package (url + sha256).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RESOLVE="$ROOT_DIR/scripts/android/resolve-pixie-gtk-pins.sh"
TEMPLATE="$ROOT_DIR/android/pixie-gtk.pins"

[ -x "$RESOLVE" ] || { echo "R21: missing $RESOLVE" >&2; exit 1; }
track="$(jq -r '.packages[0].track // empty' "$TEMPLATE")"
[ "$track" = latest ] || { echo "R21: pixie-gtk.pins track must be latest, got $track" >&2; exit 1; }

out="$("$RESOLVE")"
jq -e '
  .packages[0]
  | .name == "gtk"
  and (.url | test("packages/generic/gtk/"))
  and (.inputs | test("^[a-f0-9]{64}$"))
  and (.track | length > 0)
' <<<"$out" >/dev/null || { echo "R21: bad resolved gtk pin: $out" >&2; exit 1; }

echo "R21: pixie gtk latest resolve ok ($(jq -r '.packages[0].track' <<<"$out"))"