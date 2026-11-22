#!/usr/bin/env bash
# R12 — verify-apk.sh requires pixie-gtk runtime tag (no android-bugs patch strings).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
VERIFY="$ROOT_DIR/scripts/android/verify-apk.sh"

[ -f "$VERIFY" ] || { echo "missing verify-apk.sh" >&2; exit 1; }

grep -q 'expected pixie-gtk' "$VERIFY" ||
  { echo "verify-apk.sh must require pixie-gtk runtime tag" >&2; exit 1; }
! grep -q 'ollmchat-android-bugs-v16' "$VERIFY" ||
  { echo "verify-apk.sh must not reference android-bugs patch tags" >&2; exit 1; }

echo "R12 verify-apk-runtime-tag: OK"