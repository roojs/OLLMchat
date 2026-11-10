#!/usr/bin/env bash
# Put release.pins on the GitHub Pages site.
# Valadoc already occupies that site. This copies the live site and replaces
# the pin files. It leaves index.html as it was.
set -euo pipefail

pins=""
out=""
pages_url="${PIXIE_PAGES_URL:-https://roojs.github.io/OLLMchat}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pins) pins=${2:-}; shift 2 ;;
    --out) out=${2:-}; shift 2 ;;
    --pages-url) pages_url=${2:-}; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$pins" ] || [ -z "$out" ] || [ ! -f "$pins" ]; then
  echo "Usage: stage-pins-page.sh --pins FILE --out DIR [--pages-url URL]" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "stage-pins-page needs jq" >&2
  exit 1
fi
if ! command -v wget >/dev/null 2>&1; then
  echo "stage-pins-page needs wget" >&2
  exit 1
fi
if ! jq -e '.packages | type == "array"' "$pins" >/dev/null; then
  echo "Pin file has no packages array: $pins" >&2
  exit 1
fi

pages_url="${pages_url%/}"
mirror="$(mktemp -d)"
trap 'rm -rf "$mirror"' EXIT

echo "Reading $pages_url"
# wget exits 8 when a linked file is missing. The sentinel check below
# rejects a mirror that did not get the Valadoc pages.
set +e
wget -r -l inf -np -nH -x --cut-dirs=1 \
  -P "$mirror" \
  -e robots=off \
  --timeout=30 \
  --tries=3 \
  --retry-connrefused \
  --reject-regex '[?]' \
  -nv \
  "${pages_url}/"
status=$?
set -e
if [ "$status" -ne 0 ] && [ "$status" -ne 8 ]; then
  echo "Could not read $pages_url (wget status $status)" >&2
  exit 1
fi

mirror_root="$mirror"
if [ ! -f "$mirror_root/index.html" ] || [ ! -f "$mirror_root/ollmchat/index.htm" ]; then
  host="${pages_url#https://}"
  host="${host#http://}"
  host="${host%%/*}"
  if [ -f "$mirror/$host/OLLMchat/index.html" ]; then
    mirror_root="$mirror/$host/OLLMchat"
  elif [ -f "$mirror/OLLMchat/index.html" ]; then
    mirror_root="$mirror/OLLMchat"
  fi
fi
if [ ! -f "$mirror_root/index.html" ] || [ ! -f "$mirror_root/ollmchat/index.htm" ]; then
  echo "Pages mirror is missing Valadoc from $pages_url" >&2
  find "$mirror" -maxdepth 3 -type d >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out"
cp -a "$mirror_root"/. "$out"/
cp "$pins" "$out/release.pins"
if [ ! -f "$out/snapshot.pins" ] || ! jq -e '.packages | type == "array"' "$out/snapshot.pins" >/dev/null; then
  jq -n '{packages:[]}' > "$out/snapshot.pins"
fi
if [ ! -f "$out/.nojekyll" ]; then
  : > "$out/.nojekyll"
fi
if ! cmp -s "$mirror_root/index.html" "$out/index.html"; then
  echo "index.html changed while staging pins" >&2
  exit 1
fi
echo "Staged $(jq '.packages | length' "$out/release.pins") release pins into $out"
