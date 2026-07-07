# Build Instructions

Canonical build workflow for this project. Written for **AI agents** — **mandatory** for agents building or changing the project. Human contributors may treat this as a helpful guide. See also **`docs/coding-standards.md`**.

## Building the Project

**IMPORTANT:** Always use `ninja -C build` to build this project. Do NOT use `valac` directly - the build system handles all compilation through Meson/Ninja.

### Standard Build

V2 is the only supported build (`v2testing=true`, the default). Plain `meson setup build` builds the RPC + `ollmfilesd` app and vector CLI examples.

```bash
ninja -C build
```

Shipping v1 (`-Dv2testing=false`) was removed; Meson fails at configure time if you pass it.

### Rebuilding After Changes

If the build system doesn't detect file changes, reconfigure and rebuild:
```bash
meson setup --reconfigure build
ninja -C build
```

### Initial Setup
```bash
meson setup build --prefix=/usr
ninja -C build
```

## Notes
- The build system uses Meson and Ninja
- All Vala files are compiled through the Meson build system
- Never call `valac` directly - always use `ninja -C build`

