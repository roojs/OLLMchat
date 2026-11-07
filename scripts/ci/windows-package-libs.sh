#!/usr/bin/env bash
# Pack every OLLMchat library as an MSYS2 UCRT64 pacman package.
#
# Expects scripts/ci/windows-msys2-build.sh to have compiled BUILD_DIR.
# The library list is packaging/msys2/PKGBUILD _libs.
#
# Usage (MSYS2 UCRT64):
#   ./scripts/ci/windows-package-libs.sh
#   BUILD_DIR=build-windows ./scripts/ci/windows-package-libs.sh
#
# Output (one per library):
#   packaging/msys2/mingw-w64-ucrt-x86_64-lib<name>-<version>-1-any.pkg.tar.zst
#
# Install (unsigned — download, then pacman -U the local files):
#   pacman -U --noconfirm packaging/msys2/mingw-w64-ucrt-x86_64-lib*-any.pkg.tar.zst
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

BUILD_DIR="${BUILD_DIR:-build-windows}"
PKG_DIR="${ROOT}/packaging/msys2"
STAGE="${PKG_DIR}/prebuilt"
MAKEPKG="${MAKEPKG:-makepkg-mingw}"
PREFIX="${MSYSTEM_PREFIX:-/ucrt64}"

if [[ "${MSYSTEM:-}" != "UCRT64" ]]; then
	echo "windows-package-libs: MSYSTEM=${MSYSTEM:-unset}; run under MSYS2 UCRT64" >&2
	exit 1
fi
if ! command -v "${MAKEPKG}" >/dev/null 2>&1; then
	echo "windows-package-libs: ${MAKEPKG} not found (MSYS2 UCRT64; pacman -S base-devel)" >&2
	exit 1
fi

VERSION="$(grep -E "^[[:space:]]*version:" "${ROOT}/meson.build" | head -1 | sed -E "s/.*'([^']+)'.*/\1/")"
if [[ -z "${VERSION}" ]]; then
	echo "windows-package-libs: version missing from meson.build" >&2
	exit 1
fi

# Names come from PKGBUILD _libs so the package functions and the stage list match.
LIBS=()
in_libs=0
while IFS= read -r line; do
	if [[ "${line}" == "_libs=("* ]]; then
		in_libs=1
		continue
	fi
	if [[ "${in_libs}" -eq 1 ]]; then
		if [[ "${line}" == ")" ]]; then
			break
		fi
		line="${line%%#*}"
		line="${line//[[:space:]]/}"
		[[ -z "${line}" ]] && continue
		LIBS+=("${line}")
	fi
done < "${PKG_DIR}/PKGBUILD"
if ((${#LIBS[@]} == 0)); then
	echo "windows-package-libs: PKGBUILD _libs is empty" >&2
	exit 1
fi

# Empty means this Windows build does not emit a GIR (no vala_gir, or Linux-only).
# A name missing from the case is a packaging bug.
gir_for() {
	case "$1" in
		ocsqlite) printf '%s\n' OCSqlite-1.0.gir ;;
		ocmarkdown) printf '%s\n' OCMarkdown-1.0.gir ;;
		ocmarkdowngtk) printf '%s\n' OCMarkdownGtk-1.0.gir ;;
		ollmchat) printf '%s\n' OLLMchat-1.0.gir ;;
		octools) printf '%s\n' OLLMtools-1.0.gir ;;
		occoder) printf '%s\n' OLLMcoder-1.0.gir ;;
		ollmchatgtk) printf '%s\n' OLLMchatGtk-1.0.gir ;;
		ocrpc|ollamaweb|ochf|ocfiles|ocwebkit|ocvector2|ocbwrap|ocmcp) printf '\n' ;;
		*)
			echo "windows-package-libs: no gir decision for $1" >&2
			return 1
			;;
	esac
}

# One match. A missing or doubled build output stops the package.
require_one() {
	local pattern="$1"
	local label="$2"
	local match=""
	local count=0
	local f
	shopt -s nullglob
	for f in ${pattern}; do
		match="$f"
		count=$((count + 1))
	done
	shopt -u nullglob
	if [[ "${count}" -ne 1 ]]; then
		echo "windows-package-libs: expected one ${label} (${pattern}), found ${count}" >&2
		exit 1
	fi
	printf '%s\n' "${match}"
}

stage_lib() {
	local name="$1"
	local sub="${BUILD_DIR}/lib${name}"
	local pkgname="mingw-w64-ucrt-x86_64-lib${name}"
	local root="${STAGE}/${name}/ucrt64"
	local dll implib header vapi gir

	if ! grep -q "package_${pkgname}()" "${PKG_DIR}/PKGBUILD"; then
		echo "windows-package-libs: PKGBUILD has no package_${pkgname}" >&2
		exit 1
	fi

	dll="$(require_one "${sub}/lib${name}.dll" "lib${name}.dll")"
	implib="$(require_one "${sub}/lib${name}.dll.a" "lib${name}.dll.a")"
	header="$(require_one "${sub}/${name}.h" "${name}.h")"
	vapi="$(require_one "${sub}/${name}.vapi" "${name}.vapi")"
	gir="$(gir_for "${name}")"

	rm -rf "${STAGE}/${name}"
	install -Dm644 "${dll}" "${root}/bin/lib${name}.dll"
	install -Dm644 "${implib}" "${root}/lib/lib${name}.dll.a"
	install -Dm644 "${header}" "${root}/include/${name}.h"
	install -Dm644 "${vapi}" "${root}/share/vala/vapi/${name}.vapi"
	install -Dm644 "${ROOT}/LICENSE" "${root}/share/licenses/${pkgname}/LICENSE"
	if [[ -n "${gir}" ]]; then
		gir="$(require_one "${sub}/${gir}" "${gir}")"
		install -Dm644 "${gir}" "${root}/share/gir-1.0/$(basename "${gir}")"
	fi
}

for name in "${LIBS[@]}"; do
	stage_lib "${name}"
done

# FAISS is built from source into the UCRT64 prefix. It is not an MSYS2
# package, and libocvector2 will not load without its DLL.
if printf '%s\n' "${LIBS[@]}" | grep -qx 'ocvector2'; then
	faiss_dll=""
	for candidate in "${PREFIX}/bin/libfaiss.dll" "${PREFIX}/lib/libfaiss.dll"; do
		if [[ -f "${candidate}" ]]; then
			faiss_dll="${candidate}"
			break
		fi
	done
	if [[ -z "${faiss_dll}" ]]; then
		echo "windows-package-libs: libfaiss.dll not under ${PREFIX} (bin or lib)" >&2
		exit 1
	fi
	install -Dm644 "${faiss_dll}" "${STAGE}/ocvector2/ucrt64/bin/libfaiss.dll"
fi

echo "==> staged ${STAGE}"
find "${STAGE}" -type f -print | sort

rm -f "${PKG_DIR}"/mingw-w64-ucrt-x86_64-lib*-any.pkg.tar.zst \
	"${PKG_DIR}"/mingw-w64-ucrt-x86_64-lib*-any.pkg.tar.zst.sig
export OLLM_LIBS_PKGVER="${VERSION}"
export OLLM_LIBS_PREBUILT_DESTDIR="${STAGE}"

echo "==> ${MAKEPKG} ${#LIBS[@]} libraries ${VERSION}"
(
	cd "${PKG_DIR}"
	"${MAKEPKG}" -C -f --noconfirm --skipchecksums
)

missing=0
for name in "${LIBS[@]}"; do
	pkg="${PKG_DIR}/mingw-w64-ucrt-x86_64-lib${name}-${VERSION}-1-any.pkg.tar.zst"
	if [[ ! -f "${pkg}" ]]; then
		echo "windows-package-libs: missing ${pkg}" >&2
		missing=1
	fi
done
if [[ "${missing}" -ne 0 ]]; then
	ls -l "${PKG_DIR}"/*.pkg.tar.zst >&2 || true
	exit 1
fi
ls -lh "${PKG_DIR}"/mingw-w64-ucrt-x86_64-lib*-"${VERSION}"-1-any.pkg.tar.zst
echo "==> done (${#LIBS[@]} packages)"
