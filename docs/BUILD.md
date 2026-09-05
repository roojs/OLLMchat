# Building OLLMchat

Build from source with Meson and Ninja. For day-to-day use, install the
`ollmchat` package from the [roojs repositories](https://roojs.github.io/repos/)
instead — see [README.md](../README.md).

Agents changing this project should also follow [`docs/build-rules.md`](build-rules.md).
**Do not** call `valac` directly — always build with Meson/Ninja.

## Dependencies (Debian / Ubuntu)

Use **Debian 13** (`trixie`) or **Ubuntu 25.04+** (`plucky` / `questing` /
`resolute`). Ubuntu 24.04 is not a published [roojs APT](https://roojs.github.io/repos/)
suite.

Add that APT source from [the repos page](https://roojs.github.io/repos/) so
`libllama-dev` and tree-sitter language parsers resolve (`libfaiss-dev` is
already in Debian 13 / Ubuntu 25.04+). GitHub Actions uses
`scripts/ci/enable-roojs-apt.sh` for the same step.

```bash
sudo apt install \
  meson \
  ninja-build \
  valac \
  valadoc \
  libgee-0.8-dev \
  libglib2.0-dev \
  libgtk-4-dev \
  libgtksourceview-5-dev \
  libadwaita-1-dev \
  libsecret-1-dev \
  libwebkitgtk-6.0-dev \
  libwebkitgtk-6.0-webdriver-dev \
  libatspi2.0-dev \
  libsoup-3.0-dev \
  libjson-glib-dev \
  libxml2-dev \
  libsqlite3-dev \
  libgit2-glib-1.0-dev \
  libseccomp-dev \
  gobject-introspection \
  libgirepository1.0-dev \
  libomp-dev \
  libblas-dev \
  liblapack-dev \
  libopenblas-dev \
  libfaiss-dev \
  libllama-dev \
  libtree-sitter-dev \
  desktop-file-utils \
  bubblewrap \
  build-essential \
  pkg-config
```

- **libwebkitgtk-6.0-dev** + **libwebkitgtk-6.0-webdriver-dev** / **libatspi2.0-dev** — Linux browser tool (`libocwebkit`; runtime **`libwebkitgtk-6.0-webdriver4`** from roojs APT). Configure probes interactions via `scripts/meson/check-webkit-interactions.sh` (see webkitgtk-automation `docs/consuming.md`)
- **libseccomp-dev** — sandbox syscall reporting (`libocbwrap`)
- **libsecret-1-dev** — sudo password keyring (`OLLMchatGtk.Sudo`, Linux)
- **bubblewrap** — `bwrap` for sandboxed `run_command` and MCP stdio servers
- **libblas-dev** / **liblapack-dev** / **libopenblas-dev** — required to link
  FAISS. Meson accepts either OpenBLAS or the reference BLAS/LAPACK packages;
  install all three so setup does not fail if one provider is missing. A
  configure line `Library openblas found: NO` is fine only when `blas`/`lapack`
  were found instead.

On Fedora 44, after adding the DNF repo from that page, install matching
`-devel` packages. `faiss-devel` is in the repo; `llama-cpp-devel` is already
in Fedora.

## Optional: tree-sitter parsers (code search)

Install parsers for the languages you want to index from the
[roojs APT repository](https://roojs.github.io/repos/):

```bash
sudo apt-get install \
  libtree-sitter-bash libtree-sitter-c-sharp libtree-sitter-cpp \
  libtree-sitter-go libtree-sitter-java libtree-sitter-javascript \
  libtree-sitter-markdown libtree-sitter-php libtree-sitter-python \
  libtree-sitter-rpmspec libtree-sitter-ruby libtree-sitter-rust \
  libtree-sitter-vala
```

On Fedora 44, `dnf install` the same `libtree-sitter-*` names.

## Optional: Ollama models (vector search)

Download through the settings dialog, or:

```bash
ollama pull bge-m3:latest
ollama pull qwen3-coder:30b
```

MCP servers are optional. See [MCP server settings](mcp-settings.md).

## Build and run

```bash
meson setup build --prefix=/usr
ninja -C build
```

Default `local_gguf` is `auto` (builds the GGUF backend when libllama is found).
Remote-only: `-Dlocal_gguf=disabled`. Force GGUF: `-Dlocal_gguf=enabled`.

After code changes:

```bash
meson setup --reconfigure build
ninja -C build
```

Executables use `build_rpath` so they find libraries in the build tree.
Wrapper scripts in `build/` set library paths; `ollmchat` is `build/ollmchat.bin`.

```bash
./build/ollmchat.bin
./build/ollmchat-cli --help
```

## Install (optional)

```bash
sudo meson install -C build
```

For day-to-day testing, running from `build/` is enough.

## Other builds

- Debian packages: [`debian/README`](../debian/README)
- Releases / RPM / AppImage / Windows: [Creating releases](creating-releases.md)
- Android: [Android build](android-build.md)
