#!/usr/bin/env bash
# GitHub Actions helper: add the roojs APT source used by Debian package CI
# (.github/workflows/release.yml). Not the user-facing install path — that is
# https://roojs.github.io/repos/ (key + sources file). Do not download FAISS,
# llama.cpp/libggml, or tree-sitter parsers from Debian pool directories.
set -euo pipefail

run() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

suite="${ROOJS_APT_SUITE:-}"
if [ -z "$suite" ]; then
  suite="$(lsb_release -cs 2>/dev/null || true)"
fi
if [ -z "$suite" ] && [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  suite="${VERSION_CODENAME:-}"
fi
if [ -z "$suite" ]; then
  echo "Set ROOJS_APT_SUITE (trixie, plucky, questing, or resolute) or install lsb-release." >&2
  exit 1
fi

case "$suite" in
  trixie|plucky|questing|resolute) ;;
  *)
    echo "Suite '${suite}' is not published at https://roojs.github.io/repos/" >&2
    echo "Use Debian 13 (trixie) or Ubuntu 25.04+ (plucky/questing/resolute)." >&2
    exit 1
    ;;
esac

run apt-get update
run apt-get install -y --no-install-recommends ca-certificates curl gnupg
run install -d -m 0755 /etc/apt/keyrings
run rm -f /etc/apt/keyrings/roojs.gpg
curl -fsSL https://roojs.github.io/repos/key.gpg \
  | run gpg --batch --yes --dearmor -o /etc/apt/keyrings/roojs.gpg
curl -fsSL https://roojs.github.io/repos/sources \
  | sed "s/@suite@/${suite}/" \
  | run tee /etc/apt/sources.list.d/roojs.sources >/dev/null
run chmod 0644 /etc/apt/keyrings/roojs.gpg /etc/apt/sources.list.d/roojs.sources
run apt-get update
echo "Enabled roojs APT source for suite ${suite}."
