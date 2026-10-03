# libocrpc-dev / libocrpc-devel do not ship `ocrpc.h`

**Status:** ✔️ archived 2026-10-03 — `ocrpc.h` is on the Debian and RPM dev file lists. Left open only for a post-1.4.0 `dpkg -c` / `rpm -qlp` check that was never run.

**Related:**

- **ℹ️** Found by gnome-shell-rpc packaging: `gnome-shell-rpc/docs/plans/1.1-installable-bootable-session.md` (Phase 2). Its Debian and RPM CI build against the roojs `libocrpc-dev` / `libocrpc-devel`.

---

## Problem

- **🔷** A project outside this tree that builds against the packaged `libocrpc` (Vala or C) cannot compile.
- Expected: `libocrpc-dev` / `libocrpc-devel` give everything a consumer needs: `libocrpc.so`, `ocrpc.vapi`, `ocrpc.h`.
- Actual: the packages ship `ocrpc.vapi` but not `ocrpc.h`. Every vapi symbol has `[CCode (cheader_filename = "ocrpc.h")]`, so valac’s C output `#include "ocrpc.h"` fails.

## Evidence

- **ℹ️** `libocrpc/meson.build`: `vala_header: 'ocrpc.h'` with `install_dir: [true, true, false]`, so `meson install` puts `usr/include/ocrpc.h` in the destroot.
- **ℹ️** `debian/libocrpc-dev.install` lists only `usr/share/vala/vapi/ocrpc.vapi`. The built `debian/libocrpc-dev/` has no `usr/include`. dh 13 only warns about installed-but-unpackaged files, so the header is dropped silently.
- **ℹ️** `packaging/rpm/ollmchat.spec` `%files -n libocrpc-devel` lists only `%{_datadir}/vala/vapi/ocrpc.vapi`.
- **ℹ️** Builds against a local `meson install` work because that put `/usr/include/ocrpc.h` on the machine. Only the packaged path fails.
- **ℹ️** `ocrpc.h` is the only C header this tree installs. The other libraries do not install theirs, so this is libocrpc only.

## Root cause

- **✔️** The `-dev` / `-devel` file lists were not updated when `ocrpc.h` started installing.

## Proposed fix

**💩** Add the header to both file lists.

#### Replace with — `debian/libocrpc-dev.install`

```text
usr/share/vala/vapi/ocrpc.vapi
usr/include/ocrpc.h
```

#### Replace with — `packaging/rpm/ollmchat.spec` (`%files -n libocrpc-devel`)

```text
%files -n libocrpc-devel
%{_datadir}/vala/vapi/ocrpc.vapi
%{_includedir}/ocrpc.h
```

## Attempts / changelog

- **✔️** `debian/split/libocrpc-dev.install` and the live `debian/libocrpc-dev.install` now list `usr/include/ocrpc.h`. CI runs `debian/use-split-packages.sh`, which copies `debian/split/` over the live install files, so the split copy is the one that ships.
- **✔️** `packaging/rpm/ollmchat.spec` `%files -n libocrpc-devel` now lists `%{_includedir}/ocrpc.h`. That `%files` block is inside `%if %{with local_gguf}`. The remote-only build still `rm -rf %{buildroot}%{_includedir}` and does not ship `libocrpc-devel`.

## Next

- **✔️** File lists and `CHANGELOG.md` already install `ocrpc.h`. The v1.4.0 remote-only `dh_missing` for that header is recorded in [`2026-10-02-FIXED-v140-release-jobs.md`](2026-10-02-FIXED-v140-release-jobs.md) and fixed there (`debian/monolithic/ollmchat.install`, `debian/monolithic-remote-only/ollmchat-remote-only.install`, RPM `%{_includedir}/ocrpc.h`).
- **🚫** The built `.deb` / `.rpm` were not listed with `dpkg -c` / `rpm -qlp` in this log. User closed it 2026-10-03.
- **✔️** Archived to `docs/bugs/done/`.
