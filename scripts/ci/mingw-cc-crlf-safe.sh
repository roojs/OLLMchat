#!/usr/bin/env bash
# MinGW cc wrapper: strip CR from C sources before compile.
#
# Vala emits multi-line string literals as "…\n" \ continuations. If the
# generated .c is written/checked out with CRLF, `\` is no longer the last
# character before newline and GCC fails with "missing terminating \"" /
# "stray '\'" (often attributed to the .vala via #line).
set -euo pipefail

REAL_CC="${MINGW_CC_REAL:-cc}"
for arg in "$@"; do
	case "${arg}" in
	*.c | *.h)
		if [[ -f "${arg}" ]]; then
			sed -i 's/\r$//' "${arg}"
		fi
		;;
	esac
done
exec "${REAL_CC}" "$@"
