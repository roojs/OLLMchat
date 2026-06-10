# Building and running OLLMchat on Windows

**Status:** PLAN

**Goal:** Document and script three separate Windows workflows — cross-build + Wine smoke test on Linux, run the portable bundle on native Windows without installing, and produce the NSIS installer. Split manual-build docs out of [creating-releases.md](../creating-releases.md), which should stay focused on CI/tag releases.

---

## Current state

| Piece | Status | Notes |
|-------|--------|-------|
| Cross-compile portable bundle | ✅ `scripts/build-windows-dir.sh` | `sqgipkg --target win-dir` → `dist-windows-x86_64/OLLMchat/` |
| Wine smoke test | ⚠️ partial | `--wine` flag on build script; no standalone run script |
| Native Windows run (no install) | ⚠️ partial | Launchers in bundle (`OLLMchat.bat`, `OLLMchat.ps1`); no zip/transfer helper |
| NSIS installer | ⚠️ CI only | `sqgipkg --target win-nsis` in release workflow; no local script |
| Docs | ❌ wrong place | Manual `sqgipkg` / deb steps live in [creating-releases.md](../creating-releases.md) |

**Artifact layout** (all gitignored):

```text
build-windows-x86_64/     # meson compile tree — NOT runnable alone
dist-windows-x86_64/
  OLLMchat/               # portable bundle — copy this to Windows or run under Wine
    OLLMchat.exe          # GUI launcher (hidden console → OLLMchat.bat)
    OLLMchat.bat          # sqgipkg launcher (sets PATH, FONTCONFIG_*, GDK_BACKEND=win32)
    OLLMchat.ps1          # PowerShell wrapper
    ollmapp/ollmchat.exe  # actual app binary
    bin/, lib/, share/    # MSYS2/GTK runtime DLLs
  OLLMchat-Setup.exe      # NSIS installer (win-nsis target only)
.sqgipkg/                 # sqgi install, MSYS2 cache, native faiss build
```

Configuration: [`sqgipkg.json`](../../sqgipkg.json) (`windows.build_dir`, packages, native faiss patches, staged files).

---

## Part 1 — Cross-build on Linux + Wine smoke test

**Purpose:** Day-to-day dev loop on Linux — compile the Windows binary and sanity-check it under Wine without a Windows machine.

### Script: `scripts/build-windows-dir.sh` (exists)

Keep as the single entry point for cross-compilation. It already:

1. Resolves/clones [sqgi](https://github.com/supercamel/sqgi) (sibling `../sqgi` or `.sqgipkg/sqgi`)
2. Builds/installs sqgi into `.sqgipkg/host` when missing
3. Downloads Noto Color Emoji (not in MSYS2)
4. Runs `sqgipkg --target win-dir`
5. Post-steps: patch `FONTCONFIG_FILE` in `OLLMchat.bat`, embed app icon in `OLLMchat.exe`

**Usage:**

```bash
scripts/build-windows-dir.sh              # build portable bundle
scripts/build-windows-dir.sh --debug      # visible console (--windows-console)
scripts/build-windows-dir.sh --wine       # build then launch under Wine
scripts/build-windows-dir.sh --clean      # remove build/dist/.sqgipkg artifacts
scripts/build-windows-dir.sh --sysroot-only   # MSYS2 sysroot only (no app bundle)
```

**Host prerequisites** (Ubuntu/Debian, same family as CI):

```bash
sudo apt-get install -y \
  build-essential cmake ninja-build pkg-config git curl \
  meson valac wine \
  mingw-w64 \
  x86_64-w64-mingw32-gcc x86_64-w64-mingw32-g++ x86_64-w64-mingw32-windres
```

### Script: `scripts/run-windows-wine.sh` (new)

Thin wrapper so rebuild is not required for every test run.

```bash
scripts/run-windows-wine.sh [--debug] [--] [app args...]
```

Behavior:

- Require `dist-windows-x86_64/OLLMchat/OLLMchat.bat`; error with “run build-windows-dir.sh first” if missing
- `WINEPREFIX` default `~/.wine-ollmchat` (match build script)
- Invoke `wine cmd /c "…/OLLMchat.bat …"` — **never** run `ollmapp/ollmchat.exe` directly (missing env)
- `--debug` forwarded to the bat launcher

Refactor `build-windows-dir.sh --wine` to call this script instead of duplicating logic.

### Wine limitations

Wine is a smoke test, not a release gate. Known gaps (see [2026-06-09-windows-startup bug](../bugs/2026-06-09-windows-startup-configure-loop-required-models.md)):

- First-run / bootstrap UX may differ from native Windows
- Some GTK/adwaita rendering quirks
- Use native Windows (Part 2) before tagging a release

---

## Part 2 — Run on native Windows (no install)

**Purpose:** QA the real Windows runtime. The portable bundle is self-contained; no NSIS install step.

### Workflow

1. On Linux, after Part 1:

   ```bash
   scripts/build-windows-dir.sh
   ```

2. Copy **`dist-windows-x86_64/OLLMchat/`** (the folder, not `build-windows-x86_64/`) to the Windows PC — USB, SMB, scp, etc.

3. On Windows, from the bundle folder (Samba / `X:`: see [vala.win32 `windows-build.md`](../../../vala.win32/docs/windows-build.md) — use `X:` then `cd …`, not `cd X:\…`):

   Do **not** run `.\OLLMchat.ps1` directly — default policy blocks unsigned scripts. Same one-liner pattern as [Snappr `windows-build.md`](../../../app.Snappr/docs/windows-build.md):

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\OLLMchat.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\OLLMchat.ps1 --debug
   ```

   From a repo checkout on the Samba share (example):

   ```powershell
   X:
   cd OLLMchat\dist-windows-x86_64\OLLMchat
   powershell -NoProfile -ExecutionPolicy Bypass -File .\OLLMchat.ps1 --debug
   ```

### Script: `scripts/stage-windows-portable.sh` (new, optional)

Convenience for transfer — does **not** replace the bundle, just packages it:

```bash
scripts/stage-windows-portable.sh
# → dist-windows-x86_64/OLLMchat-portable.zip
```

- Fail if `dist-windows-x86_64/OLLMchat/` missing
- Zip with paths relative to `OLLMchat/` root so unzip-on-Windows gives a runnable folder
- Print size + reminder to unzip and run via `OLLMchat.ps1` (with `-ExecutionPolicy Bypass`)

### Native Windows build (future, out of scope for v1)

Cross-compilation from Linux is the supported path (matches CI). A **native MSYS2 build on Windows** would be a separate plan if needed — duplicate sqgipkg/msys2 setup, slower, only worth it if cross-build breaks. Do not block Parts 1–3 on this.

---

## Part 3 — Package NSIS installer on Linux

**Purpose:** Produce `OLLMchat-Setup.exe` locally — same artifact CI attaches to GitHub Releases. Releases themselves stay server-driven ([creating-releases.md](../creating-releases.md)); this is for pre-release QA of the installer.

### Script: `scripts/package-windows-nsis.sh` (new)

Mirror `build-windows-dir.sh` structure:

1. Share sqgi resolution / install / host-deps with build script (extract common functions to `scripts/windows-build-common.sh` if duplication grows)
2. Run `sqgipkg --target win-nsis --output dist-windows-x86_64`
3. Apply same post-steps as win-dir where relevant (emoji font download; icon is usually NSIS/sqgipkg concern — verify output)
4. Print path: `dist-windows-x86_64/OLLMchat-Setup.exe`

**Usage:**

```bash
scripts/package-windows-nsis.sh
scripts/package-windows-nsis.sh --clean
scripts/package-windows-nsis.sh --debug    # if sqgipkg supports --windows-console for NSIS staging
```

**Host prerequisites:** Part 1 deps **plus** `nsis` (`sudo apt-get install nsis`).

**Relationship to win-dir:**

| Target | Output | Use |
|--------|--------|-----|
| `win-dir` | `dist-windows-x86_64/OLLMchat/` | Dev, Wine, portable copy to Windows |
| `win-nsis` | `dist-windows-x86_64/OLLMchat-Setup.exe` | Installer matching release asset |

Both can share the same `build-windows-x86_64/` compile tree; running win-nsis after win-dir should be incremental (sqgipkg rebuilds only what changed).

---

## Documentation split

### Keep in `docs/creating-releases.md`

- Tag push → GitHub Actions Release workflow
- What assets CI publishes (AppImage, Setup.exe, debs)
- Installing debs from a release
- Manual workflow_dispatch (artifacts only, no publish)
- Re-upload / `--clobber` behavior
- Link to Windows build doc for local builds

### Move to `docs/building-windows.md` (this file, promoted when done)

- All three parts above (prerequisites, scripts, run commands)
- Artifact layout diagram
- Wine vs native Windows expectations
- Troubleshooting (wrong folder, missing DLLs, fontconfig/emoji)

### Move to `docs/building-linux.md` (new, small)

Extract from creating-releases.md § “Local packaging”:

- AppImage: `sqgipkg --target appimage --appimage-arch …`
- Debian: faiss-from-Debian preamble + `dpkg-buildpackage` (or link README.packaging.md)

creating-releases.md then ends with: *“For local builds see [building-windows.md](building-windows.md) and [building-linux.md](building-linux.md).”*

---

## Implementation checklist

### Scripts

- [ ] **T1** — `scripts/run-windows-wine.sh`; refactor `build-windows-dir.sh --wine` to call it
- [ ] **T2** — `scripts/stage-windows-portable.sh` (zip helper)
- [ ] **T3** — `scripts/package-windows-nsis.sh`
- [ ] **T4** — (optional) `scripts/windows-build-common.sh` — sqgi resolve/install, deps check, emoji font — shared by build + package scripts

### Docs

- [ ] **D1** — Trim [creating-releases.md](../creating-releases.md): remove § “Local packaging”, add links
- [ ] **D2** — Promote this plan to [building-windows.md](../building-windows.md) when scripts land
- [ ] **D3** — Add [building-linux.md](../building-linux.md) for AppImage/deb local builds
- [ ] **D4** — One-line pointer from root README if it mentions building (optional)

### Verification

- [ ] **V1** — `build-windows-dir.sh` → `run-windows-wine.sh --debug` launches under Wine
- [ ] **V2** — Zip → copy to Windows VM → `OLLMchat.ps1` (Bypass) runs without install
- [ ] **V3** — `package-windows-nsis.sh` → installer runs on Windows VM
- [ ] **V4** — CI release workflow unchanged (still `sqgipkg --target win-nsis` in Actions)

---

## Quick reference (target end state)

```bash
# Linux dev loop
scripts/build-windows-dir.sh --debug --wine

# Re-run without rebuild
scripts/run-windows-wine.sh --debug

# Ship folder to Windows PC
scripts/stage-windows-portable.sh
# … copy dist-windows-x86_64/OLLMchat-portable.zip …

# Local installer (same as CI release asset)
scripts/package-windows-nsis.sh
```

On Windows after unzip:

```powershell
cd OLLMchat
powershell -NoProfile -ExecutionPolicy Bypass -File .\OLLMchat.ps1 --debug
```
