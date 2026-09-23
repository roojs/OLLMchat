# File connection Request: stale config snapshot

**Status:** ✔️ fix applied (live `config` before present + success toast)

**Pointer:** `docs/bug-fix-process.md`

## Problem

- 🔷 Phone Add file connection → Request. Dialog disappears at once;
  no **Requested** row; desktop never shows Accept.
- 🔷 If there is no answer, show **Could not connect**, do not close
  the add dialog.
- 🔷 ✔️ `can_close = true` immediately after failure dismissed the add
  dialog; keep `can_close` false until idle, re-`present`, then allow close.
- 🔷 Restart after filling the LLM connection loses that config.

## Evidence

- ✔️ 17:20:35 hang was TLS + fingerprint then silence (`bin_body`).
- ✔️ 17:51 on-device `config.2.json` after Request:

      "connections" : {    },
      "filesd-client" : { "url" : "https://192.168.88.132:8443" }

  LLM connection gone; only the filesd URL remains.
- ✔️ Android constructs `settings_dialog` in the window ctor
  (`OllmchatWindow.vala` ~130) **before** `load_config()` replaces
  `app.config`. ConnectionsPage then
  `new FileConnectionAdd(this.dialog.app.config)` holds that **empty**
  `Config2`. Bootstrap / load assign a **new** object to `app.config`.
- ✔️ Request success does `this.config.save()` + `force_close()` on
  the empty snapshot → wipes disk; `render_file_connection()` reads
  live `app.config.filesd_client.url` (still empty) → no row.
- 💩 Timeout / `can_close` / JSON body never visible as “Could not
  connect” because success `force_close` runs on the snapshot path.

## Root cause

- ✔️ FileConnectionAdd keeps the Config2 passed at Settings
  construct (empty on Android). Saving that object overwrites the
  real config. The Requested row looks at a different object, so it
  never appears. Restart loads the wiped file.

## Proposed fix

- ✔️ `FileConnectionAdd()` builds UI only; `ConnectionsPage` saves live
  `app.config` in `on_file_add_closed` from `registered_url` (same as
  `ConnectionAdd` / `verified_connection`).

## Attempts / changelog

- ✔️ CertAsk + remote-address qdata (earlier).
- ✔️ 2026-09-22 17:20 — hang + swapped insert + silent close.
- ✔️ 17:43 APK — JSON / timeout / insert; Request still vanished;
  config wiped on save of construct-time empty Config2.
- ✔️ 17:53 — ConnectionAdd-style redesign applied then **reverted**
  (needs approval).

## Post-approval Check (2026-09-23)

- 🔷 After desktop **Accept**, main-window banner: tap **Check** on the phone.
- ✔️ **Check** only verifies hello + sets `approved` (no `replace_rpc` in
  settings flow). Use **Enabled** toggle or restart to connect live.
- ✔️ Local Unix fallback on reconnect failure is desktop-only (`#if !ANDROID`).
- ✔️ Repeat **Request** with the same cert fingerprint returns ok (like a
  check); new fingerprints from one IP still cap at three pending rows.
- ✔️ Main window banner when a registration arrives while settings are closed.

## Next

- 🔷 User verify on device: Request → pending toast, **Requested** row,
  config persists after restart; Accept → banner; Check → **Active** without crash.
