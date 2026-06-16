#!/usr/bin/env bash
# Verify broken GTK subproject caches are repaired from bootstrap before meson runs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
export ROOT_DIR

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

install_wraps() {
  local extra="$ROOT_DIR/android/pixiewood-wraps"
  mkdir -p "$ROOT_DIR/subprojects"
  local dep_dir wrap
  for dep_dir in "$extra"/*/; do
    for wrap in "$dep_dir"/*.wrap; do
      if [ -f "$wrap" ]; then
        cp -a "$wrap" "$ROOT_DIR/subprojects/"
      fi
    done
  done
}

install_wraps

# Seed a known-good GTK tree and bootstrap cache once.
prepare_android_subprojects_before_meson
if ! gtk_bootstrap_cache_is_valid; then
  echo "failed to seed GTK bootstrap cache" >&2
  exit 1
fi

# Broken cache: top-level gtk exists but nested wrap-redirect targets are missing.
rm -rf "$ROOT_DIR/subprojects/gtk"
mkdir -p "$ROOT_DIR/subprojects/gtk"
echo '# broken stub' > "$ROOT_DIR/subprojects/gtk/meson.build"

log="$(mktemp)"
if ! prepare_android_subprojects_before_meson > "$log" 2>&1; then
  echo "GTK repair failed; log:" >&2
  cat "$log" >&2
  exit 1
fi

grep -q 'Restoring GTK from bootstrap cache' "$log" ||
  { echo "expected bootstrap restore; log:" >&2; cat "$log" >&2; exit 1; }
grep -q 'Cloning GTK from gtk.wrap' "$log" &&
  { echo "should not re-clone when bootstrap cache is valid; log:" >&2; cat "$log" >&2; exit 1; }

if ! gtk_subproject_is_complete; then
  echo "GTK subproject still incomplete after bootstrap restore." >&2
  exit 1
fi

if [ ! -f "$(gtk_subproject_patch_marker)" ]; then
  echo "android-bugs.patch marker missing after bootstrap restore." >&2
  exit 1
fi

# With compile cache restored, setup must not call pixiewood prepare when GTK is fixed.
export CI=true
export PIXIEWOOD_SKIP_SUBPROJECTS_DOWNLOAD=1
export PIXIEWOOD_MANIFEST="$ROOT_DIR/android/pixiewood-chat-poc.xml"
export PIXIEWOOD_BUILD_DIR="$ROOT_DIR/.pixiewood/bin-aarch64"
export PIXIEWOOD="$ROOT_DIR/scripts/android/test-stubs/pixiewood-prepare-stub.sh"
mkdir -p "$(dirname "$PIXIEWOOD")"
cat > "$PIXIEWOOD" << 'STUB'
#!/usr/bin/env bash
while [ "$1" = "-C" ]; do shift 2; done
echo "pixiewood prepare must not run when compile cache is usable" >&2
exit 99
STUB
chmod +x "$PIXIEWOOD"

mkdir -p "$PIXIEWOOD_BUILD_DIR/meson-logs" "$ROOT_DIR/.pixiewood"
touch "$PIXIEWOOD_BUILD_DIR/build.ninja"
touch "$ROOT_DIR/.pixiewood/pixiewood.ini"
touch "$ROOT_DIR/.pixiewood/toolchain.cross"
echo 'Version: 1.8.0' > "$PIXIEWOOD_BUILD_DIR/meson-logs/meson-log.txt"
for pkg in gee-0.8 libsoup-3.0 json-glib-1.0 libxml-2.0 sqlite3; do
  mkdir -p "$PIXIEWOOD_BUILD_DIR/lib/pkgconfig"
  touch "$PIXIEWOOD_BUILD_DIR/lib/pkgconfig/$pkg.pc"
done

log="$(mktemp)"
if ! PIXIEWOOD_PHASE=setup "$ROOT_DIR/scripts/android/build-pixiewood-apk.sh" > "$log" 2>&1; then
  echo "build-pixiewood-apk.sh setup failed after GTK bootstrap restore; log:" >&2
  cat "$log" >&2
  exit 1
fi

grep -q 'pixiewood prepare must not run' "$log" &&
  { echo "prepare ran when compile cache should skip it; log:" >&2; cat "$log" >&2; exit 1; }

echo "gtk-subproject-readiness: OK"
