#!/bin/bash
set -euo pipefail
# Fetch libllama/libggml .debs from Debian for systems where apt is too old.
# Installs core packages plus vulkan and blas backends. HIP (~1GB) is added only
# when ROCm is present. Debian has no NVIDIA CUDA backend package.

GGML_POOL="https://deb.debian.org/debian/pool/main/g/ggml"
LLAMA_POOL="https://deb.debian.org/debian/pool/main/l/llama.cpp"

ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
if [ -z "$ARCH" ]; then
  case "$(uname -m)" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) ARCH="$(uname -m)" ;;
  esac
fi

download_latest_deb() {
  local pool="$1"
  local package="$2"
  local out="/tmp/${package}.deb"

  local deb="$(
    curl -fsSL "$pool/" \
      | grep -oE "href=\"${package}_[^\"]+_${ARCH}\\.deb\"" \
      | sed 's/^href="//;s/"$//' \
      | sort -V \
      | tail -n1
  )"

  if [ -z "$deb" ]; then
    echo "Could not find ${package}_*_${ARCH}.deb under ${pool}" >&2
    exit 1
  fi

  echo "Downloading ${deb}" >&2
  curl -fsSL "$pool/$deb" -o "$out"
  printf '%s\n' "$out"
}

has_rocm() {
  [ -e /dev/kfd ] || command -v rocminfo >/dev/null 2>&1
}

sudo apt install -y curl

PACKAGES=(
  libggml0
  libggml-dev
  libllama0
  libllama-dev
  libggml0-backend-vulkan
  libggml0-backend-blas
)

if has_rocm; then
  echo "ROCm detected; including HIP backend."
  PACKAGES+=(libggml0-backend-hip)
else
  echo "No ROCm detected; skipping HIP backend."
fi

DEBS=()
for package in "${PACKAGES[@]}"; do
  pool="$GGML_POOL"
  if [[ "$package" == libllama* ]]; then
    pool="$LLAMA_POOL"
  fi
  DEBS+=("$(download_latest_deb "$pool" "$package")")
done

echo "Installing: ${DEBS[*]}"
sudo dpkg -i "${DEBS[@]}" || sudo apt-get install -f -y

MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
if [ -z "$MULTIARCH" ]; then
  case "$ARCH" in
    amd64) MULTIARCH="x86_64-linux-gnu" ;;
    arm64) MULTIARCH="aarch64-linux-gnu" ;;
    *) MULTIARCH="${ARCH}-linux-gnu" ;;
  esac
fi

LLAMA_LIBDIR="/usr/lib/${MULTIARCH}/llama"
LD_CONF="/etc/ld.so.conf.d/llama.conf"
if [ ! -f "$LD_CONF" ] || ! grep -qF "$LLAMA_LIBDIR" "$LD_CONF" 2>/dev/null; then
  echo "Registering ${LLAMA_LIBDIR} with ldconfig (libllama installs outside default search path)."
  echo "$LLAMA_LIBDIR" | sudo tee "$LD_CONF" >/dev/null
  sudo ldconfig
fi
