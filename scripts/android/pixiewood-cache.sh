#!/usr/bin/env bash
# Pixiewood compile-cache and toolchain.cross validation helpers.
# shellcheck shell=bash

version_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" = "$1" ]
}

pixiewood_toolchain_cross_file() {
  echo "$ROOT_DIR/.pixiewood/toolchain.cross"
}

pixiewood_toolchain_llvm_dir() {
  local tc llvm_dir
  tc="$(pixiewood_toolchain_cross_file)"
  [ -f "$tc" ] || return 1
  llvm_dir="$(
    sed -n "s/^toolchain[[:space:]]*=[[:space:]]*['\"]\\(.*\\)['\"]/\\1/p" "$tc" | head -1
  )"
  [ -n "$llvm_dir" ] || return 1
  printf '%s\n' "$llvm_dir"
}

pixiewood_toolchain_cross_valid() {
  local llvm_dir clang
  llvm_dir="$(pixiewood_toolchain_llvm_dir || true)"
  [ -n "$llvm_dir" ] || return 1
  clang="$llvm_dir/bin/aarch64-linux-android31-clang"
  [ -x "$clang" ]
}

discard_pixiewood_compile_state() {
  rm -rf "$ROOT_DIR/.pixiewood/bin-aarch64"
  rm -f "$ROOT_DIR/.pixiewood/pixiewood.ini"
  rm -f "$ROOT_DIR/.pixiewood/toolchain.cross"
}

pixiewood_prefix_has_patched_gtk_object() {
  find "$ROOT_DIR/.pixiewood/bin-aarch64" \
    -name 'gdkandroidollmchatpatch*.o' -print -quit 2>/dev/null | grep -q .
}

pixiewood_prefix_libgtk_has_patch_tag() {
  local libgtk
  libgtk="$(
    find "$ROOT_DIR/.pixiewood/bin-aarch64" -name 'libgtk-4.so' -print -quit 2>/dev/null
  )"
  [ -n "$libgtk" ] && strings "$libgtk" 2>/dev/null | grep -q 'ollmchat-android-bugs-v5'
}

pixiewood_prefix_has_patched_gtk() {
  pixiewood_prefix_has_patched_gtk_object || return 1
  if find "$ROOT_DIR/.pixiewood/bin-aarch64" -name 'libgtk-4.so' -print -quit 2>/dev/null | grep -q .; then
    pixiewood_prefix_libgtk_has_patch_tag || return 1
  fi
  return 0
}

pixiewood_compile_cache_looks_usable() {
  local build_dir="$ROOT_DIR/.pixiewood/bin-aarch64"
  local obj_count cache_bytes meson_ver meson_min="${MESON_MIN_VERSION:-1.8.0}"

  [ -f "$build_dir/build.ninja" ] &&
    [ -f "$build_dir/meson-logs/meson-log.txt" ] &&
    [ -f "$ROOT_DIR/.pixiewood/pixiewood.ini" ] &&
    pixiewood_toolchain_cross_valid &&
    pixiewood_prefix_has_patched_gtk || return 1

  obj_count="$(find "$build_dir" -type f -name '*.o' 2>/dev/null | wc -l)"
  cache_bytes="$(du -sb "$build_dir" 2>/dev/null | cut -f1)"
  meson_ver="$(grep -m1 '^Version: ' "$build_dir/meson-logs/meson-log.txt" | sed 's/^Version: //')"

  [ "$obj_count" -ge 100 ] &&
    [ "$cache_bytes" -ge 30000000 ] &&
    version_ge "$meson_ver" "$meson_min"
}

ensure_pixiewood_compile_state_consistent() {
  local build_dir="$ROOT_DIR/.pixiewood/bin-aarch64"
  local has_ninja has_ini has_tc tc_valid

  has_ninja=false
  has_ini=false
  has_tc=false
  tc_valid=false
  [ -f "$build_dir/build.ninja" ] && has_ninja=true
  [ -f "$ROOT_DIR/.pixiewood/pixiewood.ini" ] && has_ini=true
  [ -f "$(pixiewood_toolchain_cross_file)" ] && has_tc=true
  pixiewood_toolchain_cross_valid && tc_valid=true

  if pixiewood_compile_cache_looks_usable; then
    return 0
  fi

  if [ "$has_tc" = true ] && [ "$tc_valid" = false ]; then
    echo "Discarding Pixiewood state (toolchain.cross points at missing NDK)." >&2
    discard_pixiewood_compile_state
    return 0
  fi

  if [ "$has_ninja" = true ] && { [ "$has_ini" = false ] || [ "$tc_valid" = false ]; }; then
    echo "Discarding Pixiewood state (build.ninja without valid toolchain/ini)." >&2
    discard_pixiewood_compile_state
    return 0
  fi

  if [ "$has_ini" = true ] && [ "$has_tc" = false ]; then
    echo "Discarding Pixiewood state (pixiewood.ini without toolchain.cross)." >&2
    discard_pixiewood_compile_state
  fi
}
