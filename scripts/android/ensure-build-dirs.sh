#!/usr/bin/env bash
# Picks android/local-build.{office,local}.env from office storage presence,
# or android/local-build.env if you create that gitignored override.
# shellcheck shell=bash

OLLMCHAT_OFFICE_BUILD_ROOT="${OLLMCHAT_OFFICE_BUILD_ROOT:-/storage/Downloads/OLLMchat-build}"

_ollmchat_android_build_env_file() {
  local root_dir="$1"

  if [ -f "$root_dir/android/local-build.env" ]; then
    echo "$root_dir/android/local-build.env"
    return
  fi
  if [ -d "$OLLMCHAT_OFFICE_BUILD_ROOT" ]; then
    echo "$root_dir/android/local-build.office.env"
    return
  fi
  echo "$root_dir/android/local-build.local.env"
}

ensure_android_build_dirs() {
  local root_dir="$1"
  local env_file
  env_file="$(_ollmchat_android_build_env_file "$root_dir")"

  # shellcheck disable=SC1090
  set -a
  # shellcheck source=/dev/null
  source "$env_file"
  set +a

  _ensure_android_build_link "$root_dir" .android-sdk "${OLLMCHAT_ANDROID_SDK:-}"
  _ensure_android_build_link "$root_dir" .pixiewood "${OLLMCHAT_PIXIEWOOD:-}"
  _ensure_android_build_link "$root_dir" .android-tools "${OLLMCHAT_ANDROID_TOOLS:-}"
}

_ensure_android_build_link() {
  local root_dir="$1"
  local name="$2"
  local target="$3"
  local link="$root_dir/$name"

  if [ -n "$target" ]; then
    mkdir -p "$target"
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      echo "Refusing to replace $link (not a symlink). Move it aside or remove it." >&2
      exit 1
    fi
    rm -f "$link"
    ln -s "$target" "$link"
    return
  fi

  if [ -L "$link" ]; then
    rm -f "$link"
  elif [ -e "$link" ]; then
    return
  fi
  mkdir -p "$link"
}
