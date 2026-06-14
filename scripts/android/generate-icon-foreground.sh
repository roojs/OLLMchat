#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SVG="$ROOT_DIR/pixmaps/scalable/apps/org.roojs.ollmchat.svg"
OUT="$ROOT_DIR/android/icon-foreground.xml"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

find_gradle_jar() {
  local pattern="$1"
  find "${HOME}/.gradle/caches" -name "$pattern" 2>/dev/null \
    | grep -v sources \
    | grep -v javadoc \
    | sort -V \
    | tail -n1
}

SDK_COMMON="$(find_gradle_jar 'sdk-common-*.jar')"
COMMON="$(find "${HOME}/.gradle/caches" -path '*instrumented-common-*.jar' 2>/dev/null | sort -V | tail -n1 || true)"
GUAVA="$(find_gradle_jar 'guava-*.jar')"

if [ -z "$SDK_COMMON" ] || [ -z "$COMMON" ] || [ -z "$GUAVA" ]; then
  echo "Missing Android Gradle jars for Svg2Avd." >&2
  echo "Build any Android Gradle project once, or install Android Studio." >&2
  exit 1
fi

if [ -f "$ROOT_DIR/.android-tools/gtk-android-builder/generate/Svg2Avd.java" ]; then
  cp "$ROOT_DIR/.android-tools/gtk-android-builder/generate/Svg2Avd.java" "$WORK/"
elif [ -f "/tmp/gtk-android-builder/generate/Svg2Avd.java" ]; then
  cp "/tmp/gtk-android-builder/generate/Svg2Avd.java" "$WORK/"
else
  git clone --depth 1 https://github.com/sp1ritCS/gtk-android-builder.git "$WORK/gtk-android-builder"
  cp "$WORK/gtk-android-builder/generate/Svg2Avd.java" "$WORK/"
fi

javac --release 11 -cp "$COMMON:$SDK_COMMON:$GUAVA" "$WORK/Svg2Avd.java"
java -cp "$COMMON:$SDK_COMMON:$GUAVA:$WORK" Svg2Avd "$SVG" > "$WORK/raw.xml"

python3 - "$WORK/raw.xml" "$OUT" <<'PY'
import sys
import xml.etree.ElementTree as ET

NS = {"android": "http://schemas.android.com/apk/res/android"}
ET.register_namespace("android", NS["android"])

raw_path, out_path = sys.argv[1:3]
tree = ET.parse(raw_path)
vector = tree.getroot()

src_w = float(vector.get(f"{{{NS['android']}}}viewportWidth"))
src_h = float(vector.get(f"{{{NS['android']}}}viewportHeight"))
target = 108.0
scale = min(target / src_w, target / src_h) * 0.72
draw_w = src_w * scale
draw_h = src_h * scale
tx = (target - draw_w) / 2.0
ty = (target - draw_h) / 2.0

out = ET.Element("vector")
out.set(f"{{{NS['android']}}}width", "108dp")
out.set(f"{{{NS['android']}}}height", "108dp")
out.set(f"{{{NS['android']}}}viewportWidth", "108")
out.set(f"{{{NS['android']}}}viewportHeight", "108")

group = ET.SubElement(out, "group")
group.set(f"{{{NS['android']}}}scaleX", f"{scale:.6f}")
group.set(f"{{{NS['android']}}}scaleY", f"{scale:.6f}")
group.set(f"{{{NS['android']}}}translateX", f"{tx:.6f}")
group.set(f"{{{NS['android']}}}translateY", f"{ty:.6f}")

for child in list(vector):
    group.append(child)

ET.ElementTree(out).write(
    out_path,
    encoding="utf-8",
    xml_declaration=True,
)
PY

echo "Wrote $OUT"
