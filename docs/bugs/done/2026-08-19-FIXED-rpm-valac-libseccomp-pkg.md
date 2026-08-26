# FIXED: RPM / Debian valac — `Package libseccomp not found`

**Status:** ✅ FIXED — native Meson uses `cc.find_library('seccomp')`; Fedora RPM shipped. User closed.

**CI:** [32208958343](https://github.com/roojs/OLLMchat/actions/runs/32208958343) (Fedora), [32208715029](https://github.com/roojs/OLLMchat/actions/runs/32208715029) (Tumbleweed), [32208925906](https://github.com/roojs/OLLMchat/actions/runs/32208925906) (Debian)

---

## Problem

GitHub **Release - Fedora** / **openSUSE** / **Debian** died at valac:

```text
error: Package `libseccomp' not found in specified Vala API directories or GObject-Introspection GIR directories
```

## Root cause

`libseccomp_pc.partial_dependency(...)` still injected `--pkg libseccomp` on Meson 1.11. Distros do not ship that vapi. In-tree is `vapi/seccomp.vapi` (`--pkg=seccomp`).

## Fix

`config/meson.build` native branch matches sysroot: `declare_dependency` wrapping `cc.find_library('seccomp')` plus `-I` from pkg-config `includedir`. Do not put `dependency('libseccomp')` in Vala `dependencies:`.
