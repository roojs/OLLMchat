#!/usr/bin/env bash
# Cross-compile OLLMchat for Windows on Linux and stage a portable directory
# (no NSIS installer). Uses sqgipkg + MSYS2/MinGW, same stack as CI.
#
# Artifact layout (all gitignored; does not touch native Linux build/):
#   build-windows-x86_64/   meson + MinGW compile tree (sqgipkg.json)
#   dist-windows-x86_64/    portable win-dir bundle (ollmchat.exe + DLLs + launcher)
#   .sqgipkg/               sqgi install, MSYS2 package cache, native/faiss, etc.
#
# Usage:
#   scripts/build-windows-dir.sh
#   scripts/build-windows-dir.sh --clean
#   scripts/build-windows-dir.sh --wine --debug
#
# After build (from repo root):
#   wine dist-windows-x86_64/OLLMchat/OLLMchat.bat --debug
#   wine dist-windows-x86_64/OLLMchat/OLLMchat.exe
#
# Options:
#   --clean          Remove Windows build/dist dirs (sqgipkg --clean) and exit
#   --sysroot-only   Only prepare the Windows cross sysroot (sqgipkg --target win-sysroot)
#   --wine           Run the staged bundle under Wine after a successful build
#   --debug          Pass --windows-console so CLI flags print to a visible console
#   --install-sqgi   Rebuild and reinstall sqgi into .sqgipkg/host even if present
#   -h, --help       Show this help
#
# Environment:
#   SQGI_SOURCE_DIR   sqgi git checkout (default: ../sqgi, else clone to .sqgipkg/sqgi)
#   SQGI_PREFIX       Local sqgi install prefix (default: .sqgipkg/host)
#   WINEPREFIX        Wine prefix when using --wine (default: ~/.wine-ollmchat)

set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Must match sqgipkg.json windows.build_dir and library paths.
WIN_BUILD_DIR="build-windows-x86_64"
WIN_DIST_DIR="dist-windows-x86_64"

SQGI_PREFIX="${SQGI_PREFIX:-$ROOT/.sqgipkg/host}"
SQGI_BUILD="${SQGI_BUILD:-$ROOT/.sqgipkg/host/sqgi-build}"
SQGI_REPO="${SQGI_REPO:-https://github.com/supercamel/sqgi.git}"

TARGET="win-dir"
DO_CLEAN=0
DO_SYSROOT_ONLY=0
DO_WINE=0
DO_DEBUG=0
FORCE_INSTALL_SQGI=0

usage() {
	sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
}

log() {
	printf 'build-windows-dir: %s\n' "$*"
}

die() {
	printf 'build-windows-dir: error: %s\n' "$*" >&2
	exit 1
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

resolve_sqgi_source_dir() {
	if [[ -n "${SQGI_SOURCE_DIR:-}" ]]; then
		printf '%s' "$SQGI_SOURCE_DIR"
		return
	fi
	if [[ -d "$ROOT/../sqgi/.git" || -f "$ROOT/../sqgi/CMakeLists.txt" ]]; then
		printf '%s' "$(CDPATH= cd -- "$ROOT/../sqgi" && pwd)"
		return
	fi
	printf '%s' "$ROOT/.sqgipkg/sqgi"
}

ensure_sqgi_sources() {
	local src="$1"
	if [[ -f "$src/CMakeLists.txt" ]]; then
		log "using sqgi sources at $src"
		return
	fi
	need_cmd git
	log "cloning sqgi into $src"
	mkdir -p "$(dirname "$src")"
	git clone --depth 1 "$SQGI_REPO" "$src"
}

ensure_sqgi_installed() {
	local src="$1"
	local sqgipkg_bin="$SQGI_PREFIX/bin/sqgipkg"
	local sqgi_bin="$SQGI_PREFIX/bin/sqgi"

	if [[ "$FORCE_INSTALL_SQGI" -eq 0 && -x "$sqgipkg_bin" && -x "$sqgi_bin" ]]; then
		log "using sqgi from $SQGI_PREFIX"
		return
	fi

	need_cmd cmake
	need_cmd ninja
	[[ -f "$src/CMakeLists.txt" ]] || die "sqgi sources not found at $src"

	log "building sqgi into $SQGI_PREFIX"
	mkdir -p "$SQGI_BUILD" "$SQGI_PREFIX"
	cmake -S "$src" -B "$SQGI_BUILD" -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DSQ_ENABLE_JIT=ON \
		-DCMAKE_INSTALL_PREFIX="$SQGI_PREFIX"
	cmake --build "$SQGI_BUILD"
	cmake --install "$SQGI_BUILD"

	[[ -x "$sqgipkg_bin" ]] || die "sqgipkg not installed at $sqgipkg_bin"
	[[ -x "$sqgi_bin" ]] || die "sqgi not installed at $sqgi_bin"
}

ensure_host_deps() {
	need_cmd meson
	need_cmd ninja
	need_cmd pkg-config
	need_cmd x86_64-w64-mingw32-gcc
	need_cmd x86_64-w64-mingw32-g++
}

warn_linux_build_dir() {
	if [[ -d "$ROOT/build/meson-private" ]]; then
		log "note: native Linux build/ is separate from $WIN_BUILD_DIR (unchanged)"
	fi
}

run_sqgipkg() {
	local src="$1"
	shift
	local -a extra=("$@")
	local -a cmd=(
		sqgipkg
		--target "$TARGET"
		--output "$WIN_DIST_DIR"
		--sqgi-source-dir "$src"
	)

	if [[ "$DO_DEBUG" -eq 1 ]]; then
		cmd+=(--windows-console)
	fi

	PATH="$SQGI_PREFIX/bin:$PATH" "${cmd[@]}" "${extra[@]}"
}

win_bundle_dir() {
	printf '%s/%s' "$WIN_DIST_DIR" "OLLMchat"
}

print_run_commands() {
	local bundle
	bundle="$(win_bundle_dir)"
	[[ -d "$bundle" ]] || return

	printf '\n'
	printf '  wine %s/OLLMchat.bat --debug\n' "$bundle"
	printf '  wine %s/OLLMchat.exe\n' "$bundle"
	printf '\n'
}

run_wine() {
	local bundle bat
	bundle="$(win_bundle_dir)"
	bat="$bundle/OLLMchat.bat"
	[[ -f "$bat" ]] || die "launcher not found: $bat (run build first)"

	need_cmd wine
	export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-ollmchat}"
	mkdir -p "$WINEPREFIX"

	local -a wine_args=()
	if [[ "$DO_DEBUG" -eq 1 ]]; then
		wine_args+=(--debug)
	fi

	log "running under Wine (WINEPREFIX=$WINEPREFIX)"
	# .bat sets PATH, GI_TYPELIB_PATH, GDK_BACKEND=win32, etc. (do not run build-tree exe alone)
	wine cmd /c "$bat ${wine_args[*]}"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--clean)
			DO_CLEAN=1
			shift
			;;
		--sysroot-only)
			TARGET="win-sysroot"
			DO_SYSROOT_ONLY=1
			shift
			;;
		--wine)
			DO_WINE=1
			shift
			;;
		--debug)
			DO_DEBUG=1
			shift
			;;
		--install-sqgi)
			FORCE_INSTALL_SQGI=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		--)
			shift
			break
			;;
		*)
			die "unknown option: $1 (try --help)"
			;;
	esac
done

SQGI_SOURCE_DIR="$(resolve_sqgi_source_dir)"
export SQGI_SOURCE_DIR

warn_linux_build_dir

ensure_host_deps
ensure_sqgi_sources "$SQGI_SOURCE_DIR"
ensure_sqgi_installed "$SQGI_SOURCE_DIR"

if [[ "$DO_CLEAN" -eq 1 ]]; then
	log "cleaning Windows packaging artifacts"
	PATH="$SQGI_PREFIX/bin:$PATH" sqgipkg --clean --sqgi-source-dir "$SQGI_SOURCE_DIR"
	exit 0
fi

log "target=$TARGET build_dir=$WIN_BUILD_DIR output=$WIN_DIST_DIR"
run_sqgipkg "$SQGI_SOURCE_DIR"

if [[ "$DO_SYSROOT_ONLY" -eq 1 ]]; then
	log "win-sysroot ready (no application bundle staged)"
	exit 0
fi

log "done: $(win_bundle_dir)/"
print_run_commands

if [[ "$DO_WINE" -eq 1 ]]; then
	run_wine
fi
