# Android feasibility study

This note records the current feasibility of building OLLMchat for Android and
of adding automatic GitHub builds.

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
3. Maintain a stripped-down Android proof-of-concept entry point that avoids
   the desktop window and its tool/project/vector setup.
4. Treat GGUF/libllama as optional for mobile and disable it for early Android
   experiments.

## Current application shape

OLLMchat is built with Meson and Vala. The main application uses GTK 4,
Libadwaita, and GtkSourceView. The project also builds reusable libraries for
LLM API access, markdown rendering, project/file management, MCP tools, vector
search, and the GTK chat UI.

The existing release automation builds:

- Linux AppImages for x86_64 and aarch64
- Debian packages for amd64
- a Windows NSIS installer

The repository now includes a Pixiewood-based Android shell packaging path.
Pixiewood generates the Gradle project, Android manifest, and Android NDK cross
files under `.pixiewood/` at build time.

## Minimal Android proof of concept

The repository includes two opt-in proof-of-concept targets.

### APK shell POC

The first target is `ollmchat-android-shell-poc`, implemented in
`ollmapp/AndroidShellPoc.vala`. It uses GTK and Libadwaita, but intentionally
does not link `libollmchat` yet. This validates that the GTK Android backend,
Libadwaita, Meson Android application target, Pixiewood generation, Gradle, and
debug APK packaging can work together.

Build it with:

```bash
scripts/android/build-shell-poc-apk.sh
```

The script bootstraps the Android command-line SDK/NDK under `.android-sdk/`
when needed, clones Pixiewood under `.android-tools/`, and runs:

```bash
pixiewood prepare android/pixiewood-shell-poc.xml
pixiewood generate
pixiewood build
```

Successful debug builds produce APKs under:

```text
.pixiewood/android/app/build/outputs/apk/debug/
```

The first validated output paths were:

```text
.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
.pixiewood/android/app/build/outputs/apk/debug/app-universal-debug.apk
```

### Remote chat POC

The second target is `ollmchat-android-poc`, implemented in
`ollmapp/AndroidPoc.vala`:

```bash
meson setup build-android-poc --prefix=/usr \
  -Dandroid_poc=true \
  -Dlocal_gguf=disabled
ninja -C build-android-poc ollmapp/ollmchat-android-poc
```

The target is `ollmchat-android-poc` and the source is
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

This is the correct application surface to use for an Android package
experiment. It keeps the first mobile target focused on "can GTK launch and can
remote chat work?" instead of trying to port the full desktop app at once.

When Meson is cross-building for `host_machine.system() == 'android'`, the POC
target is declared with `android_exe_type: 'application'` so Android can load it
as an application shared object. Desktop builds omit that keyword and compile
the same POC as a normal executable for CI validation.

The remote chat POC is not the APK target yet because it brings in additional
native dependencies (`libollmchat`, libsoup, json-glib, gee, sqlite, and related
Vala package metadata). Those dependencies are the next Android packaging layer
after the shell APK.

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

Pixiewood / gtk-android-builder can generate Android packaging around Meson GTK
applications. In this branch, it successfully builds a Libadwaita shell APK for
`ollmchat-android-shell-poc`; the full app still needs more feature gating and
native dependency wrapping.

## Main Android blockers

### Desktop UI and toolkit dependencies

The main UI depends on GTK 4, Libadwaita, and GtkSourceView. The widgets and
workflows are desktop oriented, including multi-pane layouts, project browsing,
source editing, settings dialogs, and file/tool permission flows. Even if the
application compiles, it would need mobile usability work.

### Native dependency stack

An Android build would need Android-compatible builds of the native dependency
chain, including at least:

- GLib/GIO/GObject
- GTK 4
- Libadwaita
- GtkSourceView
- libsoup
- json-glib
- libxml2
- SQLite
- libgit2-glib
- tree-sitter
- FAISS and OpenBLAS, unless vector search is disabled or replaced

The current production cross-build support targets Linux AppImage and Windows
through sqgipkg. The new Pixiewood shell path provides an Android GTK/
Libadwaita dependency bundle for the shell POC, but not yet for the
remote-chat target's extra libraries.

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

## GitHub Actions feasibility

### Feasible now

GitHub Actions can build the existing remote-only desktop configuration on
demand. This validates that the no-GGUF path keeps compiling without requiring
libllama packages.

The Android shell APK can also be built locally with:

```bash
scripts/android/build-shell-poc-apk.sh
```

It can also be built on GitHub without making a release:

1. Open GitHub Actions.
2. Choose the `Android shell APK` workflow.
3. Click `Run workflow` and select the branch to test.
4. Download the `ollmchat-android-shell-apk` artifact from the completed run.

The artifact contains the debug APK files generated by Gradle, including:

```text
app-arm64-v8a-debug.apk
app-universal-debug.apk
```

A suitable manual workflow should:

- install the normal Linux build dependencies
- install FAISS from Debian, matching the existing release/docs workflows
- configure Meson with `-Dlocal_gguf=disabled`
- configure Meson with `-Dandroid_poc=true`
- compile with Ninja
- run offline tests that do not require Ollama, local model downloads, or
  Android devices

Normal Linux builds should continue to work with the distro Meson shipped by
Ubuntu 24.04. A newer Meson is only required when cross-building the Android
application target, because that path needs `android_exe_type`.

### Android shell APK automation

The initial Android automation is deliberately manual-only:

```yaml
on:
  workflow_dispatch:
```

That trigger is the safest first step because the job downloads the Android
SDK/NDK and builds a large GTK Android dependency stack. It should not run on
every pull request until we know the cost and reliability are acceptable.

The workflow currently provides:

- Android SDK and NDK setup through `scripts/android/install-sdk.sh`
- Meson with Android application target support; `scripts/android/ensure-meson.sh`
  downloads and extracts Debian's current `meson_*_all.deb` under
  `.android-tools/` when the system Meson is too old
- Pixiewood package generation through `android/pixiewood-shell-poc.xml`
- artifact upload for generated debug APKs

Possible future triggers:

- keep `workflow_dispatch` while iterating on the shell APK
- add `pull_request` only after the job is stable and the runtime cost is known
- add release/tag publishing later by copying the generated APKs into
  `release.yml` or a dedicated Android release workflow

The workflow does not yet run:

- emulator or device smoke tests
- release signing
- AAB packaging

The remote-chat APK/AAB still needs:

- Android packaging for `ollmchat-android-poc`
- Android builds or wraps for libsoup, json-glib, gee, sqlite, and
  `libollmchat`
- feature gating for Linux-only components before moving beyond the shell

## Recommended next steps

1. Run `Android shell APK` manually from GitHub Actions and install the debug
   APK artifact on a device or emulator.
2. Add Pixiewood packaging around `ollmchat-android-poc`.
3. Add Android wraps or subproject handling for the remote-chat dependencies.
4. Add Meson options to disable Android-hostile subsystems independently:
   vector search, command execution sandboxing, MCP stdio, and `ollmfilesd`.
5. Reintroduce larger desktop features only after the app launches and basic
   chat works on device.

## Verdict

Remote-only/no-GGUF builds are already supported and are appropriate for CI.
The first Android packaging milestone is now concrete: the Libadwaita shell POC
can build a debug APK with Pixiewood. The next milestone is moving from that
shell to the minimal `ollmchat-android-poc` remote chat client, not the full
desktop application.
