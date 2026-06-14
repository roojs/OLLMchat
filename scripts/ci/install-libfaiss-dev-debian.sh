#!/usr/bin/env bash
# Install libfaiss-dev from Debian on hosts where apt is too old (e.g. Ubuntu 24.04).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POOL="https://deb.debian.org/debian/pool/main/f/faiss"

sudo apt-get install -y libblas-dev liblapack-dev libomp-dev

deb="$("$ROOT/scripts/ci/debian-pool-deb.sh" "$POOL" libfaiss-dev amd64 /tmp/libfaiss-dev.deb)"
echo "Using Debian package: $(basename "$deb")"
sudo apt-get install -y libfaiss1 || true
sudo dpkg -i /tmp/libfaiss-dev.deb || sudo apt-get install -f -y
