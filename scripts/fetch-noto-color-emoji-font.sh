#!/bin/bash
set -euo pipefail
# Download Noto Color Emoji for the Windows sqgipkg bundle (gitignored; not in apt).

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
FONT="$ROOT/resources/fonts/NotoColorEmoji.ttf"
URL="https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf"

if [[ -s "$FONT" ]]; then
  echo "Using existing $FONT"
  exit 0
fi

command -v curl >/dev/null 2>&1 || { echo "curl required" >&2; exit 1; }

mkdir -p "$(dirname "$FONT")"
echo "Downloading Noto Color Emoji to $FONT"
curl -fsSL -o "$FONT" "$URL"
[[ -s "$FONT" ]] || { echo "download failed or empty: $FONT" >&2; exit 1; }
