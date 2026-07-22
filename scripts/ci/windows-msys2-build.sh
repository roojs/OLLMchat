#!/usr/bin/env bash
# Native Windows (MSYS2 UCRT64) build for OLLMchat — used by GitHub Actions
# (.github/workflows/windows-build.yml) and local MSYS2 shells.
#
# Expects to run under UCRT64 bash.
# Order: FAISS (sqgipkg Windows recipe) → webview2-gtk → OLLMchat meson.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

WEBVIEW2GTK_DIR="${WEBVIEW2GTK_DIR:-${ROOT}/webview2-gtk}"
WEBVIEW2GTK_REPO="${WEBVIEW2GTK_REPO:-https://github.com/roojs/webview2-gtk.git}"
WEBVIEW2GTK_REF="${WEBVIEW2GTK_REF:-}"
WEBVIEW2GTK_STAGING="${WEBVIEW2GTK_STAGING:-${ROOT}/.ci-webview2gtk-prefix}"
FAISS_DIR="${FAISS_DIR:-${ROOT}/.ci-faiss/faiss}"
FAISS_REF="${FAISS_REF:-v1.8.0}"
FAISS_REPO="${FAISS_REPO:-https://github.com/facebookresearch/faiss.git}"
# Install into the UCRT64 prefix so Meson find_library('faiss') resolves
# without -Dwindows_prefix (that flag would also redirect tree-sitter lookup).
FAISS_PREFIX="${FAISS_PREFIX:-${MSYSTEM_PREFIX:-/ucrt64}}"
BUILD_DIR="${BUILD_DIR:-build-windows}"

# Vala → C on MinGW: normalize LF before valac, and wrap cc so generated
# .c with CRLF line-continuations still compile (see mingw-cc-crlf-safe.sh).
echo "==> normalize Vala sources to LF"
find "${ROOT}" \( -name '*.vala' -o -name '*.vapi' \) \
	! -path '*/webview2-gtk/*' \
	! -path '*/.ci-*/*' \
	! -path '*/build/*' \
	! -path '*/build-*/*' \
	-print0 | while IFS= read -r -d '' f; do
	sed -i 's/\r$//' "${f}"
done
export MINGW_CC_REAL="${MINGW_CC_REAL:-$(command -v cc)}"
export CC="${ROOT}/scripts/ci/mingw-cc-crlf-safe.sh"
chmod +x "${CC}"

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

# --- webview2-gtk ---
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
