#!/usr/bin/env bash
# Standard layout is android/local-build.local.env (trees inside the clone).
# Gitignored android/local-build.env is the one override when a machine keeps
# those trees elsewhere. Paths in that file are canonicalized before Meson
# sees the build directory.
# shellcheck shell=bash

_ollmchat_android_build_env_file() {
  local root_dir="$1"

  if [ -f "$root_dir/android/local-build.env" ]; then
    echo "$root_dir/android/local-build.env"
    return
  fi
  echo "$root_dir/android/local-build.local.env"
}

_ollmchat_canonicalize_dir() {
  local path="$1"

  mkdir -p "$path"
  realpath "$path"
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

  if [ -n "${OLLMCHAT_ANDROID_SDK:-}" ]; then
    OLLMCHAT_ANDROID_SDK="$(_ollmchat_canonicalize_dir "$OLLMCHAT_ANDROID_SDK")"
    export OLLMCHAT_ANDROID_SDK
  fi
  if [ -n "${OLLMCHAT_PIXIEWOOD:-}" ]; then
    OLLMCHAT_PIXIEWOOD="$(_ollmchat_canonicalize_dir "$OLLMCHAT_PIXIEWOOD")"
    export OLLMCHAT_PIXIEWOOD
  fi
  if [ -n "${OLLMCHAT_ANDROID_TOOLS:-}" ]; then
    OLLMCHAT_ANDROID_TOOLS="$(_ollmchat_canonicalize_dir "$OLLMCHAT_ANDROID_TOOLS")"
    export OLLMCHAT_ANDROID_TOOLS
  fi
  if [ -n "${OLLMCHAT_JAVA_HOME:-}" ]; then
    if [ ! -x "${OLLMCHAT_JAVA_HOME}/bin/java" ] || [ ! -x "${OLLMCHAT_JAVA_HOME}/bin/javac" ]; then
      echo "OLLMCHAT_JAVA_HOME needs bin/java and bin/javac: ${OLLMCHAT_JAVA_HOME}" >&2
      exit 1
    fi
    export JAVA_HOME="$OLLMCHAT_JAVA_HOME"
    export PATH="$JAVA_HOME/bin:$PATH"
  fi

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
