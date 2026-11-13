#!/usr/bin/env bash
# Native Windows (MSYS2 UCRT64) build for OLLMchat — used by GitHub Actions
# (.github/workflows/windows-build.yml) and local MSYS2 shells.
#
# Expects to run under UCRT64 bash.
# Order: faiss pacman package → webview2gtk pacman package → OLLMchat meson.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FAISS_VERSION="${FAISS_VERSION:-1.16.0}"
FAISS_PKG_URL="${FAISS_PKG_URL:-https://github.com/roojs/faiss/releases/download/v${FAISS_VERSION}-win32/mingw-w64-ucrt-x86_64-faiss-${FAISS_VERSION}-1-any.pkg.tar.zst}"
BUILD_DIR="${BUILD_DIR:-build-windows}"

# Signed release from https://github.com/roojs/webview2-gtk — pin via env to bump.
WEBVIEW2GTK_VERSION="${WEBVIEW2GTK_VERSION:-0.6.7}"
WEBVIEW2GTK_PKG_URL="${WEBVIEW2GTK_PKG_URL:-https://github.com/roojs/webview2-gtk/releases/download/v${WEBVIEW2GTK_VERSION}/mingw-w64-ucrt-x86_64-webview2gtk-${WEBVIEW2GTK_VERSION}-1-any.pkg.tar.zst}"
WEBVIEW2GTK_KEY="${ROOT}/packaging/msys2/webview2gtk-packager.gpg"
WEBVIEW2GTK_FPR_FILE="${ROOT}/packaging/msys2/webview2gtk-packager.fpr"

# --- FAISS (prebuilt unsigned pacman package — download locally so pacman skips .sig) ---
FAISS_PKG_FILE="${ROOT}/.ci-faiss/$(basename "${FAISS_PKG_URL}")"
mkdir -p "$(dirname "${FAISS_PKG_FILE}")"
echo "==> download faiss ${FAISS_VERSION} -> ${FAISS_PKG_FILE}"
curl -fsSL -o "${FAISS_PKG_FILE}" "${FAISS_PKG_URL}"
echo "==> pacman -U faiss ${FAISS_VERSION}"
pacman -U --noconfirm "${FAISS_PKG_FILE}"

# --- webview2gtk (signed pacman package; key vendored — we trust this packager) ---
if [[ ! -f "${WEBVIEW2GTK_KEY}" || ! -f "${WEBVIEW2GTK_FPR_FILE}" ]]; then
	echo "missing vendored packager key: ${WEBVIEW2GTK_KEY} / ${WEBVIEW2GTK_FPR_FILE}" >&2
	exit 1
fi
WEBVIEW2GTK_FPR="$(tr -d '[:space:]' < "${WEBVIEW2GTK_FPR_FILE}")"
echo "==> trust webview2gtk packager key ${WEBVIEW2GTK_FPR} (from packaging/msys2/)"
pacman-key --init 2>/dev/null || true
if ! pacman-key --list-keys "${WEBVIEW2GTK_FPR}" &>/dev/null; then
	pacman-key --add "${WEBVIEW2GTK_KEY}"
	pacman-key --lsign-key "${WEBVIEW2GTK_FPR}"
fi

echo "==> pacman -U webview2gtk ${WEBVIEW2GTK_VERSION}"
pacman -U --noconfirm "${WEBVIEW2GTK_PKG_URL}"
pkg-config --modversion webview2gtk-1

# Pacman ships webview2gtk-1.vapi under $MSYSTEM_PREFIX/lib (not share/vala/vapi).
WEBVIEW2GTK_PREFIX="${WEBVIEW2GTK_PREFIX:-${MSYSTEM_PREFIX:-/ucrt64}}"

echo "==> meson setup OLLMchat (${BUILD_DIR})"
rm -rf "${BUILD_DIR}"
meson setup "${BUILD_DIR}" \
	-Ddocs=false \
	-Dexamples=false \
	-Dtests=false \
	-Dlocal_gguf=disabled \
	-Dwebview2gtk_prefix="${WEBVIEW2GTK_PREFIX}"

echo "==> meson compile"
meson compile -C "${BUILD_DIR}"

echo "==> done: ${BUILD_DIR}"
