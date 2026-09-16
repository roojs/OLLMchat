# libocrpc install: `.so` + `.vapi` but no `ocrpc.h`

**Status:** ✔️ fix applied + DESTDIR gate PASS — await system reinstall / gnome-shell-rpc verify  
**Hit:** 2026-09-16 — gnome-shell-rpc switched `-Docrpc_libdir=` to use the
installed library; C compile dies on `#include <ocrpc.h>`  
**Component:** `libocrpc/meson.build` — `library(... vala_header: 'ocrpc.h',
install: true)` + `custom_target('ocrpc-vapi')`  
**Consumer evidence:** gnome-shell-rpc meson with empty `ocrpc_libdir`

---

## Problem

🔷 After `ninja install` (prefix `/usr`), consumers must be able to build
against the **installed** libocrpc the same way as any other Vala/C library:

- `libocrpc.so` on the linker path  
- `ocrpc.vapi` on the default vapidir  
- **`ocrpc.h` on the default include path** (`#include <ocrpc.h>`)

🔷 Actual install (from `build/meson-logs/install-log.txt`):

```
/usr/lib/x86_64-linux-gnu/libocrpc.so
/usr/share/vala/vapi/ocrpc.vapi
```

**No** `/usr/include/ocrpc.h` (also absent under `/usr/local/include`).

🔷 Expected: `ocrpc.h` installed to `${prefix}/include` (or the configured
`includedir`).

Reproduce on a machine that just installed OLLMchat libocrpc:

```bash
ls /usr/lib/x86_64-linux-gnu/libocrpc.so
ls /usr/share/vala/vapi/ocrpc.vapi
ls /usr/include/ocrpc.h   # missing → FAIL
```

Consumer fallout (gnome-shell-rpc, system ocrpc):

```text
fatal error: ocrpc.h: No such file or directory
    4 | #include <ocrpc.h>
```

That forces `-Docrpc_libdir=…/OLLMchat/build/libocrpc` (build tree has the
header next to the `.so`) — wrong for an installed library.

---

## Evidence

✔️ 2026-09-16 — install log lists only `.so` + `.vapi` for ocrpc (no header).

✔️ `intro-targets.json` for `ocrpc` shared library install filenames:

```text
['/usr/lib/x86_64-linux-gnu/libocrpc.so', None, None]
```

Two `None`s — header (and related) slots not populated for install.

✔️ Header **is** built: `build/libocrpc/ocrpc.h` exists. It is just not
installed.

✔️ `libocrpc/meson.build` today:

- `library('ocrpc', … vala_header: 'ocrpc.h', install: true)` — expects
  Meson/Vala to install the generated header; it does not (this tree /
  this Meson+Vala combo).
- Separate `custom_target('ocrpc-vapi')` runs `valac … --header
  meson.current_build_dir() / 'ocrpc.h' --vapi @OUTPUT@` with
  `install: true` / `install_dir: …/vala/vapi` — **only the `.vapi`
  output is installed**, not the `--header` file.

ℹ️ Same install-log pattern for sibling libs (`ocsqlite`, `ocmarkdown`, …):
`.so` + `.vapi`, no C headers. ocrpc is the urgent consumer break; fix
the pattern there first (or share one install_headers helper).

---

## Root cause

✔️ Meson Vala `library(... install: true)` with only one install slot
installs the `.so` only. Introspection shows:

```text
filename: [libocrpc.so, ocrpc.h, ocrpc-meson.vapi]
install_filename: [/usr/lib/.../libocrpc.so, None, None]
```

Secondary outputs (header / meson vapi) are installed only when
`install_dir` is a list whose length matches the output count, and the
header slot is `true` (or an explicit includedir). Meson’s ninja backend
then maps `install_dir[1] is True` → `get_includedir()`.

✔️ `install_headers(builddir / 'ocrpc.h')` is **not** viable here: Meson
1.7 `install_headers` only accepts source `File`/string paths (strict),
not generated build-tree headers.

✔️ The separate `custom_target('ocrpc-vapi')` installs only `@OUTPUT@`
(`.vapi`), not the side-effect `--header` file — expected; the library’s
`vala_header` is the install source of truth for `ocrpc.h`.

---

## Proposed fix

🔷 On `ocrpc_base_lib`, pass Vala multi-output `install_dir` so the
header installs to includedir; skip installing `ocrpc-meson.vapi`
(consumers use custom-target `ocrpc.vapi`).

### `libocrpc/meson.build` — `library('ocrpc', …)`

#### Replace

```meson
  install: true,
)
```

#### Replace with

```meson
  install: true,
  install_dir: [true, true, false],
)
```

🚫 Do not tell consumers to keep `-I` pointed at the OLLMchat **build**
directory. That is the workaround, not the fix.

🚫 Do not use bare `install_headers(meson.current_build_dir() / 'ocrpc.h')`
— configure rejects / will hard-error generated build paths.

ℹ️ Optional follow-up: same `install_dir: [true, true, …]` for other
`liboc*` Vala libs that ship a C header via `vala_header`.

---

## Gate (FAIL → PASS)

```bash
test -f /usr/include/ocrpc.h
echo $?   # 1 today after ninja install; 0 when fixed
```

Or from gnome-shell-rpc (after fix + reinstall):

```bash
meson setup build --reconfigure -Docrpc_libdir=
ninja -C build tests/call-sync-repro/value-v-gate
# must not die on missing ocrpc.h
```

---

## Attempts / changelog

- ⏳ 2026-09-16 — Filed from gnome-shell-rpc (system `-Docrpc_libdir=`).
  No libocrpc code change from that tree. Header missing on install is
  the blocker.
- ✔️ 2026-09-16 — Root cause refined via `intro-targets.json` + Meson
  1.7 ninjabackend (`install_dir[1] is True` → includedir). Applied
  `install_dir: [true, true, false]` on `library('ocrpc', …)`.
- ✔️ 2026-09-16 — `DESTDIR=/tmp/ocrpc-install-check ninja -C build install`:
  `…/usr/include/ocrpc.h` present; introspect now
  `install_filename: […/libocrpc.so, /usr/include/ocrpc.h, None]`.

---

## Next

⏳ Real `ninja install` (prefix `/usr`) + gnome-shell-rpc empty
`ocrpc_libdir` build.  
⏳ Consider the same hole for other `liboc*` installs.
