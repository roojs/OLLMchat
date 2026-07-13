#!/bin/sh
set -e
VALADOC_DIR="$1"
shift
valadoc "$@"
"$(dirname "$0")/fix-valadoc-index-links.sh" "$VALADOC_DIR/ollmchat/index.htm"
