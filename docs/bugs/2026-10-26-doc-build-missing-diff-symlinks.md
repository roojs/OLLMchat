# GitHub valadoc job fails: Diff sources missing

**Status:** ✔️ symlinks restored locally. Not pushed.

## Problem

- 🔷 [X - Publish Valadoc to GitHub Pages](https://github.com/roojs/OLLMchat/actions/runs/40279488012) on `dd8c2ca0` failed in **Setup meson build**.
- 🔷 Expected: `meson setup build --prefix=/usr -Dtests=false` configures, then `ninja -C build docs/valadoc` publishes.

## Evidence

- ✔️ Job log: `libocfiles/meson.build:39:18: ERROR: File Diff/Patch.vala does not exist.`
- ✔️ `dd8c2ca0` deleted the three symlinks (`mode 120000`): `libocfiles/Diff/Patch.vala`, `Differ.vala`, `PatchApplier.vala`.
- ✔️ The real sources stayed in `ollmfilesd/Diff/`. `libocfiles/meson.build` and `docs/meson.build` still list the old paths. Callers still use `OLLMfiles.Diff` (`liboccoder/SourceView.vala`, `liboccoder/Diff/ReviewBar.vala`, `examples/oc-test-source-diff.vala`, `examples/oc-diff.vala`).
- ℹ️ Parent `cefcdc2c` had `libocfiles/Diff/*.vala` → `../../ollmfilesd/Diff/*.vala`, as in `docs/plans/CODER-4.2.3.5.5-DONE-source-view-diff-items.md`.

## Root cause

- ✔️ The merge commit removed the deprecated `libocfiles/Diff` symlinks and left the Meson source lists pointing at them. Configure stops on the first missing file.

## Proposed fix

- 🔷 Restore the three symlinks from `cefcdc2c`. Do not drop the Meson entries. The old client diff still compiles through `libocfiles`.

```
git restore --source=cefcdc2c --worktree -- libocfiles/Diff
```

## Attempts

- ✔️ Restored from `dd8c2ca0^` (`cefcdc2c`). Each name is a symlink to `../../ollmfilesd/Diff/`, and each target exists.
- ✔️ Every `.vala` path in `docs/meson.build` and `libocfiles/meson.build` exists again.
