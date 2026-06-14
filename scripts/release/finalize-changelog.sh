#!/usr/bin/env bash
# Promote [Unreleased] to a versioned section after a successful GitHub release.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <tag>   e.g. v1.2.5-alpha" >&2
  exit 1
fi

exec "$ROOT/scripts/release/changelog.sh" finalize "$1"
