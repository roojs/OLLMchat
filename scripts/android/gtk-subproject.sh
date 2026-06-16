#!/usr/bin/env bash
# GTK subproject bootstrap and patch helpers for Android Pixiewood builds.
# shellcheck shell=bash

gtk_subproject_patch_marker() {
  echo "$ROOT_DIR/subprojects/gtk/gdk/android/gdkandroidollmchatpatch.c"
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

gtk_bootstrap_cache_is_valid() {
  local cache expected_rev actual_rev
  cache="$(gtk_bootstrap_cache_dir)"
  expected_rev="$(gtk_subproject_wrap_revision)"

  [ -n "$expected_rev" ] || return 1
  actual_rev="$(cat "$cache/.revision" 2>/dev/null || true)"
  [ "$actual_rev" = "$expected_rev" ] &&
    [ -f "$cache/meson.build" ] &&
    [ -f "$cache/subprojects/graphene.wrap" ] &&
    [ -f "$cache/gdk/android/gdkandroidollmchatpatch.c" ]
}

save_gtk_subproject_bootstrap() {
  local gtk_dir cache revision
  gtk_dir="$ROOT_DIR/subprojects/gtk"
  cache="$(gtk_bootstrap_cache_dir)"
  revision="$(gtk_subproject_wrap_revision)"

  if [ -z "$revision" ] ||
     ! gtk_subproject_is_complete ||
     [ ! -f "$(gtk_subproject_patch_marker)" ]; then
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
}

ensure_gtk_subproject_checked_out() {
  local gtk_dir="$ROOT_DIR/subprojects/gtk"

  if gtk_subproject_is_complete; then
    return 0
  fi

  if [ -d "$gtk_dir" ]; then
    echo "GTK subproject incomplete; replacing it." >&2
    rm -rf "$gtk_dir"
  fi

  if gtk_bootstrap_cache_is_valid; then
    echo "Restoring GTK from bootstrap cache." >&2
    restore_gtk_subproject_from_bootstrap
    if gtk_subproject_is_complete; then
      return 0
    fi
    echo "Bootstrap cache copy was incomplete; discarding cache." >&2
    rm -rf "$gtk_dir" "$(gtk_bootstrap_cache_dir)"
  fi

  clone_gtk_subproject_from_wrap

  if ! gtk_subproject_is_complete; then
    echo "GTK checkout is still incomplete." >&2
    exit 1
  fi
}

ensure_gtk_subproject_patched() {
  local gtk_dir="$ROOT_DIR/subprojects/gtk"
  local marker patch
  marker="$(gtk_subproject_patch_marker)"
  patch="$ROOT_DIR/android/pixiewood-wraps/gtk/android-bugs.patch"

  if [ -f "$marker" ]; then
    save_gtk_subproject_bootstrap || true
    return 0
  fi

  ensure_gtk_subproject_checked_out

  if [ ! -f "$patch" ]; then
    echo "android-bugs.patch missing: $patch" >&2
    exit 1
  fi

  echo "Applying android-bugs.patch to GTK subproject." >&2
  patch -p1 -d "$gtk_dir" --forward --batch -s < "$patch" || true

  if [ -f "$marker" ]; then
    save_gtk_subproject_bootstrap || true
    return 0
  fi

  echo "Could not patch GTK subproject; refreshing from bootstrap or gtk.wrap." >&2
  rm -rf "$gtk_dir"
  ensure_gtk_subproject_checked_out
  patch -p1 -d "$gtk_dir" --forward --batch -s < "$patch" || true

  if [ ! -f "$marker" ]; then
    echo "android-bugs.patch did not apply after GTK refresh." >&2
    exit 1
  fi

  save_gtk_subproject_bootstrap || true
}

prepare_android_subprojects_before_meson() {
  ensure_gtk_subproject_checked_out
  ensure_gtk_subproject_patched
}
