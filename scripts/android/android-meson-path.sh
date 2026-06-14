#!/usr/bin/env bash

# Hide host g-ir-scanner from Android cross Meson builds without removing
# /usr/bin from PATH (which would break bash, python3, etc.).

android_meson_path() {
  local root_dir hide_dir
  root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  hide_dir="$root_dir/.android-tools/hidden-gi"
  mkdir -p "$hide_dir"
  if [ ! -x "$hide_dir/g-ir-scanner" ]; then
    cat > "$hide_dir/g-ir-scanner" <<'EOF'
#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "0.0.0"
  exit 0
fi
echo "g-ir-scanner is disabled for Android cross builds" >&2
exit 1
EOF
    chmod +x "$hide_dir/g-ir-scanner"
  fi
  printf '%s:%s\n' "$hide_dir" "${PATH:-}"
}

with_android_meson_path() {
  local old_path="$PATH"
  PATH="$(android_meson_path)"
  "$@"
  PATH="$old_path"
}
