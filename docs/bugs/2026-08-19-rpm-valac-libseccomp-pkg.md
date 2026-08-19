# RPM / Debian valac: `Package libseccomp not found`

**Status:** ⏳ ✔️ Fedora 44 RPM build green after Meson fix — await user verify / GitHub CI

## Problem

🔷 GitHub **Release - Fedora**, **Release - openSUSE**, and **Release - Debian** fail at compile:

```text
error: Package `libseccomp' not found in specified Vala API directories or GObject-Introspection GIR directories
```

🔷 Expected: same in-tree `vapi/seccomp.vapi` (`--pkg=seccomp`) used on native Meson builds.

## Evidence

- ℹ️ CI: `gh run view 32208958343` (Fedora), `32208715029` (Tumbleweed), `32208925906` (Debian) — same valac error.
- ✔️ Fedora 44 host `192.168.88.14:8022`, `./scripts/ci/build-rpm.sh`. Failed valac line for `libocbwrap` includes both `--pkg libseccomp` and `--pkg=seccomp` plus `vapi/seccomp.vapi`.
- ℹ️ `config/meson.build` already warned not to pass `dependency('libseccomp')` into Vala; native path used `partial_dependency()`, which still injects `--pkg libseccomp` on Meson **1.11.2** (Fedora 44).
- ℹ️ Sysroot/sqgipkg path already uses `cc.find_library('seccomp')` + compile args and does not leak `--pkg libseccomp`.

## Root cause

✔️ `libseccomp_pc.partial_dependency(...)` remains a pkg-config-named dep for Vala on Meson 1.11. valac looks for a **system** `libseccomp` vapi/GIR; this distro does not ship one. The in-tree vapi is named `seccomp`.

## Proposed fix

🔷 Match the sysroot branch: `declare_dependency` wrapping `cc.find_library('seccomp')` and `-I` from pkg-config `includedir`. Do not put the pkg-config `dependency('libseccomp')` object in Vala `dependencies:`.

#### Replace with (`config/meson.build` native `else` branch)

`declare_dependency(dependencies: [cc.find_library('seccomp')], compile_args: ['-I' + includedir])`

## Attempts

- ✔️ Native branch switched off `partial_dependency()` (this log’s apply).
- ✔️ Fedora 44: `ninja -C build` then `./scripts/ci/build-rpm.sh` — split `.fc44.` RPMs in `/home/alan/OLLMchat/artifacts/` (no valac `libseccomp` package error).
