#!/bin/sh
# Generate OLLMfiles-1.0.gir without clobbering libocfiles build artifacts
# (valac --library=ocfiles -C would rewrite ocfiles.vapi / .c in place).
set -e
gir_out="$1"
header_out="$2"
shift 2
# Ninja cwd is the build dir; @INPUT@ paths are often relative (../libocfiles/…).
# Resolve path-like args to absolute before cd'ing into the temp workdir.
gir_out=$(realpath -m -- "$gir_out")
header_out=$(realpath -m -- "$header_out")
abs_args=
expect_dir=
for arg in "$@"; do
  if [ -n "$expect_dir" ]; then
    abs_args="$abs_args $(realpath -m -- "$arg")"
    expect_dir=
    continue
  fi
  case "$arg" in
    --vapidir|--girdir)
      abs_args="$abs_args $arg"
      expect_dir=1
      ;;
    *.vala|*.vapi|*.gs|*.c|*.h|/*|../*|./*)
      abs_args="$abs_args $(realpath -m -- "$arg")"
      ;;
    *)
      abs_args="$abs_args $arg"
      ;;
  esac
done
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
(
  cd "$workdir"
  # shellcheck disable=SC2086
  valac -C --debug $abs_args --header "$header_out" --gir "$(basename "$gir_out")"
  cp "$(basename "$gir_out")" "$gir_out"
)
