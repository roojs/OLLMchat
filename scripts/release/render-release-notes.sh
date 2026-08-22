#!/usr/bin/env bash
# Write GitHub release notes from CHANGELOG.md, with a preamble that
# sends Debian / Fedora / openSUSE users to the README (not this asset set).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <tag> [output-file]" >&2
  exit 1
fi

TAG="$1"
OUTPUT="${2:-$ROOT/release-notes.md}"
"$ROOT/scripts/release/changelog.sh" release-notes "$TAG" -o "$OUTPUT"

repo="${GITHUB_REPOSITORY:-roojs/OLLMchat}"
tmp="$(mktemp)"
{
  echo "**Debian, Fedora, and openSUSE:** install from the [roojs package repositories](https://roojs.github.io/repos/) (\`apt\` / \`dnf\` / \`zypper\`). Setup commands are in the [README](https://github.com/${repo}/blob/main/README.md#releases)."
  echo
  echo "\`.deb\` / \`.rpm\` files for this version are on [${TAG}-packages](https://github.com/${repo}/releases/tag/${TAG}-packages)."
  echo
  echo "This GitHub Release is AppImage, Windows, and Android."
  echo
  echo "---"
  echo
  cat "$OUTPUT"
} > "$tmp"
mv "$tmp" "$OUTPUT"
