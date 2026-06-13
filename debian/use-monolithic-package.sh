#!/bin/sh
# Switch active debian/ packaging to the all-in-one ollmchat package (default).
set -eu
cd "$(dirname "$0")"
rm -f ./*.install
cp monolithic/control ./control
cp monolithic/ollmchat.install ./ollmchat.install
cp monolithic/not-installed ./not-installed
printf '%s\n' enabled > ./local-gguf
echo "Active packaging: monolithic (ollmchat .deb with local GGUF)"
