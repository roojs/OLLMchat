#!/usr/bin/env bash
# Simulate CI restoring a broken GTK subproject cache and verify the build
# script drops wrap trees and forces prepare before meson setup.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
export ROOT_DIR
export CI=true
export PIXIEWOOD_SKIP_SUBPROJECTS_DOWNLOAD=1
export PIXIEWOOD_MANIFEST="$ROOT_DIR/android/pixiewood-chat-poc.xml"
export PIXIEWOOD_BUILD_DIR="$ROOT_DIR/.pixiewood/bin-aarch64"
export PIXIEWOOD_PHASE=setup

# Stub pixiewood prepare so we can test ordering without a full SDK setup.
export PIXIEWOOD="$ROOT_DIR/scripts/android/test-stubs/pixiewood-prepare-stub.sh"
mkdir -p "$(dirname "$PIXIEWOOD")"
cat > "$PIXIEWOOD" << 'STUB'
#!/usr/bin/env bash
while [ "$1" = "-C" ]; do
  shift 2
done
if [ "$1" = "prepare" ]; then
  echo "STUB: pixiewood prepare succeeded"
  exit 0
fi
echo "STUB: unexpected pixiewood invocation: $*" >&2
exit 1
STUB
chmod +x "$PIXIEWOOD"

# Fake a compile cache hit so needs_pixiewood_prepare would normally skip prepare.
mkdir -p "$PIXIEWOOD_BUILD_DIR/meson-logs"
touch "$PIXIEWOOD_BUILD_DIR/build.ninja"
mkdir -p "$ROOT_DIR/.pixiewood"
touch "$ROOT_DIR/.pixiewood/pixiewood.ini"
touch "$ROOT_DIR/.pixiewood/toolchain.cross"
echo 'Version: 1.8.0' > "$PIXIEWOOD_BUILD_DIR/meson-logs/meson-log.txt"

# Chat POC prefix markers so needs_pixiewood_prepare stays false.
mkdir -p "$PIXIEWOOD_BUILD_DIR/lib/pkgconfig"
for pkg in gee-0.8 libsoup-3.0 json-glib-1.0 libxml-2.0 sqlite3; do
  touch "$PIXIEWOOD_BUILD_DIR/lib/pkgconfig/$pkg.pc"
done

# Broken cache: gtk directory exists but nested wraps were never extracted.
rm -rf "$ROOT_DIR/subprojects/gtk"
mkdir -p "$ROOT_DIR/subprojects/gtk"
echo '# broken stub' > "$ROOT_DIR/subprojects/gtk/meson.build"

log="$(mktemp)"
if ! "$ROOT_DIR/scripts/android/build-pixiewood-apk.sh" > "$log" 2>&1; then
  echo "build-pixiewood-apk.sh setup failed; log:" >&2
  cat "$log" >&2
  exit 1
fi

grep -q 'GTK subproject incomplete' "$log" ||
  { echo "expected incomplete-GTK message; log:" >&2; cat "$log" >&2; exit 1; }
grep -q 'STUB: pixiewood prepare succeeded' "$log" ||
  { echo "expected forced prepare; log:" >&2; cat "$log" >&2; exit 1; }
grep -q 'Skipping Meson subprojects download' "$log" &&
  { echo "must not skip download on broken cache; log:" >&2; cat "$log" >&2; exit 1; }

echo "gtk-subproject-readiness: OK"
