# Creating Releases

Users install OLLMchat from the **[roojs package repositories](https://roojs.github.io/repos/)** (`apt-get` / `dnf` / `zypper`). GitHub keeps two Releases per version: the version tag (`v1.3.0`) has AppImage, Android, and the Windows NSIS installer (`OLLMchat-<version>-Setup.exe`); the matching `v1.3.0-packages` tag has the `.deb` / `.rpm` files. Publish creates the packages Release first, then the version tag, so the Releases page (newest `created_at` first) shows `v1.3.0`, then `v1.3.0-packages`, then older versions. GitHub’s **Latest** badge stays on the version tag.

For Debian package layout and local `.deb` builds, see [`debian/README`](../debian/README). RPM packaging lives under [`packaging/rpm/`](../packaging/rpm/).

## How it works

The [Release](../.github/workflows/release.yml) workflow (`name: Release`) runs when:

- a tag matching `v*` is pushed (run **`./scripts/release.sh`** — humans only; `v*-packages` is ignored), or
- **Release** is started manually from the GitHub Actions UI (**workflow_dispatch**).

To test **one** package family without waiting on the others, run the matching
`Release - …` workflow on your branch (same jobs Release uses; no publish):

| Actions name | File | Command |
|--------------|------|---------|
| **Release - Debian** | [`release-debian.yml`](../.github/workflows/release-debian.yml) | `gh workflow run release-debian.yml --ref <branch>` |
| **Release - Fedora** | [`release-fedora.yml`](../.github/workflows/release-fedora.yml) | `gh workflow run release-fedora.yml --ref <branch>` |
| **Release - openSUSE** | [`release-opensuse.yml`](../.github/workflows/release-opensuse.yml) | `gh workflow run release-opensuse.yml --ref <branch>` |
| **Release - AppImage** | [`release-appimage.yml`](../.github/workflows/release-appimage.yml) | `gh workflow run release-appimage.yml --ref <branch>` |
| **Release - Windows** | [`release-windows.yml`](../.github/workflows/release-windows.yml) | `gh workflow run release-windows.yml --ref <branch>` |
| **Release - Android** | [`release-android.yml`](../.github/workflows/release-android.yml) | `gh workflow run release-android.yml --ref <branch>` |

Ignore anything named **X - …** (sorts to the bottom). The `Release calls this`
ones are the real package-build jobs; **Release - Debian** (and the others) are
the buttons that start them. The rest are compile checks, docs publish, and PR
housekeeping.

CI then:

1. Builds **Debian** packages on Ubuntu 25.04 using the [roojs APT repo](https://roojs.github.io/repos/) for `libllama-dev`: split runtime/`-dev` libraries plus `ollmchat`, then a second **ollmchat-remote-only** all-in-one `.deb`.
2. Builds **RPMs** on **Fedora 44** (`.fc44.` filenames) and **openSUSE Tumbleweed** (no `.fc` tag) from the same spec.
3. Builds Linux AppImages with sqgipkg (Ubuntu 24.04; FAISS is built from source for those bundles).
4. Builds the **Windows** NSIS installer on `windows-latest` + MSYS2 UCRT64 ([`x-windows.yml`](../.github/workflows/x-windows.yml)) → **`OLLMchat-<version>-Setup.exe`**.
5. Builds the **Android** remote-chat POC APK (`ollmchat-android-v*-debug.apk`). A Pixiewood failure does not block the other packages.
6. On a tag push, publishes **two** GitHub Releases. Debian and RPM files go on `${tag}-packages` first (same commit, not marked Latest), then AppImage, Windows Setup.exe, and the APK (when Android succeeded) on the version tag so that tag appears above packages on the Releases page.

AppImage packaging is configured in [`sqgipkg.json`](../sqgipkg.json) (Linux only). Debian packaging lives under [`debian/`](../debian/). The RPM spec is [`packaging/rpm/ollmchat.spec`](../packaging/rpm/ollmchat.spec).

Fedora 44 is the RPM base. openSUSE uses the same spec; CI does **not** share one binary RPM between the two (Fedora dist tag vs Tumbleweed filename). The repos project already routes `.fcN.` files to `rpm/fcN/` and untagged RPMs to `rpm/tumbleweed/`.

### Debian vs RPM vs AppImage / Windows / Android

| Format | Architectures | libllama | Notes |
|--------|---------------|----------|-------|
| APT / `.deb` | amd64 | **split `ollmchat`**: yes · **ollmchat-remote-only**: no | Users: `apt-get update && apt-get install ollmchat` (or `libocrpc-dev`) after adding [the repo](https://roojs.github.io/repos/) |
| RPM | x86_64 | same split + remote-only | Fedora 44 and openSUSE Tumbleweed; FAISS on Fedora comes from the roojs repo (nicked from Tumbleweed) |
| AppImage | x86_64, aarch64 | No | Self-contained; remote backends only |
| Windows `.exe` | x86_64 | No | Native MSYS2 NSIS: **`OLLMchat-<version>-Setup.exe`** |
| Android `.apk` | arm64-v8a | No | Remote-chat POC; sideload from GitHub Releases |

Release `.deb` files use the **split** Debian layout (runtime libraries, `-dev` packages, `ollmchat`, `ollmchat-tools`, `ollmchat-doc`) plus a conflicting **ollmchat-remote-only** all-in-one package. See [`debian/README`](../debian/README). The RPM spec ships the same split (`libocrpc`, `libocrpc-devel`, …) for the GGUF build and a single `ollmchat-remote-only` RPM without libllama.

### Changelog (single source of truth)

Release notes live in [`CHANGELOG.md`](../CHANGELOG.md). `debian/changelog` and the RPM `%changelog` are **generated** from it — do not edit those by hand.

While developing, add bullets under **`## [Unreleased]`**. When the release is ready, rename that heading to the version (Keep a Changelog still uses brackets), for example `## [1.2.5-alpha] - Unreleased`.

Regenerate Debian packaging locally with:

```bash
./scripts/release/sync-debian-changelog.sh
```

**Tag push (via `scripts/release.sh`):**

1. CI reads the versioned heading, checks it matches the tag (`v1.2.5-alpha` → `1.2.5-alpha` → Debian/RPM `1.2.5~alpha-1`), and copies notes into Debian and RPM packaging **in the CI workspace**.
2. GitHub Release notes come from that same section (`scripts/release/render-release-notes.sh`), not from git commits. The version-tag notes start with a pointer to the [README Releases](../README.md#releases) install commands (APT / DNF / zypper) and to `${tag}-packages` for the `.deb` / `.rpm` files.
3. If the workflow **fails**, `CHANGELOG.md` on `main` is unchanged.
4. If it **succeeds**, CI runs **`finalize-changelog.sh`**, stamps the date on `[1.2.5-alpha]`, inserts a fresh `[Unreleased]` heading, regenerates `debian/changelog`, and commits to `main`.

Manual **workflow_dispatch** runs do **not** finalize the changelog.

Agents must not run `scripts/release.sh` (it refuses `CURSOR_AGENT=1` and must not be worked around).

## Making a release

1. **Finish the release on `main`.** Commit everything that should ship.

2. **Update `CHANGELOG.md`.** Put the notes under `## [1.2.5-alpha] - Unreleased` (version in the heading).

3. **Run the human-only release script:**

   ```bash
   ./scripts/release.sh
   ```

   It checks a clean tree, refuses an empty notes section, creates an annotated `v1.2.5-alpha` tag, and pushes the branch plus tag. Do not tag by hand unless you are doing the same checks.

   If CI failed for that version, commit the fix on `main` then retag:

   ```bash
   ./scripts/release.sh --retry
   ```

   That deletes the local and origin version tag **and** the matching `v*-packages` tag, then tags HEAD and pushes again. Existing GitHub Releases for those tags are updated (`gh release upload --clobber`), not recreated.

4. **Watch CI.** Open **Actions → Release** on GitHub and wait for Debian, Fedora, openSUSE, AppImage, Windows, Android, and Publish to finish.

5. **Check the releases** and [roojs.github.io/repos](https://roojs.github.io/repos/) after the repos publish job picks up the new GitHub assets. Distro files live on the `v*-packages` release; if the repos ingest currently only watches the version tag, point it at `-packages` as well.

   **Version tag** (`v1.3.0` — GitHub Latest):

   | File | Platform |
   |------|----------|
   | `OLLMchat-remote-only-x86_64.AppImage` | Linux 64-bit (Intel/AMD); remote backends only |
   | `OLLMchat-remote-only-aarch64.AppImage` | Linux 64-bit (ARM); remote backends only |
   | `OLLMchat-<version>-Setup.exe` | Windows installer (MSYS2 / WebView2); remote backends only |
   | `ollmchat-android-v*-debug.apk` | Android remote-chat POC (arm64; sideload) |

   **Packages tag** (`v1.3.0-packages`):

   | File | Platform |
   |------|----------|
   | `ollmchat_*.deb`, `liboc*_*.deb`, `liboll*_*.deb`, `ollmchat-remote-only_*.deb` | Debian/Ubuntu amd64 (split libs + app; remote-only is all-in-one) |
   | `libocrpc-*.rpm`, `liboc*-*.rpm`, `liboll*-*.rpm`, `ollmchat-*.fc44.*.rpm` | Fedora 44 (split libs + app; plus `ollmchat-remote-only`) |
   | same names without `.fc` | openSUSE Tumbleweed |

### Installing from the package repositories

Add the APT or DNF source from [roojs.github.io/repos](https://roojs.github.io/repos/), then:

```bash
sudo apt-get update && sudo apt-get install ollmchat
sudo dnf install ollmchat
sudo zypper install ollmchat
```

`ollmchat` and `ollmchat-remote-only` conflict; install one or the other. Split library packages (`libocrpc1`, `libocrpc-dev`, …) also conflict with `ollmchat-remote-only`.

## Manual builds (no release publish)

To rebuild **one** package family (the usual way to iterate on openSUSE, Debian, and so on):

1. Go to **Actions**.
2. Choose **Release - openSUSE** (or Debian / Fedora / AppImage / Windows / Android).
3. **Run workflow** on the branch you want to test.

To rebuild **everything** without tagging: **Actions → Release → Run workflow**.

Manual runs upload artifacts on that workflow run. **Publish** and **Finalize changelog** only run for tag pushes. Manual runs sync `debian/changelog` from `CHANGELOG.md` without promoting `[Unreleased]`.

## Local packaging (optional)

### AppImage (sqgipkg)

If you have sqgi installed locally:

```bash
# Linux x86_64 AppImage
sqgipkg --target appimage --appimage-arch x86_64

# Linux aarch64 AppImage
sqgipkg --target appimage --appimage-arch aarch64
```

Outputs land under `dist-linux-x86_64/` and `dist-linux-aarch64/` in the repo root.

### Windows (native MSYS2)

Do not use `sqgipkg --target win-nsis` — WebView2 cannot be cross-compiled from Linux.

Release CI builds on **`windows-latest`** + MSYS2 UCRT64 ([`x-windows.yml`](../.github/workflows/x-windows.yml)):

1. `scripts/ci/windows-msys2-build.sh` — FAISS + pinned webview2gtk pacman + meson compile
2. `scripts/ci/windows-package-nsis.sh` — stages `dist-windows/OLLMchat/` (exe + DLLs; intermediate only), then NSIS → **`OLLMchat-<version>-Setup.exe`**

Tagged releases attach that Setup.exe. Manual: **Release - Windows**. Compile-only smoke: **X - Native Windows MSYS2 compile**.

End users need the [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) (Evergreen). See [webview2-gtk deploying docs](https://github.com/roojs/webview2-gtk/blob/main/docs/deploying-windows.md).

### Debian packages

Build on Debian 13 (`trixie`) or Ubuntu 25.04+ (`plucky` / `questing` / `resolute`). Add the [roojs APT source](https://roojs.github.io/repos/) so `libllama-dev` resolves, then install build-depends and run `dpkg-buildpackage`. CI uses `scripts/ci/enable-roojs-apt.sh` for that first step.

```bash
sudo apt-get install build-essential devscripts debhelper meson ninja-build \
  pkg-config valac libgee-0.8-dev libglib2.0-dev \
  libjson-glib-dev libsoup-3.0-dev libxml2-dev libsqlite3-dev \
  libgtk-4-dev libgtksourceview-5-dev libadwaita-1-dev libsecret-1-dev gobject-introspection \
  libgirepository1.0-dev libtree-sitter-dev libseccomp-dev libgit2-glib-1.0-dev \
  libwebkitgtk-6.0-dev libatspi2.0-dev \
  libopenblas-dev liblapack-dev libfaiss-dev libllama-dev

dpkg-buildpackage -us -uc -b
```

The resulting `.deb` files are written to the parent directory. The default layout is **split** libraries plus `-dev` packages; see [`debian/README`](../debian/README).

### RPMs (Fedora 44 / openSUSE Tumbleweed)

On the target distro (or a matching container):

```bash
./scripts/ci/build-rpm.sh
```

Artifacts land in `artifacts/`. Fedora 44 CI enables the [roojs DNF repo](https://roojs.github.io/repos/) so `faiss-devel` is available (Fedora does not ship FAISS; Tumbleweed does). Do not build against Fedora 42.

## Re-uploading assets

If a release already exists for the tag, the workflow runs `gh release upload … --clobber`, so re-pushing the same tag after a fix will replace the attached files on the existing release.
