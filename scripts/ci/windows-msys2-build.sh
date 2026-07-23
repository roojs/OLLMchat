#!/usr/bin/env bash
# Native Windows (MSYS2 UCRT64) build for OLLMchat — used by GitHub Actions
# (.github/workflows/windows-build.yml) and local MSYS2 shells.
#
# Expects to run under UCRT64 bash.
# Order: FAISS (sqgipkg Windows recipe) → webview2gtk pacman package → OLLMchat meson.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FAISS_DIR="${FAISS_DIR:-${ROOT}/.ci-faiss/faiss}"
FAISS_REF="${FAISS_REF:-v1.8.0}"
FAISS_REPO="${FAISS_REPO:-https://github.com/facebookresearch/faiss.git}"
# Install into the UCRT64 prefix so Meson find_library('faiss') resolves
# without -Dwindows_prefix (that flag would also redirect tree-sitter lookup).
FAISS_PREFIX="${FAISS_PREFIX:-${MSYSTEM_PREFIX:-/ucrt64}}"
BUILD_DIR="${BUILD_DIR:-build-windows}"

# Signed release from https://github.com/roojs/webview2-gtk — pin via env to bump.
WEBVIEW2GTK_VERSION="${WEBVIEW2GTK_VERSION:-0.3.3}"
WEBVIEW2GTK_PKG_URL="${WEBVIEW2GTK_PKG_URL:-https://github.com/roojs/webview2-gtk/releases/download/v${WEBVIEW2GTK_VERSION}/mingw-w64-ucrt-x86_64-webview2gtk-${WEBVIEW2GTK_VERSION}-1-any.pkg.tar.zst}"
WEBVIEW2GTK_KEY="${ROOT}/packaging/msys2/webview2gtk-packager.gpg"
WEBVIEW2GTK_FPR_FILE="${ROOT}/packaging/msys2/webview2gtk-packager.fpr"

# --- FAISS (same patches + cmake flags as sqgipkg.json windows.native_dependencies) ---
echo "==> FAISS ${FAISS_REF} -> ${FAISS_PREFIX}"
if [[ ! -d "${FAISS_DIR}/.git" ]]; then
	mkdir -p "$(dirname "${FAISS_DIR}")"
	git clone --depth 1 --branch "${FAISS_REF}" "${FAISS_REPO}" "${FAISS_DIR}"
fi
(
	cd "${FAISS_DIR}"
	# MinGW aligned allocation shim (sqgipkg)
	if ! grep -q 'MinGW aligned allocation shim' faiss/impl/platform_macros.h; then
		perl -0pi -e 's/#include <cstdio>/#include <cstdio>\n#if defined(_WIN32) && !defined(_MSC_VER)\n\/\/ MinGW aligned allocation shim.\n#include <cerrno>\n#include <malloc.h>\n#define posix_memalign(p, a, s) (((*(p)) = _aligned_malloc((s), (a))), *(p) ? 0 : errno)\n#define posix_memalign_free _aligned_free\n#endif/' \
			faiss/impl/platform_macros.h
	fi
	if ! grep -q 'ifndef posix_memalign_free' faiss/impl/platform_macros.h; then
		perl -0pi -e 's/#define posix_memalign_free free/#ifndef posix_memalign_free\n#define posix_memalign_free free\n#endif/' \
			faiss/impl/platform_macros.h
	fi
	if ! grep -q '#ifndef _WIN32' faiss/invlists/InvertedListsIOHook.cpp; then
		perl -0pi -e 's/#ifndef _MSC_VER/#ifndef _WIN32/g; s/#endif \/\/ !_MSC_VER/#endif \/\/ !_WIN32/g' \
			faiss/invlists/InvertedListsIOHook.cpp
	fi

	rm -rf build-windows-x86_64
	# Native UCRT64: no SQGI cross toolchain file.
	# GCC 16 treats faiss pointer→long casts as errors; -fpermissive matches
	# the looser MinGW sqgipkg historically used.
	cmake -S . -B build-windows-x86_64 -G Ninja \
		-DFAISS_ENABLE_GPU=OFF \
		-DFAISS_ENABLE_PYTHON=OFF \
		-DBUILD_TESTING=OFF \
		-DBUILD_SHARED_LIBS=ON \
		-DBLA_VENDOR=OpenBLAS \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_CXX_FLAGS=-fpermissive \
		-DCMAKE_INSTALL_PREFIX="${FAISS_PREFIX}"
	cmake --build build-windows-x86_64 --target faiss
	cmake --install build-windows-x86_64
)

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
