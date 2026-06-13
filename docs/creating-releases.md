# Creating Releases

OLLMchat publishes installable builds through **GitHub Releases**, driven by **git tags**. Pushing a version tag starts CI, which builds the binaries and attaches them to a release on GitHub.

For more detail on the Debian package layout and local builds, see [README.packaging.md](../README.packaging.md).

## How it works

The [Release workflow](../.github/workflows/release.yml) runs when:

- a tag matching `v*` is pushed (for example `v1.0.3-alpha`), or
- the workflow is started manually from the GitHub Actions UI (**workflow_dispatch**).

On **ubuntu-24.04**, CI:

1. Checks out OLLMchat and [sqgi](https://github.com/supercamel/sqgi) (runtime + `sqgipkg`).
2. Installs build dependencies (Meson, Vala, cross-compilers, OpenBLAS, FAISS, and so on).
3. Builds and installs sqgi.
4. Runs `sqgipkg` to produce:
   - Linux **x86_64** AppImage
   - Linux **aarch64** AppImage
   - Windows **NSIS** installer (`.exe`)
5. Runs `dpkg-buildpackage` to produce **Debian packages** (amd64 only — see below).
6. Uploads the artifacts to the workflow run.
7. If the run was triggered by a tag push, creates or updates the matching **GitHub Release** and uploads the files as release assets.

AppImage and Windows packaging is configured in [`sqgipkg.json`](../sqgipkg.json). Debian packaging lives under [`debian/`](../debian/).

### Debian vs AppImage / Windows

| Format | Architectures | libllama | Notes |
|--------|---------------|----------|-------|
| AppImage | x86_64, aarch64 | No | Self-contained; remote backends only (`OLLMchat-remote-only-*.AppImage`) |
| `.deb` | amd64 | **ollmchat**: yes · **ollmchat-remote-only**: no | See [`debian/README`](../debian/README) |
| Windows `.exe` | x86_64 | No | NSIS installer via sqgipkg (`OLLMchat-remote-only-Setup.exe`) |

Release builds use the **monolithic** Debian layout (see [`debian/README`](../debian/README)): **`ollmchat_*.deb`** (with libllama) and **`ollmchat-remote-only_*.deb`**. Split library packages under `debian/split/` are for a future apt repository, not GitHub release downloads.

## Making a release

1. **Finish the release on `main`.** Merge or commit everything that should ship.

2. **Choose a tag name.** Use semantic versioning with a `v` prefix. Pre-releases use a suffix such as `-alpha`, for example `v1.0.3-alpha`. Tags must match `v*` or the workflow will not run automatically.

3. **Create and push an annotated tag:**

   ```bash
   git tag -a v1.0.3-alpha -m "Release 1.0.3 alpha"
   git push origin v1.0.3-alpha
   ```

4. **Watch CI.** Open **Actions → Release** on GitHub and wait for the job to finish.

5. **Check the release.** When the workflow succeeds, GitHub should have a release named after the tag (for example `v1.0.3-alpha`) with these assets:

   | File | Platform |
   |------|----------|
   | `OLLMchat-remote-only-x86_64.AppImage` | Linux 64-bit (Intel/AMD); remote backends only |
   | `OLLMchat-remote-only-aarch64.AppImage` | Linux 64-bit (ARM); remote backends only |
   | `OLLMchat-remote-only-Setup.exe` | Windows installer; remote backends only |
   | `ollmchat_*.deb` | All-in-one package with local GGUF (Debian/Ubuntu amd64) |
   | `ollmchat-remote-only_*.deb` | All-in-one package without libllama (Debian/Ubuntu amd64) |

   Release notes are generated automatically from commits since the previous tag.

   On tag pushes, CI also updates `debian/changelog` to match the tag (for example `v1.0.3-alpha` → `1.0.3~alpha-1`) before building the `.deb` files.

### Installing Debian packages from a release

Download **`ollmchat_*.deb`** (local GGUF via libllama) or **`ollmchat-remote-only_*.deb`** (remote backends only) from the release. The two packages conflict; install one or the other.

With libllama:

```bash
sudo apt install ./ollmchat_*.deb
```

Remote only:

```bash
sudo apt install ./ollmchat-remote-only_*.deb
```

Alternatively:

```bash
sudo dpkg -i ollmchat_*.deb    # or ollmchat-remote-only_*.deb
sudo apt install -f
```

## Manual builds (no release publish)

To rebuild the same artifacts without creating a GitHub Release:

1. Go to **Actions → Release → Run workflow**.
2. Run on the branch or tag you want to test.

Manual runs still upload build artifacts to the workflow run, but the **Publish release assets** step only runs for tag pushes. Manual runs use the version already in `debian/changelog`.

## Local packaging (optional)

### AppImage / Windows (sqgipkg)

If you have sqgi installed locally:

```bash
# Linux x86_64 AppImage
sqgipkg --target appimage --appimage-arch x86_64

# Linux aarch64 AppImage
sqgipkg --target appimage --appimage-arch aarch64

# Windows installer (fetch emoji font first — gitignored, required by sqgipkg.json)
./scripts/fetch-noto-color-emoji-font.sh
sqgipkg --target win-nsis
```

Outputs land under `dist-linux-x86_64/`, `dist-linux-aarch64/`, and `dist-windows-x86_64/` in the repo root.

### Debian packages

Ubuntu does not ship a suitable `libfaiss-dev`; install the current Debian amd64 package first (same as CI and [deploy-docs.yml](../.github/workflows/deploy-docs.yml)):

```bash
sudo apt-get install -y libblas-dev liblapack-dev libomp-dev
POOL="https://deb.debian.org/debian/pool/main/f/faiss"
deb=$(curl -fsSL "$POOL/" \
  | grep -oE 'href="libfaiss-dev_[^"]+_amd64\.deb"' \
  | sed 's/^href="//;s/"$//' \
  | sort -V \
  | tail -n1)
curl -fsSL "$POOL/${deb}" -o /tmp/libfaiss-dev.deb
sudo apt-get install -y libfaiss1 || true
sudo dpkg -i /tmp/libfaiss-dev.deb || sudo apt-get install -f -y

sudo apt-get install build-essential devscripts debhelper meson ninja-build \
  pkg-config valac libgee-0.8-dev libglib2.0-dev libgobject-2.0-dev \
  libgio-2.0-dev libjson-glib-dev libsoup-3.0-dev libxml2-dev libsqlite3-dev \
  libgtk-4-dev libgtksourceview-5-dev libadwaita-1-dev gobject-introspection \
  libgirepository1.0-dev libtree-sitter-dev libseccomp-dev libgit2-glib-1.0-dev \
  libopenblas-dev liblapack-dev

dpkg-buildpackage -us -uc -b
```

The resulting `.deb` files are written to the parent directory. See [README.packaging.md](../README.packaging.md) for package descriptions and troubleshooting.

## Re-uploading assets

If a release already exists for the tag, the workflow runs `gh release upload … --clobber`, so re-pushing the same tag after a fix will replace the attached files on the existing release.
