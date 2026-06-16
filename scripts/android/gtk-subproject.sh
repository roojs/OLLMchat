#!/usr/bin/env bash
# GTK subproject bootstrap for Android Pixiewood builds (roojs/gtk fork).
# shellcheck shell=bash

gtk_subproject_patch_marker() {
  echo "$ROOT_DIR/subprojects/gtk/gdk/android/gdkandroidollmchatpatch.c"
}

gtk_subproject_tree_has_ollmchat_fixes() {
  local gtk_dir="$1"
  local marker="$gtk_dir/gdk/android/gdkandroidollmchatpatch.c"
  local im_context="$gtk_dir/gdk/android/glue/java/org/gtk/android/ImContext.java"

  [ -f "$marker" ] && grep -q 'ollmchat-android-bugs-v4' "$marker" &&
    grep -q 'ollmchat-android-popup-v4' "$marker" &&
    grep -q 'ollmchat-android-tls-v4' "$marker" &&
    [ -f "$im_context" ] && grep -q 'syncEditableFromGtk' "$im_context"
}

gtk_subproject_patch_applied() {
  gtk_subproject_tree_has_ollmchat_fixes "$ROOT_DIR/subprojects/gtk"
}

gtk_bootstrap_cache_dir() {
  echo "$ROOT_DIR/.pixiewood/gtk-subproject-bootstrap"
}

gtk_bootstrap_revision_stamp() {
  echo "$(gtk_bootstrap_cache_dir)/.revision"
}

gtk_subproject_is_complete() {
  local gtk_dir="$ROOT_DIR/subprojects/gtk"

  [ -f "$gtk_dir/meson.build" ] &&
    [ -f "$gtk_dir/subprojects/graphene.wrap" ]
}

gtk_wrap_file() {
  echo "$ROOT_DIR/subprojects/gtk.wrap"
}

gtk_subproject_wrap_url() {
  sed -n 's/^url[[:space:]]*=[[:space:]]*//p' "$(gtk_wrap_file)" | head -1
}

gtk_subproject_wrap_revision() {
  sed -n 's/^revision[[:space:]]*=[[:space:]]*//p' "$(gtk_wrap_file)" | head -1
}

gtk_subproject_matches_wrap_revision() {
  local gtk_dir="$ROOT_DIR/subprojects/gtk"
  local expected actual

  expected="$(gtk_subproject_wrap_revision)"
  [ -n "$expected" ] || return 1
  if [ -d "$gtk_dir/.git" ]; then
    actual="$(git -C "$gtk_dir" rev-parse HEAD 2>/dev/null || true)"
    [ "$actual" = "$expected" ] && return 0
  fi
  actual="$(cat "$gtk_dir/.revision" 2>/dev/null || true)"
  [ "$actual" = "$expected" ]
}

gtk_bootstrap_cache_is_valid() {
  local cache expected_rev actual_rev
  cache="$(gtk_bootstrap_cache_dir)"
  expected_rev="$(gtk_subproject_wrap_revision)"

  [ -n "$expected_rev" ] || return 1
  actual_rev="$(cat "$cache/.revision" 2>/dev/null || true)"
  [ "$actual_rev" = "$expected_rev" ] &&
    [ -f "$cache/meson.build" ] &&
    [ -f "$cache/subprojects/graphene.wrap" ] &&
    gtk_subproject_tree_has_ollmchat_fixes "$cache"
}

save_gtk_subproject_bootstrap() {
  local gtk_dir cache revision
  gtk_dir="$ROOT_DIR/subprojects/gtk"
  cache="$(gtk_bootstrap_cache_dir)"
  revision="$(gtk_subproject_wrap_revision)"

  if [ -z "$revision" ] ||
     ! gtk_subproject_is_complete ||
     ! gtk_subproject_patch_applied; then
    return 1
  fi

  rm -rf "$cache"
  mkdir -p "$(dirname "$cache")"
  cp -a "$gtk_dir" "$cache"
  printf '%s\n' "$revision" > "$cache/.revision"
}

restore_gtk_subproject_from_bootstrap() {
  local gtk_dir cache
  gtk_dir="$ROOT_DIR/subprojects/gtk"
  cache="$(gtk_bootstrap_cache_dir)"

  rm -rf "$gtk_dir"
  cp -a "$cache" "$gtk_dir"
}

clone_gtk_subproject_from_wrap() {
  local gtk_dir url revision
  gtk_dir="$ROOT_DIR/subprojects/gtk"
  url="$(gtk_subproject_wrap_url)"
  revision="$(gtk_subproject_wrap_revision)"

  if [ -z "$url" ] || [ -z "$revision" ]; then
    echo "Could not parse url/revision from $(gtk_wrap_file)." >&2
    exit 1
  fi

  echo "Cloning GTK from gtk.wrap ($revision)." >&2
  git clone --depth 1 "$url" "$gtk_dir"
  git -C "$gtk_dir" fetch --depth 1 origin "$revision"
  git -C "$gtk_dir" checkout "$revision"
  printf '%s\n' "$revision" > "$gtk_dir/.revision"
}

gtk_subproject_checkout_ready() {
  gtk_subproject_is_complete &&
    gtk_subproject_patch_applied &&
    gtk_subproject_matches_wrap_revision
}

ensure_gtk_subproject_checked_out() {
  local gtk_dir="$ROOT_DIR/subprojects/gtk"

  if gtk_subproject_checkout_ready; then
    return 0
  fi

  if gtk_subproject_is_complete &&
     [ -f "$(gtk_subproject_patch_marker)" ] &&
     ! gtk_subproject_patch_applied; then
    echo "GTK fork markers outdated; discarding checkout and bootstrap cache." >&2
    rm -rf "$gtk_dir" "$(gtk_bootstrap_cache_dir)"
  elif gtk_subproject_is_complete &&
       ! gtk_subproject_matches_wrap_revision; then
    echo "GTK fork revision mismatch; discarding checkout." >&2
    rm -rf "$gtk_dir"
  elif [ -d "$gtk_dir" ] && ! gtk_subproject_is_complete; then
    echo "GTK subproject incomplete; replacing it." >&2
    rm -rf "$gtk_dir"
  fi

  if gtk_bootstrap_cache_is_valid; then
    echo "Restoring GTK from bootstrap cache." >&2
    restore_gtk_subproject_from_bootstrap
    if gtk_subproject_checkout_ready; then
      return 0
    fi
    echo "Bootstrap cache copy was incomplete or stale; discarding cache." >&2
    rm -rf "$gtk_dir" "$(gtk_bootstrap_cache_dir)"
  fi

  clone_gtk_subproject_from_wrap

  if ! gtk_subproject_checkout_ready; then
    echo "GTK fork checkout is missing OLLMchat Android fixes or wrong revision." >&2
    exit 1
  fi
}

ensure_gtk_subproject_patched() {
  ensure_gtk_subproject_checked_out
  save_gtk_subproject_bootstrap || true
}

prepare_android_subprojects_before_meson() {
  ensure_gtk_subproject_checked_out
  ensure_gtk_subproject_patched
}
