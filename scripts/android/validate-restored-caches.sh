#!/usr/bin/env bash
# Discard stale Android CI caches after restore; keep only trees that match current
# PIXIEWOOD_DEPS_HASH and runtime patch markers. No manual cache clearing required.
#
# Optional environment (set by GitHub Actions after actions/cache/restore):
#   PIXIEWOOD_DEPS_HASH
#   PIXIEWOOD_APP_HASH
#   CACHE_MATCHED_SUBPROJECTS_KEY
#   CACHE_MATCHED_GTK_BOOTSTRAP_KEY
#   CACHE_MATCHED_PIXIEWOOD_BUILD_KEY
#
# Prints: pixiewood_compile_cache_usable=true|false
# When GITHUB_OUTPUT is set, also writes: usable=true|false

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ROOT_DIR

# shellcheck source=pixiewood-cache.sh
source "$ROOT_DIR/scripts/android/pixiewood-cache.sh"
# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

cache_key_matches_deps_hash() {
  local matched_key="${1:-}"
  local deps_hash="${2:-}"

  [ -n "$matched_key" ] && [ -n "$deps_hash" ] &&
    [[ "$matched_key" == *"$deps_hash"* ]]
}

discard_subprojects_gtk_if_stale() {
  local gtk_dir="$ROOT_DIR/subprojects/gtk"

  if [ -n "${CACHE_MATCHED_SUBPROJECTS_KEY:-}" ] &&
     [ -n "${PIXIEWOOD_DEPS_HASH:-}" ] &&
     ! cache_key_matches_deps_hash "$CACHE_MATCHED_SUBPROJECTS_KEY" "$PIXIEWOOD_DEPS_HASH"; then
    echo "Discarding subprojects/gtk (restored subprojects cache predates PIXIEWOOD_DEPS_HASH)." >&2
    rm -rf "$gtk_dir"
    return 0
  fi

  if [ -d "$gtk_dir" ] && gtk_subproject_is_complete && ! gtk_subproject_patch_applied; then
    echo "Discarding subprojects/gtk (android-bugs.patch not applied or marker outdated)." >&2
    rm -rf "$gtk_dir"
  fi
}

discard_gtk_bootstrap_if_stale() {
  local cache
  cache="$(gtk_bootstrap_cache_dir)"

  if [ ! -d "$cache" ]; then
    return 0
  fi

  if [ -n "${CACHE_MATCHED_GTK_BOOTSTRAP_KEY:-}" ] &&
     [ -n "${PIXIEWOOD_DEPS_HASH:-}" ] &&
     ! cache_key_matches_deps_hash "$CACHE_MATCHED_GTK_BOOTSTRAP_KEY" "$PIXIEWOOD_DEPS_HASH"; then
    echo "Discarding GTK bootstrap cache (restored key predates PIXIEWOOD_DEPS_HASH)." >&2
    rm -rf "$cache"
    return 0
  fi

  if ! gtk_bootstrap_cache_is_valid; then
    echo "Discarding invalid GTK bootstrap cache." >&2
    rm -rf "$cache"
  fi
}

discard_pixiewood_compile_if_stale() {
  local discard=false
  local matched_key="${CACHE_MATCHED_PIXIEWOOD_BUILD_KEY:-}"

  if [ -n "$matched_key" ]; then
    if [ -n "${PIXIEWOOD_DEPS_HASH:-}" ] &&
       ! cache_key_matches_deps_hash "$matched_key" "${PIXIEWOOD_DEPS_HASH}"; then
      discard=true
    fi
    if [ -n "${PIXIEWOOD_APP_HASH:-}" ] &&
       ! cache_key_matches_deps_hash "$matched_key" "${PIXIEWOOD_APP_HASH}"; then
      discard=true
    fi
  fi

  if [ "$discard" = true ]; then
    echo "Discarding Pixiewood compile cache (restored key predates current PIXIEWOOD_DEPS_HASH or PIXIEWOOD_APP_HASH)." >&2
    discard_pixiewood_compile_state
    return 0
  fi

  ensure_pixiewood_compile_state_consistent
}

discard_subprojects_gtk_if_stale
discard_gtk_bootstrap_if_stale
discard_pixiewood_compile_if_stale

usable=false
if pixiewood_compile_cache_looks_usable; then
  usable=true
fi

printf 'pixiewood_compile_cache_usable=%s\n' "$usable"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "usable=$usable" >> "$GITHUB_OUTPUT"
fi
