#!/usr/bin/env bash
# Expand android/pixie-gtk.pins (track: latest) to a pixie-pkg row with url and inputs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="${PIXIE_GTK_PINS:-$ROOT_DIR/android/pixie-gtk.pins}"
API="${PIXIE_GTK_GITLAB_API:-https://gitlab.gnome.org/api/v4}"

if ! command -v jq >/dev/null 2>&1; then
  echo "resolve-pixie-gtk-pins needs jq" >&2
  exit 1
fi
if [ ! -f "$TEMPLATE" ]; then
  echo "GTK pixie template missing: $TEMPLATE" >&2
  exit 1
fi

project="$(jq -r '.packages[0].gitlab_project // "Knowles/gtk"' "$TEMPLATE")"
pkg_name="$(jq -r '.packages[0].package_name // "gtk"' "$TEMPLATE")"
abi="$(jq -r '.packages[0].abi // "arm64-v8a"' "$TEMPLATE")"
repo="$(jq -r '.packages[0].repo // "https://gitlab.gnome.org/Knowles/gtk.git"' "$TEMPLATE")"
track="$(jq -r '.packages[0].track // "latest"' "$TEMPLATE")"

if [ "$track" != "latest" ]; then
  if jq -e '.packages[0].url // "" | length > 0' "$TEMPLATE" >/dev/null; then
    cat "$TEMPLATE"
    exit 0
  fi
  echo "pixie-gtk.pins track is not latest and no url is set: $TEMPLATE" >&2
  exit 1
fi

project_enc="${project//\//%2F}"
list_url="$API/projects/$project_enc/packages?package_type=generic&package_name=$pkg_name&order_by=created_at&sort=desc&per_page=1"
meta="$(curl -fsSL --retry 3 --retry-delay 2 "$list_url")"
version="$(printf '%s' "$meta" | jq -r '.[0].version // empty')"
pkg_id="$(printf '%s' "$meta" | jq -r '.[0].id // empty')"
if [ -z "$version" ] || [ -z "$pkg_id" ]; then
  echo "No generic $pkg_name package on GitLab project $project" >&2
  exit 1
fi

files_url="$API/projects/$project_enc/packages/$pkg_id/package_files"
files="$(curl -fsSL --retry 3 --retry-delay 2 "$files_url")"
file_name="$(printf '%s' "$files" | jq -r '.[0].file_name // empty')"
inputs="$(printf '%s' "$files" | jq -r --arg fn "$file_name" '
  .[]
  | select(.file_name == $fn)
  | .file_sha256
  ')"
resolved="$(printf '%s' "$meta" | jq -r '.[0].pipeline.sha // empty')"
if [ -z "$file_name" ] || [ -z "$inputs" ] || [ "$inputs" = null ]; then
  echo "Could not read .pixie file metadata for $project $version" >&2
  exit 1
fi

url="$API/projects/$project_enc/packages/generic/$pkg_name/$version/$file_name"

jq -n \
  --arg abi "$abi" \
  --arg repo "$repo" \
  --arg name "$pkg_name" \
  --arg track "$version" \
  --arg resolved "$resolved" \
  --arg inputs "$inputs" \
  --arg url "$url" \
  '{
    packages: [{
      abi: $abi,
      repo: $repo,
      name: $name,
      track: $track,
      resolved: $resolved,
      inputs: $inputs,
      url: $url
    }]
  }'