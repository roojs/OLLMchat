#!/usr/bin/env bash
# Native Windows (MSYS2 UCRT64) build for OLLMchat — used by GitHub Actions
# (.github/workflows/windows-build.yml) and local MSYS2 shells.
#
# Expects to run under UCRT64 bash. Builds webview2-gtk into a staging prefix,
# then configures and compiles OLLMchat with -Dlocal_gguf=disabled.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

WEBVIEW2GTK_DIR="${WEBVIEW2GTK_DIR:-${ROOT}/webview2-gtk}"
WEBVIEW2GTK_REPO="${WEBVIEW2GTK_REPO:-https://github.com/roojs/webview2-gtk.git}"
WEBVIEW2GTK_REF="${WEBVIEW2GTK_REF:-}"
WEBVIEW2GTK_STAGING="${WEBVIEW2GTK_STAGING:-${ROOT}/.ci-webview2gtk-prefix}"
BUILD_DIR="${BUILD_DIR:-build-windows}"

echo "==> webview2-gtk source: ${WEBVIEW2GTK_DIR}"
if [[ ! -f "${WEBVIEW2GTK_DIR}/meson.build" ]]; then
	git clone --depth 1 ${WEBVIEW2GTK_REF:+--branch "${WEBVIEW2GTK_REF}"} \
		"${WEBVIEW2GTK_REPO}" "${WEBVIEW2GTK_DIR}"
fi

echo "==> build + install webview2-gtk -> ${WEBVIEW2GTK_STAGING}"
(
	cd "${WEBVIEW2GTK_DIR}"
	./scripts/vendor-webview2-sdk.sh
	rm -rf build
	meson setup build --prefix="${WEBVIEW2GTK_STAGING}"
	meson compile -C build
	meson install -C build
)

export PKG_CONFIG_PATH="${WEBVIEW2GTK_STAGING}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
echo "==> PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
pkg-config --modversion webview2gtk-1

echo "==> meson setup OLLMchat (${BUILD_DIR})"
rm -rf "${BUILD_DIR}"
meson setup "${BUILD_DIR}" \
	-Ddocs=false \
	-Dexamples=false \
	-Dtests=false \
	-Dlocal_gguf=disabled \
	-Dwebview2gtk_prefix="${WEBVIEW2GTK_STAGING}"

echo "==> meson compile"
meson compile -C "${BUILD_DIR}"

echo "==> done: ${BUILD_DIR}"
