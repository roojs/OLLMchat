# WIP checkpoint: local TLS iteration (paused 2026-06-17)

Paused to run gtk-fixes POC PR validation (IME + paste harness at `gtk.wrap` `af83724a96`).

## Contents

- `tracked.patch` — all modified tracked files at pause time
- `untracked/` — copies of new files (harness scripts, `AndroidGtkFixesPoc.vala`, etc.)
- `android-gio-tls.c` / `.h` / `AndroidGtkFixesPoc.vala` — TLS-only harness + app TLS init
- `giomodule.c.local` — debug GLib with ensure-before-scan + `OLLMchat-GIO` logging
- `gdkandroidruntime.c.local` — GDK post-scan TLS probe

## Resume TLS work

```bash
git checkout wip/android-tls-local-2026-06-17
# or: git apply android/wip-patches/2026-06-17-tls-local-iteration/tracked.patch
```

Device-verified on this branch: `GTlsBackendOpenssl`, harness `ready=true` (with local GLib + app fixes).
