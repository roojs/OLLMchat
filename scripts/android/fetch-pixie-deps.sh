#!/usr/bin/env bash
# Download the published Android libraries and activate them for Pixiewood.
# The GTK stack comes from the pixiewood-pkgs GitHub Pages pin lists.
# android/pixie-gtk.pins replaces the gtk line with the IME package from Knowles/gtk.
# webkitgtk-android is not in that set. Its pin list is appended from
# https://roojs.github.io/webkitgtk-android/release.pins.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIXIEWOOD_BASE="${OLLMCHAT_PIXIEWOOD:-$ROOT_DIR/.pixiewood}"
DEST="${PIXIEWOOD_PIXIE:-$PIXIEWOOD_BASE/pixie}"
CLONE="$PIXIEWOOD_BASE/pixie-pkg"
RELEASE_URL="${PIXIE_RELEASE_PINS_URL:-https://roojs.github.io/pixiewood-pkgs/release.pins}"
SNAPSHOT_URL="${PIXIE_SNAPSHOT_PINS_URL:-https://roojs.github.io/pixiewood-pkgs/snapshot.pins}"
WEBKIT_URL="${PIXIE_WEBKIT_PINS_URL:-https://roojs.github.io/webkitgtk-android/release.pins}"
OVERRIDE="$ROOT_DIR/android/pixie-gtk.pins"
WEBKIT_PC="$DEST/lib/arm64-v8a/pkgconfig/webkitgtk-android-1.pc"
WEBKIT_VAPI="$DEST/share/vala/vapi/webkitgtk-android-1.vapi"
WEBKIT_JAVA="$DEST/share/pixiewood/webkitgtk-android-java/org/roojs/webkitgtk/android/WebViewHost.java"

if [ -d "$DEST" ] && [ ! -f "$DEST/share/pixiewood/pixie.cross" ]; then
  rm -rf "$DEST"
fi

if [ -f "$DEST/share/pixiewood/pixie.cross" ] &&
   [ -f "$DEST/share/pixiewood/gtk-android-java/org/gtk/android/ImContext.java" ] &&
   [ -f "$WEBKIT_PC" ] &&
   [ -f "$WEBKIT_VAPI" ] &&
   [ -f "$WEBKIT_JAVA" ] &&
   [ "${PIXIEWOOD_REFRESH_SUBPROJECTS:-}" != 1 ]; then
  printf '%s\n' "$DEST"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "fetch-pixie-deps needs jq" >&2
  exit 1
fi
if [ ! -f "$OVERRIDE" ]; then
  echo "GTK pixie pin missing: $OVERRIDE" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL --retry 3 --retry-delay 2 "$RELEASE_URL" -o "$work/release.pins"
curl -fsSL --retry 3 --retry-delay 2 "$SNAPSHOT_URL" -o "$work/snapshot.pins"
curl -fsSL --retry 3 --retry-delay 2 "$WEBKIT_URL" -o "$work/webkit.pins"
jq -s '
  .[0].packages as $rel
  | .[1].packages as $snap
  | .[2].packages as $over
  | .[3].packages as $extra
  | ($rel + [ $snap[] | select(.name as $n | [$rel[].name] | index($n) | not) ]) as $base
  | [
      $base[]
      | . as $row
      | ([$over[] | select(.name == $row.name)] | .[0]) // $row
    ] as $merged
  | {
      packages: (
        $merged + [
          $extra[]
          | select(.name as $n | [$merged[].name] | index($n) | not)
        ]
      )
    }
' "$work/release.pins" "$work/snapshot.pins" "$OVERRIDE" "$work/webkit.pins" > "$work/merged.pins"
if ! jq -e '[.packages[] | select(.name == "webkitgtk-android")] | length > 0' "$work/merged.pins" >/dev/null; then
  echo "webkitgtk-android is missing from $WEBKIT_URL" >&2
  exit 1
fi
# pixie-pkg fetch refuses a destination that already has files. An older
# sysroot has GTK and not webkitgtk-android, so replace the whole tree
# only after the pin list is known to include that package.
if [ -d "$DEST" ]; then
  rm -rf "$DEST"
fi

if [ ! -x "$CLONE/scripts/pixie-pkg" ]; then
  rm -rf "$CLONE"
  git clone --depth 1 https://github.com/roojs/pixie-pkg.git "$CLONE"
fi

mkdir -p "$(dirname "$DEST")"
"$CLONE/scripts/pixie-pkg" fetch --dest "$DEST" --pins "$work/merged.pins" --abi arm64-v8a >&2
if [ ! -f "$DEST/share/pixiewood/pixie.cross" ]; then
  echo "Pixie sysroot was not activated: $DEST" >&2
  exit 1
fi
if [ ! -f "$DEST/share/pixiewood/gtk-android-java/org/gtk/android/ImContext.java" ]; then
  echo "Pixie GTK is missing the IME Java glue: $DEST" >&2
  exit 1
fi
if [ ! -f "$WEBKIT_PC" ] || [ ! -f "$WEBKIT_VAPI" ] || [ ! -f "$WEBKIT_JAVA" ]; then
  echo "Pixie webkitgtk-android is missing the library, VAPI, or Java glue: $DEST" >&2
  exit 1
fi
printf '%s\n' "$DEST"
