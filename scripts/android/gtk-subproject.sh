#!/usr/bin/env bash
# GTK subproject bootstrap and patch helpers for Android Pixiewood builds.
#
# ** DO NOT WORK AROUND PIXIEWOOD_USE_PIXIE=1 ** — These helpers are for
# build-source-diff-apk.sh / regression tests only (pixie unset). Chat POC must
# not call checkout or patch paths; see refuse-gtk-subproject.sh.
# shellcheck shell=bash

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=refuse-gtk-subproject.sh
source "$ROOT_DIR/scripts/android/refuse-gtk-subproject.sh"

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
    [ -f "$cache/subprojects/graphene.wrap" ]
}

save_gtk_subproject_bootstrap() {
  refuse_gtk_subproject_work "Saving GTK bootstrap cache"
  local gtk_dir cache revision
  gtk_dir="$ROOT_DIR/subprojects/gtk"
  cache="$(gtk_bootstrap_cache_dir)"
  revision="$(gtk_subproject_wrap_revision)"

  gtk_subproject_is_complete || return 1

  rm -rf "$cache"
  mkdir -p "$(dirname "$cache")"
  cp -a "$gtk_dir" "$cache"
  printf '%s\n' "$revision" > "$cache/.revision"
}

restore_gtk_subproject_from_bootstrap() {
  refuse_gtk_subproject_work "Restoring GTK from bootstrap cache"
  local gtk_dir cache
  gtk_dir="$ROOT_DIR/subprojects/gtk"
  cache="$(gtk_bootstrap_cache_dir)"

  rm -rf "$gtk_dir"
  cp -a "$cache" "$gtk_dir"
}

clone_gtk_subproject_from_wrap() {
  refuse_gtk_subproject_work "Cloning GTK from gtk.wrap"
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
  refuse_gtk_subproject_work "Ensuring GTK subproject checkout"
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

pango_pin_revision() {
  wrap_file_revision "$ROOT_DIR/android/pixiewood-wraps/gtk/pango.wrap.pin"
}

pango_checkout_matches_pin() {
  local pin actual
  pin="$(pango_pin_revision)"
  [ -n "$pin" ] || return 1
  [ -d "$ROOT_DIR/subprojects/pango/.git" ] || return 1
  actual="$(git -C "$ROOT_DIR/subprojects/pango" rev-parse HEAD 2>/dev/null || true)"
  [ "$actual" = "$pin" ]
}

harfbuzz_pin_revision() {
  wrap_file_revision "$ROOT_DIR/android/pixiewood-wraps/gtk/harfbuzz.wrap.pin"
}

harfbuzz_checkout_matches_pin() {
  local pin actual
  pin="$(harfbuzz_pin_revision)"
  [ -n "$pin" ] || return 1
  [ -d "$ROOT_DIR/subprojects/harfbuzz/.git" ] || return 1
  actual="$(git -C "$ROOT_DIR/subprojects/harfbuzz" rev-parse HEAD 2>/dev/null || true)"
  [ "$actual" = "$pin" ]
}

libadwaita_checkout_matches_pin() {
  local wrap rev actual
  wrap="$ROOT_DIR/android/pixiewood-wraps/libadwaita/libadwaita.wrap"
  [ -f "$wrap" ] || return 1
  rev="$(wrap_file_revision "$wrap")"
  [ -n "$rev" ] || return 1
  [ -d "$ROOT_DIR/subprojects/libadwaita/.git" ] || return 1
  actual="$(git -C "$ROOT_DIR/subprojects/libadwaita" rev-parse HEAD 2>/dev/null || true)"
  [ "$actual" = "$rev" ]
}

glib_stack_wrap_git_is_floating() {
  local wrap rev
  for wrap in \
    "$ROOT_DIR/subprojects/glib.wrap" \
    "$ROOT_DIR/subprojects/gtk.wrap" \
    "$ROOT_DIR/subprojects/libadwaita.wrap" \
    "$ROOT_DIR/subprojects/gtk/subprojects/pango.wrap" \
    "$ROOT_DIR/subprojects/gtk/subprojects/glib.wrap"; do
    [ -f "$wrap" ] || continue
    grep -q '^\[wrap-git\]' "$wrap" || continue
    rev="$(wrap_file_revision "$wrap")"
    case "$rev" in
      main|master|HEAD) return 0 ;;
    esac
  done
  return 1
}

discard_floating_glib_stack_checkouts() {
  local wrap rev dir
  for wrap in \
    "$ROOT_DIR/subprojects/libadwaita.wrap" \
    "$ROOT_DIR/subprojects/gtk/subprojects/pango.wrap"; do
    [ -f "$wrap" ] || continue
    grep -q '^\[wrap-git\]' "$wrap" || continue
    rev="$(wrap_file_revision "$wrap")"
    case "$rev" in
      main|master|HEAD) ;;
      *) continue ;;
    esac
    dir="$(wrap_file_directory "$wrap")"
    [ -n "$dir" ] || dir="$(basename "$wrap" .wrap)"
    echo "Discarding floating wrap-git checkout $dir (wrap tracks $rev)." >&2
    rm -rf "$ROOT_DIR/subprojects/$dir"
  done
}

wrap_file_directory() {
  sed -n 's/^directory[[:space:]]*=[[:space:]]*//p' "$1" | head -1 | tr -d '[:space:]'
}

wrap_file_url() {
  sed -n 's/^url[[:space:]]*=[[:space:]]*//p' "$1" | head -1 | tr -d '[:space:]'
}

ensure_git_checkout_at_revision() {
  local dir="$1" url="$2" rev="$3" actual peeled
  if [ -d "$dir/.git" ] && [ -n "$rev" ]; then
    actual="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
    if [ "$actual" = "$rev" ]; then
      return 0
    fi
    peeled="$(git -C "$dir" rev-parse --verify -q "${rev}^{commit}" 2>/dev/null || true)"
    if [ -n "$peeled" ] && [ "$actual" = "$peeled" ]; then
      return 0
    fi
  fi
  if [ -z "$url" ] || [ -z "$rev" ]; then
    echo "cannot checkout $dir: missing url or revision" >&2
    exit 1
  fi
  echo "Checking out $dir at $rev." >&2
  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$url"
  git -C "$dir" fetch --depth 1 origin "$rev"
  git -C "$dir" checkout --detach FETCH_HEAD
  if [[ ! "$rev" =~ ^[0-9a-fA-F]{40}$ ]]; then
    git -C "$dir" update-ref "refs/tags/$rev" HEAD
  fi
}

ensure_pinned_wrap_git_checkouts() {
  local wrap pin dir
  wrap="$ROOT_DIR/android/pixiewood-wraps/libadwaita/libadwaita.wrap"
  if [ -f "$wrap" ]; then
    dir="$(wrap_file_directory "$wrap")"
    [ -n "$dir" ] || dir=libadwaita
    ensure_git_checkout_at_revision \
      "$ROOT_DIR/subprojects/$dir" \
      "$(wrap_file_url "$wrap")" \
      "$(wrap_file_revision "$wrap")"
  fi
  for pin in "$ROOT_DIR/android/pixiewood-wraps/gtk/"*.wrap.pin; do
    [ -f "$pin" ] || continue
    dir="$(wrap_file_directory "$pin")"
    [ -n "$dir" ] || continue
    ensure_git_checkout_at_revision \
      "$ROOT_DIR/subprojects/$dir" \
      "$(wrap_file_url "$pin")" \
      "$(wrap_file_revision "$pin")"
  done
}

wrap_file_revision() {
  sed -n 's/^revision[[:space:]]*=[[:space:]]*//p' "$1" | head -1 | tr -d '[:space:]'
}

discard_git_checkout_unless_revision() {
  local dir="$1" rev="$2" actual
  [ -e "$dir" ] || return 0
  if [ -d "$dir/.git" ] && [ -n "$rev" ]; then
    actual="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
    if [ "$actual" = "$rev" ]; then
      return 0
    fi
  fi
  echo "Discarding stale checkout $dir (want $rev)." >&2
  rm -rf "$dir"
}

discard_stale_pinned_checkouts() {
  local wrap pin dir rev
  for wrap in "$ROOT_DIR/android/pixiewood-wraps/"*/*.wrap; do
    [ -f "$wrap" ] || continue
    grep -q '^\[wrap-git\]' "$wrap" || continue
    dir="$(wrap_file_directory "$wrap")"
    rev="$(wrap_file_revision "$wrap")"
    [ -n "$dir" ] && [ -n "$rev" ] || continue
    case "$dir" in
      gtk|glib) continue ;;
    esac
    discard_git_checkout_unless_revision "$ROOT_DIR/subprojects/$dir" "$rev"
  done
  for pin in "$ROOT_DIR/android/pixiewood-wraps/gtk/"*.wrap.pin; do
    [ -f "$pin" ] || continue
    dir="$(wrap_file_directory "$pin")"
    rev="$(wrap_file_revision "$pin")"
    [ -n "$dir" ] && [ -n "$rev" ] || continue
    discard_git_checkout_unless_revision "$ROOT_DIR/subprojects/$dir" "$rev"
    discard_git_checkout_unless_revision "$ROOT_DIR/subprojects/gtk/subprojects/$dir" "$rev"
  done
}

pin_gtk_nested_pango_wrap() {
  local src dest wrap pin
  src="$ROOT_DIR/android/pixiewood-wraps/gtk/pango.wrap.pin"
  dest="$ROOT_DIR/subprojects/gtk/subprojects/pango.wrap"

  if [ ! -f "$src" ]; then
    echo "pinned pango.wrap missing: $src" >&2
    exit 1
  fi
  if [ ! -d "$ROOT_DIR/subprojects/gtk/subprojects" ]; then
    echo "GTK nested subprojects dir missing; cannot pin pango." >&2
    exit 1
  fi
  for pin in "$ROOT_DIR/android/pixiewood-wraps/gtk/"*.wrap.pin; do
    [ -f "$pin" ] || continue
    cp -a "$pin" "$ROOT_DIR/subprojects/gtk/subprojects/$(basename "$pin" .pin)"
  done

  # CI restore-keys can keep subprojects/nested-pango.wrap from an earlier job
  # (Meson: Multiple wrap files provide pango).
  for wrap in "$ROOT_DIR/subprojects/"*.wrap; do
    [ -f "$wrap" ] || continue
    grep -q '^\[wrap-redirect\]' "$wrap" && continue
    if grep -qE '^pango[[:space:]]*=' "$wrap"; then
      echo "Removing extra top-level pango wrap: $wrap" >&2
      rm -f "$wrap"
    fi
  done
  discard_stale_pinned_checkouts
}

ensure_gtk_subproject_ready() {
  refuse_gtk_subproject_work "Preparing GTK subproject"
  ensure_gtk_subproject_checked_out
  gtk_subproject_is_complete ||
    { echo "GTK subproject checkout is incomplete." >&2; exit 1; }
  pin_gtk_nested_pango_wrap
  save_gtk_subproject_bootstrap || true
}

prepare_android_subprojects_before_meson() {
  refuse_gtk_subproject_work "Preparing Android subprojects (GTK bootstrap)"
  local wrap
  mkdir -p "$ROOT_DIR/subprojects"
  for wrap in "$ROOT_DIR/subprojects/"*.wrap; do
    [ -f "$wrap" ] || continue
    grep -q '^\[wrap-redirect\]' "$wrap" && continue
    if grep -qE '^pango[[:space:]]*=' "$wrap"; then
      echo "Removing extra top-level pango wrap: $wrap" >&2
      rm -f "$wrap"
    fi
  done
  discard_stale_pinned_checkouts
  ensure_gtk_subproject_ready
}
