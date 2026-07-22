# Android build

How to build the OLLMchat Android remote chat POC locally and in GitHub Actions,
plus background on what is implemented today versus the full desktop application.

**Current port status:** [`docs/plans/done/9.0-DONE-android-poc-summary.md`](plans/done/9.0-DONE-android-poc-summary.md) — archived POC summary. **Open completion backlog:** [`docs/bugs/2026-07-18-android-poc-completion.md`](bugs/2026-07-18-android-poc-completion.md).

## Summary

Running the full application on Android is possible in principle, because GTK 4
has an Android backend, but it is not currently feasible as a small packaging or
CI change. The repository is a desktop Vala/GTK application with Linux and
Windows release packaging. Android would require a porting track covering the
UI, native dependency stack, packaging, and several Linux-specific runtime
features.

The practical near-term path is:

1. Keep Android as an experimental investigation.
2. Build and test the existing remote-only desktop configuration in CI.
3. Ship a stripped-down Android proof-of-concept that avoids the desktop window
   and its tool/project/vector setup.
4. Treat GGUF/libllama as optional for mobile and disable it for early Android
   experiments.

The current Android deliverable is the **remote chat POC** packaged as a debug
APK through Pixiewood. A separate GTK-only shell POC remains available locally
for minimal backend validation.

## Current application shape

OLLMchat is built with Meson and Vala. The main application uses GTK 4,
Libadwaita, and GtkSourceView. The project also builds reusable libraries for
LLM API access, markdown rendering, project/file management, MCP tools, vector
search, and the GTK chat UI.

The existing release automation builds:

- Linux AppImages for x86_64 and aarch64
- Debian packages for amd64
- a Windows NSIS installer

The repository includes a Pixiewood-based Android packaging path. Pixiewood
generates the Gradle project, Android manifest, and Android NDK cross files
under `.pixiewood/` at build time.

## Minimal Android proof of concept

### Remote chat POC (primary)

The Android target is `ollmchat-android-poc`, implemented in
`ollmapp/AndroidPoc.vala`. It intentionally does not instantiate
`OllmchatApplication` or `OllmchatWindow`.

The POC window only provides:

- server URL
- optional API key
- model name
- prompt text
- response output

It sends one remote-only chat request through `OLLMchat.Call.ChatCompletions`
and does not initialize:

- history/session management
- tool registries
- vector search
- MCP stdio servers
- project/file management
- command execution
- model pulling
- settings pages

This is the correct application surface for the first mobile target. It keeps
Android focused on "can GTK launch and can remote chat work?" instead of trying
to port the full desktop app at once.

When Meson is cross-building for `host_machine.system() == 'android'`, the POC
target is declared with `android_exe_type: 'application'` so Android can load it
as an application shared object. `-Dandroid_poc=true` is Android cross-build
only; enabling it on the host is an error.

Build the debug APK locally with:

```bash
scripts/android/build-chat-poc-apk.sh
```

`build-chat-poc-apk.sh` bootstraps the Android command-line SDK/NDK under
`.android-sdk/` when needed, clones Pixiewood under `.android-tools/`, and runs
prepare, generate, and build through `android/pixiewood-chat-poc.xml`. Extra
Meson wraps, GTK patches, and cross options for libsoup, json-glib, gee,
sqlite, openssl, glib-networking, and related dependencies live under
`android/pixiewood-wraps/` and `android/pixiewood-extra.cross`.

GTK is still fetched from upstream GNOME (`gitlab.gnome.org/GNOME/gtk.git`), not
from a fork at build time. Android-specific fixes are developed in the live clone
at `~/git/gtk` (`https://github.com/roojs/gtk.git`), stored as
`android/pixiewood-wraps/gtk/android-bugs.patch`, and applied at prepare time via
`<patch>android-bugs</patch>` in the Pixiewood manifest. `gtk.wrap` in that
directory pins the upstream revision the patch was written against.

To refresh the patch after testing changes in `~/git/gtk`:

```bash
cd ~/git/gtk-Knowles
# Pin matches android/pixiewood-wraps/gtk/gtk.wrap revision.
BASE=$(sed -n 's/^revision[[:space:]]*=[[:space:]]*//p' \
  /path/to/OLLMchat/android/pixiewood-wraps/gtk/gtk.wrap)
# IME / text / atlas fixes from android-ime — TLS runtime stays out.
# Keep fuller nested-popup geometry from the existing android-bugs.patch
# (popup-v5); regenerate other files from the branch tip.
git diff "$BASE"..android-ime -- \
  gdk/android/glue/java/org/gtk/android/ImContext.java \
  gdk/android/glue/java/org/gtk/android/ToplevelActivity.java \
  gtk/gtktext.c \
  gtk/gtktextview.c \
  gtk/gtkgesturedrag.c \
  gsk/gpu/gskgpudevice.c \
  gsk/gpu/gskgpuuploadop.c \
  > /tmp/ime-core.diff
# Reassemble with popup + meson + gdkandroidollmchatpatch.c from the prior patch,
# bumping ollmchat-android-bugs-vN in the marker, then replace android-bugs.patch.
```

Update the `revision` in `android/pixiewood-wraps/gtk/gtk.wrap` to match the
upstream commit the diff is based on (`git merge-base upstream/main HEAD`).

The patch includes a compile-only marker source,
`gdk/android/gdkandroidollmchatpatch.c`, wired into `libgdk-android`. After a
build, grep the Meson/Ninja log for `gdkandroidollmchatpatch.c.o`. If that line
is missing, the patched GTK tree was not used (usually stale `subprojects/gtk`
from cache).

### Host prerequisites

Local APK builds use the same host packages as the **Android build** GitHub
Actions workflow (`.github/workflows/android-build.yml`). On Debian/Ubuntu,
install them once:

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  git \
  gir1.2-appstream \
  glslc \
  adwaita-icon-theme \
  libadwaita-1-dev \
  libglib-object-introspection-perl \
  libglib-perl \
  libglib2.0-dev-bin \
  libgtk-4-dev \
  libipc-run-perl \
  libjson-perl \
  libset-scalar-perl \
  libtext-template-perl \
  libxml-libxml-perl \
  libxml-libxslt-perl \
  libxml2-utils \
  meson \
  nasm \
  ninja-build \
  openjdk-17-jdk \
  pkg-config \
  python3 \
  sassc \
  unzip \
  valac
```

**TLS / HTTPS:** Remote chat needs **glib-networking** with an **OpenSSL**
backend. The OpenSSL Meson wrap runs a one-time `generator.sh` on the build
host during the first configure. That step requires **`nasm`** and
**`libtext-template-perl`**. Without them, configure fails while building the
`openssl` subproject. After a successful run, generated files live under
`subprojects/openssl-3.0.8/` and are reused from the subprojects cache on later
builds.

At runtime, GIO looks for TLS backends under `GIO_MODULE_DIR`. The Android
cross-build bakes in `/lib/arm64-v8a/gio/modules`, which does not exist on
device. Before any network I/O, `main()` calls
`ollmapp_configure_android_gio_tls_modules()` (`ollmapp/android/android-gio-tls.c`)
to scan GIO TLS modules under `g_get_system_data_dirs()/gio/modules` (GTK extracts APK
assets to `filesDir/` on startup; GIO modules are staged under
`assets/share/gio/modules/` at build time). CA trust is applied per `Soup.Session` via
`AndroidConnectionTls` / `GTlsFileDatabase` (bundled
`assets/share/ssl/certs/ca-certificates.crt`). See
[`docs/android-tls.md`](android-tls.md). The Pixiewood build enables Gradle
`packaging.jniLibs.useLegacyPackaging` so native libraries are extracted to a
real filesystem path.

**GTK icons:** Header bar and other UI widgets use symbolic icon names from the
Adwaita icon theme (`sidebar-show-symbolic`, `list-add-symbolic`, …). Pixiewood
only ships `bin`, `lib`, and glib schemas in APK assets, not icon themes — the
same class of problem as Windows before `sqgipkg.json` bundled
`adwaita-icon-theme`. The Android build reads `android/icons/manifest` (tab-separated
list of dest path, source theme, source path), symlinks each SVG from the build
host’s `/usr/share/icons/` into a staging tree, then copies with `cp -rL` into
`assets/share/icons/Adwaita/` (~tens of KB, not the full theme). Add a manifest
row when Android-shipped UI references a new `icon_name`. GTK extracts assets
with the rest of `assets/share/` before `main()`.
`AndroidApplication` sets `Gtk.Settings.gtk_icon_theme_name = "Adwaita"` (see
[`docs/bugs/done/2026-06-17-FIXED-android-icon-theme-gsettings.md`](bugs/done/2026-06-17-FIXED-android-icon-theme-gsettings.md)).

After a local or CI APK build, verify packaging with:

```bash
scripts/android/verify-apk.sh
```

This checks that the chat `.so` files, `assets/share/gio/modules/libgioopenssl.so`,
and every path listed in `android/icons/manifest` are present. Android does not
install nested `lib/ABI/gio/modules/*.so` from jniLibs, so that path must not be
used for TLS modules.

Before pushing Android Meson or wrap changes, run the local cross checks (SDK
under `.android-sdk/` must already exist — the APK script installs it on first
run):

```bash
scripts/android/verify-cross-configure.sh
scripts/android/verify-cross-compile.sh --with-app
```

That script pair matches the CI cross-configure and Vala compile path more
closely than configure alone.

### Vala / gee-0.8 on Android cross-builds

Android builds disable GObject introspection, so Vala `--pkg` wiring differs
from desktop. **Do not cargo-cult `--pkg=gee-0.8` onto every target.**

| Target kind | `dependency('gee-0.8')` | `--pkg=gee-0.8` | `--vapidir …/libgee-0.20.8/gee` |
|-------------|-------------------------|-----------------|----------------------------------|
| `library()` / `executable()` (e.g. `libollmchat`, `ollmchat-android-poc`) | yes | **no** — Meson already passes `gee-0.8.vapi`; duplicate `--pkg` causes *Package gee-0.8 not found* or *Gee already contains definition* | no |
| Root `add_project_arguments` on Android (`meson.build`) | n/a | **no** (same reason) | n/a |
| `custom_target` vapi generators (`ocmarkdown-vapi`, `ocsqlite-vapi`, `ollamaweb-vapi`) | n/a | **yes** | **yes** on Android — see `gee_vapi_dir` in each lib's `meson.build` |

When adding new Android Vala targets, mirror `ollmapp/meson.build` (`android_poc`
block before the shell refactor): list `dependency('gee-0.8')` in `dependencies`
and omit `--pkg=gee-0.8` from `vala_args`.

Successful debug builds produce APKs under:

```text
.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
```

**Debug stripped (release tags only):** GitHub Release builds set
`PIXIEWOOD_STRIP_DEBUG=1`, which passes `-Dstrip=true` to Meson while keeping
`--buildtype debug`. Pixiewood strips native libraries during `meson install`
before Gradle packages the APK. The release asset is named
`ollmchat-android-<tag>-debug-stripped.apk`. Manual **Android build** workflow
runs and local builds pass `-Dstrip=false` on every reconfigure so native debug
symbols are kept for testing (Meson otherwise retains `strip=true` from a prior
release configure).

To reproduce the release-style APK locally:

```bash
PIXIEWOOD_STRIP_DEBUG=1 scripts/android/build-chat-poc-apk.sh
```

### APK shell POC (local only)

The earlier `ollmchat-android-shell-poc` target in `ollmapp/AndroidShellPoc.vala`
links GTK and Libadwaita only. It validated the GTK Android backend, Meson
application target, Pixiewood generation, Gradle, and debug APK packaging before
the remote-chat stack was wired in.

It is still buildable locally for minimal backend checks:

```bash
scripts/android/build-shell-poc-apk.sh
```

CI no longer builds this target. Use the chat POC workflow instead.

## GGUF / local inference

There are no references to "guff" in the repository. The matching component is
GGUF support through libllama:

- Meson option: `-Dlocal_gguf=disabled|auto|enabled`
- Sources: `libollmchat/GGUF.vala` and `libollmchat/CallLocal/*`
- Release packaging already disables it for AppImage and Windows builds
- Debian packaging includes both full and `ollmchat-remote-only` variants

Disabling GGUF is already supported and should be the default for any Android
experiment. It removes libllama from the problem, but it does not remove the
larger Android blockers.

## GTK on Android

GTK 4 has an Android backend, but upstream describes it as experimental. It can
run GTK demos, but there are still rough edges around input, rendering, and
application integration. Current GTK Android packaging also requires Android
specific build handling; for Meson applications this includes building the app
target with an Android application executable type, for example:

```meson
executable(
  'ollmchat',
  sources,
  android_exe_type: 'application',
)
```

Pixiewood / gtk-android-builder generates Android packaging around Meson GTK
applications. The remote chat POC now builds a debug arm64 APK with Libadwaita,
`libollmchat`, and its network stack. The full desktop app still needs more
feature gating and dependency work.

## Main Android blockers

### Desktop UI and toolkit dependencies

The main UI depends on GTK 4, Libadwaita, and GtkSourceView. The widgets and
workflows are desktop oriented, including multi-pane layouts, project browsing,
source editing, settings dialogs, and file/tool permission flows. Even if the
application compiles, it would need mobile usability work.

### Native dependency stack

An Android build would need Android-compatible builds of the native dependency
chain. The chat POC already bundles GTK, Libadwaita, libsoup, json-glib, gee,
sqlite, libxml2, and the trimmed `libollmchat` stack through Pixiewood wraps and
subprojects.

Remaining gaps for a full app include at least:

- GtkSourceView
- libgit2-glib
- tree-sitter
- FAISS and OpenBLAS, unless vector search is disabled or replaced

The current production cross-build support targets Linux AppImage and Windows
through sqgipkg.

### Linux-specific runtime features

Some parts of the app assume a desktop Linux environment:

- bubblewrap / `bwrap` sandboxing for command execution
- libseccomp user notification experiments and evidence reporting
- Unix sockets and forked daemon behavior in `ollmfilesd`
- stdio subprocess MCP servers
- desktop filesystem and project-root assumptions
- desktop install metadata such as `.desktop` files and XDG paths

These features would need to be disabled, replaced, or redesigned for Android.

### Local services and model management

The normal desktop workflow often talks to a local Ollama service and may pull
models through the settings UI. Android experiments should start remote-only
against an existing HTTP LLM endpoint instead of trying to run local model
services or GGUF inference on device.

## GitHub Actions

### Remote-only desktop build

GitHub Actions can build the existing remote-only desktop configuration on
demand through the `Remote-only build` workflow. This validates that the
no-GGUF path keeps compiling without requiring libllama packages.

### Android build workflow

The **Android build** workflow builds the remote chat POC on demand:

1. Open GitHub Actions.
2. Choose **Android build**.
3. Click **Run workflow** and select the branch to test.
4. Optionally enable **Rebuild SDK and Pixiewood/GTK caches from scratch** when
   you need a cold build.
5. Download `ollmchat-android-poc-debug.apk` from the completed run (uploaded
   as a direct `.apk`, not a zip).

The workflow is deliberately manual-only (`workflow_dispatch`) because it
downloads the Android SDK/NDK and builds a large GTK Android dependency stack.
It should not run on every pull request until cost and reliability are known.

The job provides:

- host packages listed under **Host prerequisites** above (including `nasm` and
  `libtext-template-perl` for the OpenSSL TLS stack)
- Android SDK and NDK setup through `scripts/android/install-sdk.sh`
- Meson with Android application target support; `scripts/android/ensure-meson.sh`
  downloads and extracts Debian's current `meson_*_all.deb` under
  `.android-tools/` when the system Meson is too old
- Pixiewood packaging through `android/pixiewood-chat-poc.xml` (GTK stack plus
  openssl/glib-networking for HTTPS via libsoup)
- restore/save caching for the SDK, Pixiewood/GTK tree, and Gradle (same
  pattern as the Debian extra-package cache in `release.yml`)
- a CI check that the APK contains `libollmchat-android-poc.so`,
  `libollmchat.so`, `assets/share/gio/modules/libgioopenssl.so`, and curated icons
  from `android/icons/manifest` under `assets/share/icons/Adwaita/`

The workflow does not yet run:

- emulator or device smoke tests
- release signing
- AAB packaging
- universal or x86 APK variants (CI builds arm64 only)

Possible future triggers:

- keep `workflow_dispatch` while iterating on device behavior
- add `pull_request` only after the job is stable and the runtime cost is known
- add release/tag publishing later by copying the generated APK into
  `release.yml` or a dedicated Android release workflow

Normal Linux builds should continue to work with the distro Meson shipped by
Ubuntu 24.04. A newer Meson is only required when cross-building the Android
application target, because that path needs `android_exe_type`.

## Recommended next steps

1. Run **Android build** manually from GitHub Actions and install the debug APK
   on a device or emulator.
2. Exercise remote chat against a reachable HTTP LLM endpoint on a real device.
3. Add Meson options to disable Android-hostile subsystems independently:
   vector search, command execution sandboxing, MCP stdio, and `ollmfilesd`.
4. Extend Android wraps or subproject handling for any libraries needed beyond
   the current chat POC stack. **Browser tool:** `android/pixiewood-wraps/webkitgtk-android/`
   provides `webkitgtk-android-1` (Meson subproject + `override_dependency`);
   APK Java host classes are installed via sibling
   `scripts/android/install-webview-java.sh` from `install_poc_java` in
   `scripts/android/build-pixiewood-apk.sh` (see [`5.0.2`](plans/5.0.2-android-webkit-control.md)).
5. Reintroduce larger desktop features only after the app launches and basic
   chat works reliably on device.

## Status

Remote-only/no-GGUF builds are already supported and are appropriate for CI.
The first Android packaging milestone is complete: the remote chat POC builds a
debug arm64 APK with Pixiewood, `libollmchat`, and its network dependencies.
The next milestone is reliable on-device remote chat and incremental feature
gating—not porting the full desktop application.
