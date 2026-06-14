#!/usr/bin/env bash
# Generate debian/changelog from CHANGELOG.md (single source of truth).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/scripts/release/changelog.sh" sync "$@"
