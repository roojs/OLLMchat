#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MESON_MIN_VERSION="${MESON_MIN_VERSION:-1.8.0}"
MESON_TOOLS_DIR="${MESON_TOOLS_DIR:-$ROOT_DIR/.android-tools/meson}"
MESON_WRAPPER="$MESON_TOOLS_DIR/bin/meson"

version_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" = "$1" ]
}

if command -v meson >/dev/null 2>&1 &&
   version_ge "$(meson --version)" "$MESON_MIN_VERSION"; then
  command -v meson
  exit 0
fi

mkdir -p "$MESON_TOOLS_DIR"

POOL="https://deb.debian.org/debian/pool/main/m/meson"
deb="$(curl -fsSL "$POOL/" \
  | grep -oE 'href="meson_[^"]+_all\.deb"' \
  | sed 's/^href="//;s/"$//' \
  | sort -V \
  | tail -n1)"
if [ -z "$deb" ]; then
  echo "Could not find meson_*_all.deb under $POOL" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
curl -fsSL "$POOL/$deb" -o "$tmpdir/meson.deb"
rm -rf "$MESON_TOOLS_DIR/root"
mkdir -p "$MESON_TOOLS_DIR/root" "$MESON_TOOLS_DIR/bin"
dpkg-deb -x "$tmpdir/meson.deb" "$MESON_TOOLS_DIR/root"

cat > "$MESON_WRAPPER" <<EOF
#!/usr/bin/env bash
export PYTHONPATH="$MESON_TOOLS_DIR/root/usr/lib/python3/dist-packages\${PYTHONPATH:+:\$PYTHONPATH}"
exec python3 "$MESON_TOOLS_DIR/root/usr/bin/meson" "\$@"
EOF
chmod +x "$MESON_WRAPPER"

"$MESON_WRAPPER" --version >&2
printf '%s\n' "$MESON_WRAPPER"
