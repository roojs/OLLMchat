#!/bin/sh
# Compile and run the inspector-port probe against the real Linux
# WebDriver.prepare and WebViewAuto sources. Exit 1 while an
# unauthenticated client can read or navigate the page. Exit 0 once
# that client cannot.
set -eu
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"
OUT="${INSPECTOR_PROBE_BIN:-/tmp/inspector-port-probe}"
valac \
	--pkg=gtk4 \
	--pkg=webkitgtk-6.0 \
	--pkg=gee-0.8 \
	--pkg=json-glib-1.0 \
	--pkg=gio-2.0 \
	-o "$OUT" \
	"$ROOT/tests/inspector-port/stubs.vala" \
	"$ROOT/tests/inspector-port/probe.vala" \
	"$ROOT/libocwebkit/WebDriverValue.vala" \
	"$ROOT/libocwebkit/linux/WebDriver.vala" \
	"$ROOT/libocwebkit/linux/WebViewAuto.vala"
export GDK_BACKEND="${GDK_BACKEND:-x11}"
export WEBKIT_DISABLE_DMABUF_RENDERER=1
exec xvfb-run -a "$OUT"
