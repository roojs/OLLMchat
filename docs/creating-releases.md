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
8. On tag pushes, also runs the **Android APK** build in parallel (via a reusable workflow). When the APK is ready, CI uploads it to the same GitHub Release. Android failures do not block desktop publishing or changelog finalization.

AppImage and Windows packaging is configured in [`sqgipkg.json`](../sqgipkg.json). Debian packaging lives under [`debian/`](../debian/).

### Debian vs AppImage / Windows

| Format | Architectures | libllama | Notes |
|--------|---------------|----------|-------|
| AppImage | x86_64, aarch64 | No | Self-contained; remote backends only (`OLLMchat-remote-only-*.AppImage`) |
| `.deb` | amd64 | **ollmchat**: yes · **ollmchat-remote-only**: no | See [`debian/README`](../debian/README) |
| Windows `.exe` | x86_64 | No | NSIS installer via sqgipkg (`OLLMchat-remote-only-Setup.exe`) |

Release builds use the **monolithic** Debian layout (see [`debian/README`](../debian/README)): **`ollmchat_*.deb`** (with libllama) and **`ollmchat-remote-only_*.deb`**. Split library packages under `debian/split/` are for a future apt repository, not GitHub release downloads.

### Changelog (single source of truth)

Release notes for packaging live in [`CHANGELOG.md`](../CHANGELOG.md) at the repository root.
[`debian/changelog`](../debian/changelog) is **generated** from it — do not edit `debian/changelog` by hand.

While developing, add entries under **`## [Unreleased]`** in `CHANGELOG.md`, then regenerate:

```bash
./scripts/release/sync-debian-changelog.sh
```

**Tag push (release attempt):**

1. CI reads `[Unreleased]` and builds `.deb` files labelled with the tag version (e.g. `v1.2.5-alpha` → `1.2.5~alpha-1`). This happens **only in the CI workspace** — nothing is committed yet.
2. GitHub Release notes are rendered from the same `[Unreleased]` content (via `scripts/release/render-release-notes.sh`), not from git commits.
3. If the workflow **fails** (build error, publish error, etc.), `CHANGELOG.md` on `main` is unchanged. Fix the problem, push, and re-tag or re-run — you will not accumulate failed-release entries in the changelog history.
4. If the workflow **succeeds** (build + GitHub Release publish), CI runs **`finalize-changelog.sh`**, which promotes `[Unreleased]` to a dated `[1.2.5-alpha]` section, clears `[Unreleased]`, regenerates `debian/changelog`, and commits to `main`.

Manual **workflow_dispatch** runs use whatever is already in `CHANGELOG.md` (including `[Unreleased]`) and do **not** finalize the changelog.

## Making a release

1. **Finish the release on `main`.** Merge or commit everything that should ship.

2. **Update `CHANGELOG.md`.** Ensure `[Unreleased]` lists everything since the last release.

3. **Choose a tag name.** Use semantic versioning with a `v` prefix. Pre-releases use a suffix such as `-alpha`, for example `v1.2.5-alpha`. Tags must match `v*` or the workflow will not run automatically.

4. **Create and push the tag:**

   ```bash
   git tag v1.2.5-alpha;  git push origin --tags
   ```

   A lightweight tag is enough — CI triggers on the tag name. The GitHub Release **title** is the tag (e.g. `v1.2.5-alpha`); **notes** come from `CHANGELOG.md`, not from the tag or any `-m` message. You can add `-a` and `-m "…"` if you want a note in `git show v1.2.5-alpha`, but it does not affect the published release.

5. **Watch CI.** Open **Actions → Release** on GitHub and wait for the job to finish.

6. **Check the release.** When the workflow succeeds, GitHub should have a release named after the tag (for example `v1.2.5-alpha`) with these assets:

   | File | Platform |
   |------|----------|
   | `OLLMchat-remote-only-x86_64.AppImage` | Linux 64-bit (Intel/AMD); remote backends only |
   | `OLLMchat-remote-only-aarch64.AppImage` | Linux 64-bit (ARM); remote backends only |
   | `OLLMchat-remote-only-Setup.exe` | Windows installer; remote backends only |
   | `ollmchat_*.deb` | All-in-one package with local GGUF (Debian/Ubuntu amd64) |
   | `ollmchat-remote-only_*.deb` | All-in-one package without libllama (Debian/Ubuntu amd64) |
   | `ollmchat-android-v*-debug.apk` | Android remote chat POC (arm64 debug APK; may appear shortly after the desktop assets) |

   Release notes on GitHub come from the **`[Unreleased]`** section of `CHANGELOG.md` (not from commit messages).
   After a **successful** publish, that section is promoted to a dated version entry and committed to `main`.

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

Manual runs still upload build artifacts to the workflow run, but the **Publish release assets** and **Finalize changelog** steps only run for tag pushes. Manual runs sync `debian/changelog` from `CHANGELOG.md` without promoting `[Unreleased]`.

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
