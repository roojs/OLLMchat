#!/usr/bin/env bash
# Probe the libwebkitgtk .so behind PKG-CONFIG module $1 for a compile-time feature.
#
# Usage:
#   ./scripts/meson/check-webkit-interactions.sh webkitgtk-6.0
#   ./scripts/meson/check-webkit-interactions.sh webkitgtk-6.0-webdriver
#   ./scripts/meson/check-webkit-interactions.sh webkitgtk-6.0-webdriver navigator-policy
#
# Features (2nd arg, default interactions):
#   interactions      — SimulatedInputDispatcher linked in (Element Click / Send Keys)
#   navigator-policy  — webkit_settings_set_navigator_webdriver_active_policy exported
#
# Exit 0 = feature present; 1 = missing / unresolved.
set -euo pipefail

pc="${1:?pkg-config module name required}"
feature="${2:-interactions}"

if ! pkg-config --exists "$pc"; then
  exit 1
fi

libdir="$(pkg-config --variable=libdir "$pc")"
[[ -n "$libdir" && -d "$libdir" ]] || exit 1

resolve_so() {
  local flag base candidates
  # pkg-config --libs-only-l prints one space-separated line; split to flags.
  while read -r flag; do
    [[ -z "$flag" ]] && continue
    case "$flag" in
      -l:*)
        if [[ -e "$libdir/${flag#-l:}" ]]; then
          echo "$libdir/${flag#-l:}"
          return 0
        fi
        ;;
      -l*)
        base="${flag#-l}"
        for candidates in \
          "$libdir/lib${base}.so" \
          "$libdir/lib${base}.so."*; do
          if [[ -e "$candidates" ]]; then
            echo "$candidates"
            return 0
          fi
        done
        ;;
    esac
  done
  return 1
}

so="$(pkg-config --libs-only-l "$pc" | tr ' ' '\n' | resolve_so)" || exit 1

case "$feature" in
  interactions)
    # C++ type is not in the dynamic symbol table; grep -a sees it when linked in.
    # Prefer grep -a over `strings | grep` so pipefail does not treat SIGPIPE as failure.
    if grep -aFq 'SimulatedInputDispatcher' "$so"; then
      exit 0
    fi
    ;;
  navigator-policy)
    # Optional #165269 hide API — C symbol present in the binary when built in.
    # grep -a (not nm|grep) avoids pipefail SIGPIPE when grep exits early.
    if grep -aFq 'webkit_settings_set_navigator_webdriver_active_policy' "$so"; then
      exit 0
    fi
    ;;
  *)
    echo "unknown feature: $feature (use interactions|navigator-policy)" >&2
    exit 1
    ;;
esac

exit 1
