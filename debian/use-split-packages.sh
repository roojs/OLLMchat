#!/bin/sh
# Switch active debian/ packaging to split library packages (for apt repository).
set -eu
cd "$(dirname "$0")"
rm -f ./*.install
cp split/control ./control
cp split/*.install ./
echo "Active packaging: split ($(ls -1 ./*.install | wc -l) install files)"
