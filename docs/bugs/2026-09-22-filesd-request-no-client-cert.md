# File connection Request: stale config snapshot

**Status:** ✅ phone connection flow closed by the user (2026-09-23). Next step is Agent Pi, plan 8.2.8 Phase 10, not this bug.

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

## 2026-09-23 — blank IP, Check dies, row gone after restart

### Problem

- 🔷 Request succeeds: toast, dialog hides, desktop shows the device as
  requesting, Accept works.
- 🔷 The address on that display is blank. Not using PROXY.
- 🔷 After Accept, Check on the phone kills the app.
- 🔷 Restart: the file-connection row is gone.
- 🔷 ⏳ IPv4/IPv6 numeric storage: hold. Keep the address as text.

### Evidence

- ℹ️ Soup 3.6 `soup_server_message_get_remote_address` is documented as
  nullable when the connection came from `accept_iostream`. Non-proxy
  code does copy the TCP peer into that call
  (`HttpServer.vala` incoming handler). Cert still arrives via
  `get_tls_peer_certificate`, so a missing address does not block Request.
- ✔️ `ClientCert.client_cert` **accept** sets `ip = ""` before
  `updateById`. The approved expander and any later read of that row
  have no address even when the pending row had one.
- ℹ️ `libocsqlite` `setObjectProperty` supports INTEGER / INT64 / TEXT
  only. Any other column type hits `GLib.error` and aborts the process.
- ℹ️ SQLite has no `INET_ATON` / `INET6_ATON`. INTEGER is signed 64-bit.
  IPv4 fits. IPv6 is 128 bits and does not.
- ℹ️ MySQL `INET6_ATON` returns `VARBINARY(16)`, not an integer. The
  comparable form for both families is those 16 bytes with IPv4 stored
  as IPv4-mapped IPv6 (`::ffff:a.b.c.d`).
- ✅ Restart still shows the file-connection row (user, 2026-09-23).
- ✔️ Check crash, tombstone 17:15, GTK thread, fault addr 0x1:
  `strlen` ← `g_strdup` ← `g_value_set_string` ←
  `oll_mrpc_to_value` ← `oll_mrpc_args` ←
  `file_connection_row_check`. The integer `1` in
  `args("is", 1, "ollmchat")` was read as the string.
- ℹ️ The row the user sees is painted from memory after
  `Config2.save()`. Android settings **close** uses `persist_config()`;
  the add-dialog path uses `Config2.save()`. Both use
  `Config2.config_path` once `load_config` has set it.

### Root cause

- ✔️ Approved-row address is blank because Accept deletes `ip`.
- 💩 Pending-banner address is blank when Soup does not return the
  peer we passed to `accept_iostream`. Not yet read off a live row.
- ✔️ Check dies in `args("is", …)` before hello is sent. On
  aarch64 `va_list` is a struct passed by value, so `to_value`
  advances a copy and the next letter rereads the first argument.
  x86_64 passes `va_list` as a pointer, which is why desktop Check
  does not hit this. Request uses `args("s", …)`, one letter, so it
  does not hit this.

### Applied

- ✔️ Accept clears `ip` (approval is the cert, not that address).
  The approved expander shows Registered and the date, not an IP row.
- ✔️ Peer address is stored on the client cert and copied onto
  `reply.client_ip` when Soup's remote address is null.
- ✔️ Check sends bin hello (same as the filesd HTTP test). Android
  registers `OLLMfiles` and `ClientCert` at startup so that reply
  decodes. JSON hello of a `Daemon` retval hit a null `Stream.client`
  and killed the process.
- ✔️ Opening settings calls `render_connections`, which now rebuilds the
  file row from the loaded config. The dialog used to render that row
  once, before `load_config`. Saves stay `config.save()` on both
  platforms; Android `load_config` already sets `config_path`.
- ✔️ Android compiles `libocrpc/android/namespace.vala` instead of
  `namespace.vala` (meson, same swap as `android/Cert.vala`).
  `to_value` there takes `va_list*`. The desktop file is unchanged.

## Next

- ✅ User closed this flow (2026-09-23): Request, Accept, Check stays
  up, config row survives restart.
- 🔷 ⏳ Agent Pi on Android is [`RPC-8.2.8`](../plans/RPC-8.2.8-filesd-connections-ui.md) Phase 10. Split that before implementing.
