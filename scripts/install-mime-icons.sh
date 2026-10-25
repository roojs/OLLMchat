#!/bin/bash
# Copy Humanity mime icons into one hicolor folder.
# meson install and the Android package both use that folder.
set -eu

src=/usr/share/icons/Humanity/mimes/48
if [ ! -d "$src" ]; then
  echo "Humanity icon theme is not installed." >&2
  echo "Install it: apt install humanity-icon-theme" >&2
  exit 1
fi

if [ $# -ge 1 ]; then
  dest=$1
else
  dest="${MESON_INSTALL_DESTDIR_PREFIX}/share/icons/hicolor/scalable/mimetypes"
fi

mkdir -p "$dest"
shopt -s nullglob
copied=0
for src_file in "$src"/*.svg; do
  cp -L "$src_file" "$dest/$(basename "$src_file")"
  copied=$((copied + 1))
done
if [ "$copied" -eq 0 ]; then
  echo "Humanity mime directory has no SVG files: $src" >&2
  exit 1
fi
