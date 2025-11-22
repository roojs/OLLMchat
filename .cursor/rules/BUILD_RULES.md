# Build Instructions

## Building the Project

**IMPORTANT:** Always use `ninja -C build` to build this project. Do NOT use `valac` directly - the build system handles all compilation through Meson/Ninja.

### Standard Build
```bash
ninja -C build
```

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

