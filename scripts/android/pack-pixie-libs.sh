#!/usr/bin/env bash
# Pack each Android library this build installed into a .pixie file and
# write release.pins for that set. Publish uploads the .pixie files.
# release.pins is committed on main and published on GitHub Pages.
# It is not a release asset.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIXIEWOOD_BASE="${OLLMCHAT_PIXIEWOOD:-$ROOT_DIR/.pixiewood}"
BUILD_DIR="$PIXIEWOOD_BASE/bin-aarch64"
OUT="$ROOT_DIR/pixie-artifacts"
ABI=arm64-v8a
API=31
TOKEN='@PIXIEWOOD_SYSROOT@'

if [ ! -f "$BUILD_DIR/build.ninja" ]; then
  echo "Android build directory missing: $BUILD_DIR" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "pack-pixie-libs needs jq" >&2
  exit 1
fi

version="$(sed -n "s/.*version: '\\([0-9][0-9.]*\\)'.*/\\1/p" "$ROOT_DIR/meson.build" | head -n1)"
if [ -z "$version" ]; then
  echo "Could not read the version from meson.build" >&2
  exit 1
fi
tag="${PIXIE_RELEASE_TAG:-${GITHUB_REF_NAME:-}}"
if [ -z "$tag" ]; then
  tag="v$version"
fi
repo="${GITHUB_REPOSITORY:-roojs/OLLMchat}"
resolved="$(git -C "$ROOT_DIR" rev-parse HEAD)"

# Public pkg-config names for the Android build of each library.
requires_of() {
  case "$1" in
    ocsqlite) printf '%s\n' gee-0.8 gio-2.0 glib-2.0 gobject-2.0 sqlite3 ;;
    ocrpc) printf '%s\n' gee-0.8 gio-2.0 glib-2.0 gobject-2.0 gio-unix-2.0 gmodule-2.0 json-glib-1.0 libsoup-3.0 libffi openssl ;;
    ocmarkdown) printf '%s\n' gee-0.8 gio-2.0 glib-2.0 gobject-2.0 json-glib-1.0 libsoup-3.0 libxml-2.0 ;;
    ollamaweb) printf '%s\n' gee-0.8 gio-2.0 glib-2.0 gobject-2.0 json-glib-1.0 libsoup-3.0 libxml-2.0 ;;
    ochf) printf '%s\n' gee-0.8 gio-2.0 glib-2.0 gobject-2.0 json-glib-1.0 libsoup-3.0 ;;
    ocmarkdowngtk) printf '%s\n' gtk4 gtksourceview-5 gee-0.8 gio-2.0 glib-2.0 gobject-2.0 json-glib-1.0 libsoup-3.0 libxml-2.0 ocmarkdown ;;
    ocfiles) printf '%s\n' gee-0.8 gio-2.0 glib-2.0 gobject-2.0 json-glib-1.0 libsoup-3.0 sqlite3 ocrpc ocsqlite ;;
    ollmchat) printf '%s\n' gee-0.8 gio-2.0 glib-2.0 gobject-2.0 json-glib-1.0 libsoup-3.0 ocrpc ;;
    ocwebkit) printf '%s\n' gee-0.8 gio-2.0 glib-2.0 gobject-2.0 json-glib-1.0 gtk4 libsoup-3.0 webkitgtk-android-1 ollmchat ;;
    ocmcp) printf '%s\n' gee-0.8 gio-2.0 glib-2.0 gobject-2.0 gmodule-2.0 json-glib-1.0 libsoup-3.0 ;;
    octools) printf '%s\n' gee-0.8 gio-2.0 glib-2.0 gobject-2.0 json-glib-1.0 libsoup-3.0 ;;
    occoder) printf '%s\n' gtk4 libadwaita-1 gtksourceview-5 gee-0.8 gio-2.0 glib-2.0 gobject-2.0 json-glib-1.0 libsoup-3.0 sqlite3 ollmchat ;;
    ollmchatgtk) printf '%s\n' gtk4 libadwaita-1 gtksourceview-5 gee-0.8 gio-2.0 glib-2.0 gobject-2.0 json-glib-1.0 libsoup-3.0 sqlite3 ollmchat ocmarkdown ocmarkdowngtk ocsqlite ;;
    *) return 1 ;;
  esac
}

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
meson="$("$ROOT_DIR/scripts/android/ensure-meson.sh")"
"$meson" install -C "$BUILD_DIR" --destdir "$stage/all" --no-rebuild

libdir="$stage/all/lib/$ABI"
if [ ! -d "$libdir" ]; then
  echo "Installed Android libraries missing: $libdir" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
pins="$stage/packages.json"
printf '%s\n' '{"packages":[]}' > "$pins"

found=0
for name in ocsqlite ocrpc ocmarkdown ollamaweb ochf ocmarkdowngtk ocfiles ollmchat ocwebkit ocmcp octools occoder ollmchatgtk; do
  so="$(find "$libdir" -maxdepth 1 -name "lib${name}.so" -print -quit)"
  if [ -z "$so" ]; then
    continue
  fi
  one="$stage/one"
  rm -rf "$one"
  mkdir -p "$one/lib/$ABI/pkgconfig" "$one/include" "$one/share/vala/vapi"
  find "$libdir" -maxdepth 1 -name "lib${name}.so*" -exec cp -a {} "$one/lib/$ABI/" \;
  if [ -f "$stage/all/include/${name}.h" ]; then
    cp -a "$stage/all/include/${name}.h" "$one/include/"
  fi
  if [ -d "$stage/all/share/vala/vapi" ]; then
    find "$stage/all/share/vala/vapi" -maxdepth 1 -name "${name}.*" -exec cp -a {} "$one/share/vala/vapi/" \;
  fi
  req="$(requires_of "$name" | paste -sd, -)"
  cat > "$one/lib/$ABI/pkgconfig/${name}.pc" << EOF
prefix=$TOKEN
libdir=\${prefix}/lib/$ABI
includedir=\${prefix}/include

Name: $name
Description: $name
Version: $version
Requires: $req
Libs: -L\${libdir} -l$name
Cflags: -I\${includedir}
EOF
  asset="${name}-arm-v${API}-${version}.pixie"
  tar -C "$one" -cJf "$OUT/$asset" .
  inputs="$(sha256sum "$OUT/$asset" | awk '{ print $1 }')"
  url="https://github.com/${repo}/releases/download/${tag}/${asset}"
  tmp="$(mktemp)"
  jq \
    --arg abi "$ABI" \
    --arg repo_url "https://github.com/${repo}.git" \
    --arg name "$name" \
    --arg track "$version" \
    --arg resolved "$resolved" \
    --arg inputs "$inputs" \
    --arg url "$url" \
    '.packages += [{abi:$abi, repo:$repo_url, name:$name, track:$track, resolved:$resolved, inputs:$inputs, url:$url}]' \
    "$pins" > "$tmp"
  mv "$tmp" "$pins"
  found=$((found + 1))
  echo "Packed $asset"
done

if [ "$found" -eq 0 ]; then
  echo "No Android libraries were installed to pack" >&2
  exit 1
fi
jq '.' "$pins" > "$OUT/release.pins"
echo "Wrote $OUT/release.pins ($found packages)"
