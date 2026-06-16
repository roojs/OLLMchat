#!/usr/bin/env bash
while [ "$1" = "-C" ]; do shift 2; done
echo "pixiewood prepare must not run when compile cache is usable" >&2
exit 99
