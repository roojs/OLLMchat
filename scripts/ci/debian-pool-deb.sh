#!/usr/bin/env bash
# Download a .deb from a Debian pool directory, optionally reusing a cache dir.
set -euo pipefail

usage() {
  echo "Usage: debian-pool-deb.sh POOL PACKAGE ARCH [OUTPUT_PATH]" >&2
  exit 2
}

POOL="${1:?pool URL required}"
PACKAGE="${2:?package name required}"
ARCH="${3:?architecture required}"
OUTPUT="${4:-}"

if [ -n "${DEB_CACHE_DIR:-}" ]; then
  mkdir -p "$DEB_CACHE_DIR"
fi

deb="$(
  curl -fsSL "$POOL/" \
    | grep -oE "href=\"${PACKAGE}_[^\"]+_${ARCH}\\.deb\"" \
    | sed 's/^href="//;s/"$//' \
    | sort -V \
    | tail -n1
)"

if [ -z "$deb" ]; then
  echo "Could not find ${PACKAGE}_*_${ARCH}.deb under ${POOL}" >&2
  exit 1
fi

if [ -n "${DEB_CACHE_DIR:-}" ]; then
  cached="${DEB_CACHE_DIR}/${deb}"
  if [ -s "$cached" ]; then
    echo "Using cached ${deb}" >&2
    if [ -n "$OUTPUT" ]; then
      cp "$cached" "$OUTPUT"
      printf '%s\n' "$OUTPUT"
    else
      printf '%s\n' "$cached"
    fi
    exit 0
  fi
  out="$cached"
else
  out="${OUTPUT:-/tmp/${PACKAGE}.deb}"
fi

echo "Downloading ${deb}" >&2
curl -fsSL "$POOL/${deb}" -o "$out"

if [ -n "$OUTPUT" ] && [ "$out" != "$OUTPUT" ]; then
  cp "$out" "$OUTPUT"
  printf '%s\n' "$OUTPUT"
else
  printf '%s\n' "$out"
fi
