#!/usr/bin/env bash
# Copy GTK/GLib toolchain DLLs required by a Windows .exe (for double-click / PowerShell run).
#
# Usage:
#   ./scripts/copy-exe-runtime-dlls.sh <exe> <out-dir> [WebView2Loader.dll]
set -euo pipefail

EXE_PATH="${1:?exe path}"
OUT_DIR="${2:?output directory}"
WEBVIEW2_LOADER="${3:-}"

if [[ ! -f "${EXE_PATH}" ]]; then
	echo "copy-exe-runtime-dlls: not found: ${EXE_PATH}" >&2
	exit 1
fi

mkdir -p "${OUT_DIR}"
# In-place bundling (CI: exe already in OUT_DIR) — skip same-file cp.
exe_base="$(basename "${EXE_PATH}")"
if [[ "$(cd "$(dirname "${EXE_PATH}")" && pwd -P)/${exe_base}" != "$(cd "${OUT_DIR}" && pwd -P)/${exe_base}" ]]; then
	cp -f "${EXE_PATH}" "${OUT_DIR}/"
fi

if [[ -n "${WEBVIEW2_LOADER}" && -f "${WEBVIEW2_LOADER}" ]]; then
	loader_base="$(basename "${WEBVIEW2_LOADER}")"
	if [[ "$(cd "$(dirname "${WEBVIEW2_LOADER}")" && pwd -P)/${loader_base}" != "$(cd "${OUT_DIR}" && pwd -P)/${loader_base}" ]]; then
		cp -f "${WEBVIEW2_LOADER}" "${OUT_DIR}/"
	fi
fi

trim() {
	local s="$1"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "${s}"
}

is_toolchain_path() {
	local path="$1"
	[[ "${path}" == *"/ucrt64/bin/"* ]] \
		|| [[ "${path}" == *"/mingw64/bin/"* ]] \
		|| [[ "${path}" == *"\\ucrt64\\bin\\"* ]] \
		|| [[ "${path}" == *"\\mingw64\\bin\\"* ]]
}

copy_resolved() {
	local path="$1"
	local dll
	dll="$(basename "${path}")"
	[[ -f "${OUT_DIR}/${dll}" ]] && return 0
	if [[ -f "${path}" ]]; then
		cp -f "${path}" "${OUT_DIR}/${dll}"
		return 0
	fi
	# ldd sometimes reports /ucrt64/bin/... — resolve via MSYS root.
	if [[ "${path}" == /ucrt64/bin/* ]]; then
		local msys_root="${MSYSTEM_PREFIX:-/ucrt64}"
		if [[ -f "${msys_root}/bin/${dll}" ]]; then
			cp -f "${msys_root}/bin/${dll}" "${OUT_DIR}/${dll}"
			return 0
		fi
	fi
	return 1
}

collect_ldd() {
	local target="$1"
	while IFS= read -r line; do
		case "${line}" in
			*" not found"*)
				local dll
				dll="$(trim "$(sed -n 's/^[[:space:]]*\([^[:space:]]*\).*/\1/p' <<< "${line}")")"
				copy_resolved "/ucrt64/bin/${dll}" || true
				;;
			*"=> "*)
				local path
				path="$(trim "$(sed -n 's/.*=>[[:space:]]*\([^[:space:]]*\).*/\1/p' <<< "${line}")")"
				path="${path//\\//}"
				if is_toolchain_path "${path}"; then
					copy_resolved "${path}" || true
				fi
				;;
		esac
	done < <(ldd "${target}" 2>&1 || true)
}

collect_ldd "${EXE_PATH}"

for _ in 1 2 3 4 5 6; do
	before="$(find "${OUT_DIR}" -maxdepth 1 -name '*.dll' | wc -l)"
	while IFS= read -r -d '' dll; do
		collect_ldd "${dll}"
	done < <(find "${OUT_DIR}" -maxdepth 1 -name '*.dll' -print0)
	after="$(find "${OUT_DIR}" -maxdepth 1 -name '*.dll' | wc -l)"
	[[ "${after}" -eq "${before}" ]] && break
done

echo "copy-exe-runtime-dlls: $(basename "${EXE_PATH}") -> ${OUT_DIR}/ (${after} DLLs)"
