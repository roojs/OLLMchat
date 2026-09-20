# File Server subtitle Off while running; apply only on dialog close

**Status:** ✅ FIXED — user archived 2026-09-20 with [`RPC-8.2.8.3`](../../plans/done/RPC-8.2.8.3-DONE-filesd-file-server-tls.md)  
**Hit:** 2026-09-20 — Preferences → Connections → File Server  
**Component:** `ollmapp/SettingsDialog/FileServerRow.vala`

---

## Problem

🔷 Subtitle said **Off** while the Unix file server was running.

🔷 Listen changes applied only on dialog close. Toggles and Port should apply when they differ from the last saved `filesd`.

🔷 systemd on/off is a handoff (disable `--now` then manual start, or kill manual then enable `--now`). Toast stay-up on the Connections tab — **no** `Alert.show`.

🔷 HTTPS is a second listener. Turning Enabled off must not stop the Unix socket, wipe Host/Port/Proxy/systemd, or hide systemd (systemd stays visible so it can be toggled with HTTPS off).

---

## Root cause

✔️ Subtitle was `"Off"` unless `filesd.enabled && filesd.https != ""`. Unix-only running looked Off.

✔️ `apply_config` / `reboot` ran only from `MainDialog.on_closed`. `reboot` was always `kill` + `ensure_daemon` + `Alert.show`.

---

## Landed

- ✔️ Subtitle: **Not running** / **Running (socket only)** / **Running (socket and HTTPS)** / **on startup** / **via systemd**.
- ✔️ Toggles and Port blur call `apply_config`; save + `reboot` when listen fields changed.
- ✔️ systemd ↔ manual handoff; stay-up via `ClientBoot.connectable()`, wait 2s, probe again.
- ✔️ Toasts on `Adw.ToastOverlay` (`timeout = 2`). Stay-up success toasts the expander subtitle (`Running … (socket only)` / `(socket and HTTPS)`), not `File server stopped`. Killing the app without dialog close leaving widget edits is default.
- ✔️ Enabled off hides Host / Port / Proxy only. systemd row stays shown and is always written.
