# Windows redistributable libraries

**Status:** ⏳ OLLMchat publishes the packages; Argus still compiles this tree

**Pointer:** `docs/bug-fix-process.md`

Filed from Argus. The Argus Windows installer compiles this tree to obtain the libraries it links.

## Problem

- 🔷 Argus needs the Windows build of `libocrpc` and `libocsqlite`, including the import libraries, VAPI files, and headers.
- 🔷 A consumer should download those libraries. It should not compile OLLMchat.
- 🔷 Linux already publishes `libocrpc-dev` and `libocsqlite-dev`. Windows has no equivalent.

## Evidence

- ✔️ Argus `.github/workflows/x-windows.yml` checks out `roojs/OLLMchat` at `1cba1934e04be1ce16a650e52d5c00af68a3d572`.
- ✔️ That job runs `scripts/ci/windows-msys2-build.sh`, then `meson install -C build-windows`.
- ✔️ `scripts/ci/windows-msys2-build.sh` builds FAISS, installs webview2gtk, and `meson compile`s this tree. Docs, examples, tests, and local GGUF are off. The compile has no library-only target.
- ✔️ After that install, Argus compiles one program: `./agent/argus-agent:executable`.
- ℹ️ Argus links those two libraries through `find_library('ocrpc')` and `find_library('ocsqlite')` in its `meson.build`.

## Root cause

- ✔️ The Windows CI script is the full application build. Nothing in it publishes `libocrpc` and `libocsqlite` as a consumer package, so Argus runs that script.

## Proposed fix

- 🔷 The Windows build publishes a redistributable package of the libraries a consumer links. For Argus that is `libocrpc` and `libocsqlite`, with import libraries, VAPI files, and headers.
- 🔷 Argus then downloads that package and builds `argus-agent`. It does not configure or compile this tree.
- 🔷 Package form: one MSYS2 UCRT64 pacman package per library, same shape as webview2gtk (`pacman -U` a `mingw-w64-ucrt-x86_64-lib<name>-*-any.pkg.tar.zst` from the versioned GitHub Release).
- 🔷 Libraries: `libocsqlite`, `libocrpc`, `libocmarkdown`, `libollamaweb`, `libochf`, `libocmarkdowngtk`, `libocfiles`, `libollmchat`, `libocwebkit`, `libocvector2`, `libocbwrap`, `libocmcp`, `liboctools`, `liboccoder`, `libollmchatgtk`.
- 🔷 Each package has `bin/lib<name>.dll`, `lib/lib<name>.dll.a`, `include/<name>.h`, and `share/vala/vapi/<name>.vapi`.
- 🔷 GIR is included when that library's Meson target sets `vala_gir` on Windows: `OCSqlite`, `OCMarkdown`, `OCMarkdownGtk`, `OLLMchat`, `OLLMtools`, `OLLMcoder`, `OLLMchatGtk`.
- ℹ️ `meson.build` sets `g_ir_compiler` to a disabler on Windows, so this build has no typelib to ship.
- 🔷 `libocvector2` also ships `libfaiss.dll`. The Windows job builds FAISS from source, and MSYS2 has no faiss package. OpenBLAS and LAPACK stay pacman depends.
- 🔷 The packages are unsigned. Install is download, then `pacman -U` on the local files. This repo has no packager secret, so it does not publish a `.sig`.
- 🚫 Do not keep building FAISS, webview2gtk, and the OLLMchat application inside the Argus job.

## Attempts / changelog

- ✔️ `scripts/ci/windows-package-libs.sh` stages every `_libs` entry from `build-windows` and runs `makepkg-mingw`.
- ✔️ `packaging/msys2/PKGBUILD` has one `package_*` function per library.
- ✔️ `.github/workflows/x-windows.yml` runs that script and uploads both `.pkg.tar.zst` files with the Setup.exe.
- ✔️ `.github/workflows/release.yml` attaches `*.pkg.tar.zst` to the version tag.
- ✔️ Docs: `docs/creating-releases.md`. Changelog bullet under `[1.4.7]`.
- 🚫 Argus is not in this tree, so its workflow still checks out OLLMchat and compiles it.

## Next

- ⏳ 🔷 Point the Argus Windows job at the release assets it links (`libocrpc`, `libocsqlite`, and any sibling those depends pull in). It should `pacman -U` the downloaded files and build `argus-agent` from those prefixes.
- ⏳ ℹ️ The packages exist on a release only after the next tagged **Release** (or a **Release - Windows** artifact, which is not a download URL).
