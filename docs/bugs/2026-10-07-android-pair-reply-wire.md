# Android pairing reply fails before certificate storage

**Status:** ⏳ historical phone failure not reproduced on the emulator with matching current client/server builds; do not change the codec without a matching-build reproduction

**Devices:** SM-S9380 physical phone for the original failure; `emulator-5554` for the controlled current-build flow.
**Related:** ℹ️ `docs/bugs/done/2026-10-05-CLOSED-android-pair-listen.md`, `docs/bugs/2026-10-06-android-live-rpc-read-watch.md`, `ollmapp/android/FileConnectionAdd.vala`, `tests/rpc/filesd-pair-test.vala`, `android/pair-listen-probe/`

---

## Problem

- **🔷** Test the complete pairing flow on Android before changing product code: discovery, PIN registration, signed certificate and CA storage, authenticated hello, live connection, Agent Pi availability, and the daemon approved-device list.
- **🔷** On the physical phone, the first Request reported `expected object type byte, got 0x08`; a second Request reported `Server required TLS certificate`.
- **🔷** The physical-phone failure did not add Agent Pi or update the connection state.

Original phone reproduction: uninstall the APK installed from the other machine, install the fresh local APK, open Allow New Device, open Add Remote Desktop, enter the six digits, and press Request twice.

## Evidence

- **✔️** Fresh APK built 2026-10-07 08:17 and installed after removing the differently signed phone APK.
- **✔️** Phone logcat 08:20:24.242: `FileConnectionAdd.vala:96: expected object type byte, got 0x08`.
- **✔️** Daemon at 08:20:24.550 received `ClientCert.request_registration`; at 08:20:24.553 it emitted `event.pair`; the daemon then logged `Unexpected early end-of-stream`.
- **✔️** Phone server directory `9990d325-cda3-40f0-9718-8776736497ce` contained only `client-key.pem`, `client.csr`, and the original `client.pem`; it did not contain `ollmrpc-ca.pem`.
- **✔️** Phone `config.2.json` still had empty `filesd-client.url`, `addresses`, and `server-id`, with state `0`.
- **✔️** Phone logcat 08:20:30.066: `Server required TLS certificate`; daemon at 08:20:30.377: `ssl handshake failed: TLS connection peer did not send a certificate`.
- **✔️** The second phone message was downstream of the first parse failure: no CA was stored, so the retry had no client certificate after pairing had closed.
- **✔️** The daemon used for the original phone failure had a deleted build-tree `libocrpc.so` mapped while the phone contained the fresh 08:17 Android library.
- **✔️** Restarted `ollmfilesd` with the current build-tree `libocrpc` and armed it directly through its Unix socket with PIN `438217`; no desktop app was running.
- **✔️** Published `_rpc._tcp` directly and used the installed app on `emulator-5554`; it discovered `192.168.0.16:8422`, submitted one pairing request, and showed `Remote Desktop: tcp://192.168.0.16:8422` as `Active`.
- **✔️** Emulator logcat at 08:54:03.960 showed filesd state `SOCKET`; Agent Pi became visible and the agent model contained `agent-pi`, `just-ask`, and `chatter`.
- **✔️** A direct local Unix RPC call to `ClientCert.approved_certs` returned the new in-memory row `id=13`, fingerprint `667ce677c5804524c74b4a124143301cb162cf13200602813af3d6a49aa18da3`, requester `ollmchat`; the daemon approved-device list contained 13 rows.
- **✔️** The matching-build emulator flow produced neither `expected object type byte, got 0x08` nor `Server required TLS certificate`.
- **✔️** `android/pair-listen-probe/` still tests only `_rpc._tcp` discovery and PIN-field visibility; there is no standalone Android test app for the complete pairing and sync flow.

## Root cause

- **✔️** `Server required TLS certificate` is a downstream symptom, not the root defect.
- **✔️** The current Android reply parser and current daemon codec interoperate for the complete emulator flow, so the evidence rules out an unconditional current-code Android `0x08` parser defect.
- **💩** The original `0x08` failure is most consistent with the stale daemon/client protocol mismatch, but the exact stale server revision and emitted registration-reply bytes were not preserved, so that attribution is not yet proven.

## Proposed changes

- **🔷** Keep the direct test controls in `tests/rpc/filesd-pair-test.vala`: `--arm-only` arms pairing without the desktop UI and `--list-approved` verifies the daemon's live approved-device list.
- **🔷** Add a standalone Android full-flow test that records discovery, registration reply parsing, certificate persistence, authenticated hello, filesd state, and Agent Pi visibility.
- **🚫** Do not replace `GLib.IOChannel` or alter the shared RPC codec based on the historical `0x08` result; reproduce the failure with matching current binaries and capture the raw reply before proposing such a change.

## Attempts / changelog

- **✔️** Captured physical-phone logcat, daemon log, certificate directory, and config after the failed requests.
- **✔️** Restarted the daemon on the current library and stopped the mistakenly started desktop app.
- **✔️** Completed the controlled current-build flow on `emulator-5554` using only the app, direct daemon Unix RPC, direct Avahi publication, and log capture.
- **✔️** Extended `test-rpc-filesd-pair` with direct `--arm-only` and `--list-approved` operations.

## Next

- **🔷** ⏳ Add the standalone Android full-flow test app so this flow is repeatable without driving the product UI.
- **💩** ⏳ If the physical-phone failure recurs against the current daemon, capture the first registration-reply bytes and both type registries before changing product code.
