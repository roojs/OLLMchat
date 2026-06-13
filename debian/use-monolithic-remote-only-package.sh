#!/bin/sh
# Switch active debian/ packaging to the remote-only all-in-one package.
set -eu
cd "$(dirname "$0")"
rm -f ./*.install
cp monolithic-remote-only/control ./control
cp monolithic-remote-only/ollmchat-remote-only.install ./ollmchat-remote-only.install
cp monolithic-remote-only/not-installed ./not-installed
printf '%s\n' disabled > ./local-gguf
echo "Active packaging: monolithic-remote-only (ollmchat-remote-only .deb)"
