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

There are no Android project files today: no Gradle project, Android manifest,
APK/AAB packaging, Android NDK cross file, or Android GitHub Actions workflow.

## Minimal Android proof of concept

The repository now includes an opt-in proof-of-concept target:

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

Tools such as Pixiewood / gtk-android-builder can generate Android packaging
around Meson GTK applications, but this project does not currently meet all of
the practical requirements for a successful full-app build.

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

The current cross-build support targets Linux AppImage and Windows through
sqgipkg. It does not provide an Android sysroot or dependency bundle.

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

GitHub Actions can automatically build the existing remote-only desktop
configuration. This validates that the no-GGUF path keeps compiling without
requiring libllama packages.

A suitable PR workflow should:

- install the normal Linux build dependencies
- install FAISS from Debian, matching the existing release/docs workflows
- configure Meson with `-Dlocal_gguf=disabled`
- configure Meson with `-Dandroid_poc=true`
- compile with Ninja
- run offline tests that do not require Ollama, local model downloads, or
  Android devices

### Not feasible yet

An Android APK/AAB workflow is not useful until the repository has an Android
target. A future Android CI job would need:

- Android SDK and NDK setup
- Meson with Android application target support
- Pixiewood or equivalent packaging configuration for `ollmchat-android-poc`
- Android builds or wraps for the required GTK/native dependencies
- feature gating for Linux-only components
- emulator or device smoke tests

## Recommended next steps

1. Keep the initial CI focused on the remote-only Linux build and POC target.
2. Add Pixiewood or Gradle packaging around `ollmchat-android-poc`.
3. Add Meson options to disable Android-hostile subsystems independently:
   vector search, command execution sandboxing, MCP stdio, and `ollmfilesd`.
4. Cross-build GTK, Libadwaita, GLib, libsoup, and libollmchat dependencies
   for Android.
5. Create an APK/AAB workflow once the Android dependency bundle exists.
6. Reintroduce larger desktop features only after the app launches and basic
   chat works on device.

## Verdict

Remote-only/no-GGUF builds are already supported and are appropriate for CI.
Android is technically possible, but it is a porting project rather than a
release packaging task. The first Android milestone is the minimal
`ollmchat-android-poc` remote chat client, not the full desktop application.
