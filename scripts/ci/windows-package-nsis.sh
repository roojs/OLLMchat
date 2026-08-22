#!/usr/bin/env bash
# Stage OLLMchat Windows portable tree and build OLLMchat-<version>-Setup.exe.
#
# "Portable tree" = intermediate folder of exe + DLLs that NSIS packs.
# Release asset is only the versioned Setup.exe (not a zip of that folder).
#
# Expects MSYS2 UCRT64 after scripts/ci/windows-msys2-build.sh.
#
# Usage:
#   ./scripts/ci/windows-package-nsis.sh
#   BUILD_DIR=build-windows ./scripts/ci/windows-package-nsis.sh
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

BUILD_DIR="${BUILD_DIR:-build-windows}"
STAGE="${STAGE:-${ROOT}/dist-windows/OLLMchat}"
OUT_DIR="${OUT_DIR:-${ROOT}/dist-windows}"
VERSION="$(grep -E "^[[:space:]]*version:" "${ROOT}/meson.build" | head -1 | sed -E "s/.*'([^']+)'.*/\1/")"
OUT_NAME="OLLMchat-${VERSION}-Setup.exe"
PREFIX="${MSYSTEM_PREFIX:-/ucrt64}"

EXE="${BUILD_DIR}/ollmapp/ollmchat.exe"
DAEMON="${BUILD_DIR}/ollmfilesd/ollmfilesd.exe"

if [[ ! -f "${EXE}" ]]; then
	echo "windows-package-nsis: missing ${EXE} — run scripts/ci/windows-msys2-build.sh first" >&2
	exit 1
fi
if [[ ! -f "${DAEMON}" ]]; then
	echo "windows-package-nsis: missing ${DAEMON}" >&2
	exit 1
fi
if ! command -v makensis >/dev/null 2>&1; then
	echo "windows-package-nsis: install NSIS: pacman -S mingw-w64-ucrt-x86_64-nsis" >&2
	exit 1
fi

if [[ -f "${OUT_DIR}/${OUT_NAME}" ]]; then
	echo "windows-package-nsis: refusing to overwrite ${OUT_NAME}" >&2
	echo "Bump version in meson.build (and CHANGELOG.md) first." >&2
	exit 1
fi

echo "==> stage ${STAGE}"
rm -rf "${STAGE}"
mkdir -p "${STAGE}"

cp -f "${EXE}" "${STAGE}/OLLMchat.exe"
cp -f "${DAEMON}" "${STAGE}/ollmfilesd.exe"

# Project shared libraries from the Meson build tree.
find "${BUILD_DIR}" -type f \( -name 'liboc*.dll' -o -name 'liboll*.dll' \) \
	-exec cp -f {} "${STAGE}/" \;

LOADER=""
for candidate in \
	"${PREFIX}/bin/WebView2Loader.dll" \
	"${PREFIX}/lib/WebView2Loader.dll"; do
	if [[ -f "${candidate}" ]]; then
		LOADER="${candidate}"
		break
	fi
done

chmod +x "${ROOT}/scripts/copy-exe-runtime-dlls.sh"
"${ROOT}/scripts/copy-exe-runtime-dlls.sh" "${STAGE}/OLLMchat.exe" "${STAGE}" "${LOADER}"
"${ROOT}/scripts/copy-exe-runtime-dlls.sh" "${STAGE}/ollmfilesd.exe" "${STAGE}" ""

mkdir -p "${OUT_DIR}"
WIN_SRC="$(cygpath -aw "${STAGE}")"
OUT_EXE="$(cygpath -aw "${OUT_DIR}/${OUT_NAME}")"
WIN_ICON="$(cygpath -aw "${ROOT}/pixmaps/org.roojs.ollmchat.ico")"

echo "==> NSIS ${OUT_NAME} (PRODUCT_VERSION=${VERSION})"
makensis \
	-DINST_SRC="${WIN_SRC}" \
	-DPRODUCT_VERSION="${VERSION}" \
	-DOUTFILE="${OUT_EXE}" \
	-DMUI_ICON="${WIN_ICON}" \
	-DMUI_UNICON="${WIN_ICON}" \
	"${ROOT}/packaging/windows/ollmchat.nsi"

ls -lh "${OUT_DIR}/${OUT_NAME}"
echo "==> done: ${OUT_DIR}/${OUT_NAME}"
