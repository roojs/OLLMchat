#!/usr/bin/env bash
# Write GitHub release notes from CHANGELOG.md [Unreleased] section.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <tag> [output-file]" >&2
  exit 1
fi

TAG="$1"
OUTPUT="${2:-$ROOT/release-notes.md}"
exec "$ROOT/scripts/release/changelog.sh" release-notes "$TAG" -o "$OUTPUT"
