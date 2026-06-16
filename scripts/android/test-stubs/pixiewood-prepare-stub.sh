#!/usr/bin/env bash
while [ "$1" = "-C" ]; do
  shift 2
done
if [ "$1" = "prepare" ]; then
  echo "STUB: pixiewood prepare succeeded"
  exit 0
fi
echo "STUB: unexpected pixiewood invocation: $*" >&2
exit 1
