#!/usr/bin/env bash
# PIXIEWOOD_USE_PIXIE=1 → GTK only from .pixiewood/pixie; no gtk.git, no bootstrap cache.
#
# ** DO NOT WORK AROUND THIS **
# Chat / pixie Android builds must not clone, patch, or edit GTK in-tree (no
# subprojects/gtk, no gtk-subproject-bootstrap, no gtkimcontextandroid.c hacks,
# no bypass env vars, no “just for local testing”). Fix the Knowles pixie package
# or pixie pins; use build-source-diff-apk.sh only when compiling GTK from source
# on purpose (PIXIEWOOD_USE_PIXIE unset).
# shellcheck shell=bash

pixie_gtk_no_workarounds_warning() {
  cat >&2 <<'EOF'

================================================================================
  DO NOT WORK AROUND PIXIEWOOD_USE_PIXIE=1
================================================================================
  GTK (and the rest of the pixie stack) must come from .pixiewood/pixie only.

  Never attempt:
    - checking out or patching subprojects/gtk or gtk.git
    - editing GTK C sources under .pixiewood/gtk-subproject-bootstrap
    - bypass flags, unsetting pixie on chat POC scripts, or skipping these checks
    - local IME / gtkimcontextandroid “fixes” in this repository

  Allowed: update android/pixie-gtk.pins + Knowles pixie releases; rebuild APK.
  Source GTK compile: scripts/android/build-source-diff-apk.sh (pixie off).
================================================================================

EOF
}

purge_gtk_subproject_trees() {
  local root="${ROOT_DIR:-}"
  [ -n "$root" ] || return 0
  rm -rf "$root/subprojects/gtk" "$root/.pixiewood/gtk-subproject-bootstrap"
}

refuse_gtk_subproject_work() {
  local what="${1:-GTK subproject checkout or patch}"
  if [ "${PIXIEWOOD_USE_PIXIE:-}" != 1 ]; then
    return 0
  fi
  purge_gtk_subproject_trees
  pixie_gtk_no_workarounds_warning
  echo "Stop: $what is forbidden when PIXIEWOOD_USE_PIXIE=1." >&2
  exit 1
}