#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VER="${SECCOMP_GIR_VERSION:-2.5}"
HEADER="${SECCOMP_HEADER:-/usr/include/seccomp.h}"

if ! [[ -r "$HEADER" ]]; then
	echo "Missing $HEADER — install libseccomp-dev" >&2
	exit 1
fi

echo "Using seccomp header: $HEADER"

g-ir-scanner --header-only \
	--namespace=Seccomp \
	--nsversion="${VER}" \
	--library=seccomp \
	--external-library \
	--pkg=libseccomp \
	--accept-unprefixed \
	"$HEADER" \
	-o "Seccomp-${VER}.gir"

RAW="seccomp-vapigen-raw.vapi"
vapigen --library seccomp-vapigen-raw -d . "Seccomp-${VER}.gir"

sed -i 's/Seccomp-'"${VER}"'.h/seccomp.h/g' "$RAW"

ROOT="$(cd "$DIR/../.." && pwd)"
echo "Wrote flat vapigen output → $PWD/$RAW (reference only)."
echo "Do not auto-merge into $ROOT/vapi/seccomp.vapi — that file is hand-maintained (OO Filter class)."
echo "Smoke test OO binding: valac --vapidir=$ROOT/vapi --pkg seccomp --Xcc=-lseccomp test-minimal.vala -o test-minimal && ./test-minimal"
