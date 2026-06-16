#!/usr/bin/env bash
# Cold-start the GTK fixes harness and print TLS/GIO lines.
#
#   scripts/android/adb-gtk-fixes-logcat.sh
#   scripts/android/adb-gtk-fixes-logcat.sh --no-restart
set -euo pipefail

PKG=org.roojs.ollmchat.gtkfixespoc
RESTART=1

if [ "${1:-}" = "--no-restart" ]; then
  RESTART=0
fi

if [ "$RESTART" = "1" ]; then
  adb logcat -c
  adb shell am force-stop "$PKG" 2>/dev/null || true
  sleep 1
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  sleep 6
fi

pid="$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)"
if [ -z "$pid" ]; then
  echo "App not running ($PKG). Install with:" >&2
  echo "  scripts/android/adb-install-gtk-fixes-poc.sh" >&2
  exit 1
fi

echo "=== filesDir gio/modules ==="
adb shell "run-as $PKG ls files/share/gio/modules/ 2>/dev/null" || true
echo "=== runtime tag ==="
adb shell "run-as $PKG cat files/share/ollmchat-android-runtime.tag 2>/dev/null" || true
echo "=== logcat (pid $pid) ==="
adb logcat -d --pid="$pid" | rg -i \
  'GIO|TLS|GDummy|Failed to load module|OLLMchat TLS|OLLMchat-GIO|gio-tls-backend|gioopenssl' \
  || true
