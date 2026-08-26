# 5.6 — Windows native GitHub release build

> **Do not update `docs/plans/APP-1.0-summary.md` for this plan.**

**Status:** in progress

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Related:**

- ℹ️ Parent WebKit: [`WEBKIT-5.0-webkit-control.md`](WEBKIT-5.0-webkit-control.md)
- ℹ️ Windows a11y / `webview2-gtk` wire: [`done/5.0.1-DONE-windows-webkit-accessibility.md`](done/5.0.1-DONE-windows-webkit-accessibility.md)
- ℹ️ Older Linux-cross Windows plan (superseded for **release**): [`APP-5.7-building-windows.md`](APP-5.7-building-windows.md)
- ℹ️ Current Ubuntu release CI: [`.github/workflows/release.yml`](../../.github/workflows/release.yml)
- ℹ️ Release docs: [`docs/creating-releases.md`](../creating-releases.md)
- ℹ️ **Library CI (copy shape):** `webview2-gtk/.github/workflows/release.yml`
- ℹ️ **Library consumer template:** `webview2-gtk/scripts/sample-github-build-windows.yml`
- ℹ️ **Library docs:** `webview2-gtk/docs/build-this-library.md` (no Linux cross-compile), `docs/deploying-windows.md`, `docs/using-in-your-app.md`

---

## Purpose

- **🔷** Confirm Ubuntu **mingw / sqgipkg** Windows cross-build is **not** viable once the browser tool links **`webview2-gtk`** (WebView2 / COM / `WebView2Loader`).
- **🔷** Split release CI: keep **Linux / Debian / AppImage** on Ubuntu; add a **separate Windows job** that builds on a **GitHub Windows runner** (MSYS2 UCRT64).
- **🔷** Mirror **webview2-gtk**: NSIS + pacman assets from **`windows-latest`** + **`msys2/setup-msys2`**, plus its consumer sample workflow (`sample-github-build-windows.yml`).
- **🔷** Ship Windows installer / app as **`OLLMchat`** — not `remote-only` in the filename (see **Windows naming** below).
- **✔️** **🔷** Remove `sqgipkg --target win-nsis` from the Ubuntu release job. sqgipkg is Linux AppImage only.
- **💩** Optional later: Linux→Windows SSH/rsync for local QA — not required for CI if GitHub `windows-latest` is the release path.

### Windows naming

- **🔷** There is **no** second Windows SKU (no local-GGUF / libllama Windows build today).
- **🔷** `remote-only` on Linux means “no local inference engine”; Windows is that product by default — do **not** put `remote-only` in Windows artifact names.
- **🔷** Installed app binary: **`OLLMchat.exe`**.
- **🔷** **Required** release asset: versioned **`OLLMchat-<version>-Setup.exe`**, with `<version>` from `meson.build` `project(… version: '…')`.
- **🔷** Pass that version into NSIS as **`PRODUCT_VERSION`** (`-DPRODUCT_VERSION=…` + `OUTFILE=…/OLLMchat-${VERSION}-Setup.exe`).
- **✔️** **🔷** Drop the unversioned `OLLMchat-remote-only-Setup.exe` Ubuntu artifact (no Windows installer from sqgipkg).
- **✔️** **🔷** Refuse to overwrite an existing same-version setup exe (forces a meson version bump).
- **ℹ️** **“Portable dir”** = staging folder only (`dist-windows/OLLMchat/` = exe + GTK DLLs + `WebView2Loader.dll`). NSIS packs that folder. **It is not a second release product** — tags attach Setup.exe only.
- **💩** If local GGUF is ever ported to Windows, **then** consider a rename / second SKU — not now.

---

## Phase 1 — CI script + dispatch (done)

- **✔️** **🔷** MSYS2 UCRT64 compile: [`windows-build.yml`](../../.github/workflows/windows-build.yml) (compile-only smoke) + [`scripts/ci/windows-msys2-build.sh`](../../scripts/ci/windows-msys2-build.sh).
- **✔️** **🔷** Meson Windows deps (`webview2gtk-1`, `-D WINDOWS` / `-D LINUX`, pacman pin).
- **✔️** **🔷** Green compile proven on Windows QA host (`network_session` property API).
- **⏳** **🔷** Confirm same green on GitHub `windows-latest` (Actions run).

---

## Phase 2 — Package + release wire (current)

- **✔️** **🔷** Staging + NSIS: [`scripts/ci/windows-package-nsis.sh`](../../scripts/ci/windows-package-nsis.sh), [`scripts/copy-exe-runtime-dlls.sh`](../../scripts/copy-exe-runtime-dlls.sh), [`packaging/windows/ollmchat.nsi`](../../packaging/windows/ollmchat.nsi).
- **✔️** **🔷** Release-callable job: [`x-windows.yml`](../../.github/workflows/x-windows.yml) (compile → package → artifact `ollmchat-windows`).
- **✔️** **🔷** Manual button: [`release-windows.yml`](../../.github/workflows/release-windows.yml).
- **✔️** **🔷** Tag publish: [`release.yml`](../../.github/workflows/release.yml) `build-windows` in `publish.needs` (same `ollmchat-*` download pattern).
- **✔️** **🔷** Docs: [`creating-releases.md`](../creating-releases.md) lists Setup.exe + Release - Windows.
- **⏳** **🔷** Prove package script produces Setup.exe (QA box and/or `gh workflow run release-windows.yml`).

---

## Why cross-compile breaks

- **🔷** **Ubuntu no longer ships a Windows installer.** sqgipkg is Linux AppImage only ([`x-sqgipkg.yml`](../../.github/workflows/x-sqgipkg.yml), [`creating-releases.md`](../creating-releases.md)). The old path was Ubuntu **`ubuntu-24.04`** → `mingw-w64` + **`sqgipkg --target win-nsis`**.
- **🔷** Browser cookies / downloads use WebKitGTK-shaped **`web_view.network_session`** (property), not `get_network_session()` — latest webview2-gtk only exposes the property; WebKitGTK 6 has both.
- **ℹ️** Sibling library states plainly: **no Linux cross-compile path** for webview2-gtk itself (`docs/build-this-library.md`).
- **🔷** WebView2 needs native Windows headers / SDK vendoring (`vendor-webview2-sdk.sh`), `WebView2Loader.dll`, and a Win32 HWND parent — that stack is what **webview2-gtk** builds on **MSYS2 UCRT64 on Windows**.
- **💩** Wine smoke of an old GTK-only cross bundle may still work for non-browser paths; it is **not** a release gate for WebView2.

---

## Reference builds (what to copy)

### webview2-gtk — GitHub Windows release (canonical CI shape)

- **ℹ️** Workflow: `webview2-gtk/.github/workflows/release.yml`
  - `runs-on: windows-latest`
  - `defaults.run.shell: msys2 {0}`
  - `msys2/setup-msys2@v2` with **`msystem: UCRT64`**
  - pacman toolchain: gcc, vala, meson, ninja, pkg-config, gtk4, libgee, libsoup3, curl, nsis
  - Build NSIS installer + pacman `.pkg.tar.zst`
  - Upload artifact; on `v*` tags attach to GitHub Release
- **ℹ️** Consumer template: `scripts/sample-github-build-windows.yml`
  - Same runner / MSYS2 setup
  - Build **webview2gtk** into a prefix (or clone repo)
  - Set `PKG_CONFIG_PATH`
  - Meson-build the app
  - Package with `copy-exe-runtime-dlls` / `package-windows` (exe + GTK DLLs + `WebView2Loader.dll`)
- **ℹ️** End users still need **WebView2 Runtime** (Evergreen) on the PC — document in release notes / installer text (`webview2-gtk/docs/deploying-windows.md`).

OLLMchat CI follows **compile → stage runtime DLLs → NSIS Setup.exe** on **GitHub `windows-latest`**.

---

## Target CI shape

### Job split

- **🔷** **Ubuntu jobs** — keep Debian, AppImages, Android; **✔️** no Windows from sqgipkg.
- **✔️** **🔷** **`build-windows`** — [`x-windows.yml`](../../.github/workflows/x-windows.yml):
  - Checkout OLLMchat
  - pacman webview2gtk (pinned) + FAISS + meson compile
  - Stage `dist-windows/OLLMchat/` then NSIS → **`OLLMchat-<version>-Setup.exe`**
  - Upload `ollmchat-windows`; on tag, Publish attaches Setup.exe with other assets

### Trigger / publish

- **✔️** **🔷** Manual: **Release - Windows** / compile-only **X - Native Windows MSYS2 compile**.
- **✔️** **🔷** Tag path: `release.yml` waits on `build-windows` before Publish / changelog finalize.
- **🔷** Changelog finalize on `main` waits until Windows installer artifact is present (preferred; same as other blocking package jobs).

---

## Meson / tree work

### Platform deps

- **✔️** **🔷** Root / `libocwebkit` Meson: Windows uses `dependency('webview2gtk-1')`; Vala `-D WINDOWS`.
- **ℹ️** Precedent: webview2-gtk `examples/consumer-meson.build`

### Packaging scripts

- **✔️** **🔷** Native package path (not Ubuntu sqgipkg):
  - `copy-exe-runtime-dlls.sh` + `windows-package-nsis.sh`
  - Staging dir including `WebView2Loader.dll` + GTK DLLs
  - NSIS → versioned `OLLMchat-${VERSION}-Setup.exe` + `PRODUCT_VERSION`
- **💩** Keep Linux `scripts/build-windows-dir.sh` as legacy pointer only — not for tagged releases

### Docs

- **✔️** **🔷** [`creating-releases.md`](../creating-releases.md): Windows from Windows runner; **`OLLMchat-<version>-Setup.exe`**
- **✔️** **🔷** [`APP-5.7-building-windows.md`](APP-5.7-building-windows.md) marks Linux cross-compile as superseded; points at 5.6 / `x-windows.yml`

---

## Suggested implementation order

1. **✔️** **🔷** Phase 1: MSYS2 compile workflow + script; Meson Windows deps.
2. **✔️** **🔷** Green compile on Windows host (API `network_session`).
3. **✔️** **🔷** Package + NSIS scripts + release wire (`x-windows` / `release-windows` / `release.yml`).
4. **✔️** **🔷** Drop Ubuntu `win-nsis` / sqgipkg Windows.
5. **⏳** **🔷** Prove Setup.exe on Actions / QA box; first tagged release with Windows asset.

---

## LLM notes

- Prefer **published webview2gtk pacman** from library releases for reproducible CI pins; fall back to building from a **pinned git ref** in the same job (sample workflow).
- Do not invent a second WebView wrapper — only **`webview2-gtk`**.
- Do not expand scope into Android packaging; that stays the reusable Android workflow.
- End-user dependency: document **WebView2 Runtime** (Evergreen) — `webview2-gtk/docs/deploying-windows.md`.
- Do not cite private sibling apps in public OLLMchat docs — webview2-gtk only.
