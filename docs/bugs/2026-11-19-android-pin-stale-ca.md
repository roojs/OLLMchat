# Android PIN submit keeps the stale desktop certificate

**Status:** ⏳ OPEN — PIN retry path crashes without `TlsClient` mutex init (fixed in tree); phone re-test pending.

**Started:** 2026-11-19

**Package:** `org.roojs.ollmchat.androidpoc` on SM-S9380.

## Problem

- 🔷 Entering the desktop PIN should register the phone.
- 🔷 Actual: the dialog says "Could not reach the desktop." The user saw more than one attempt and thought the desktop was slow to answer.

## Evidence

- ✔️ Phone log, pid 21461, 09:41:35, 09:41:42, and 09:42:00. Each press logs `FilesdClient.vala:243: Unacceptable TLS certificate` and then `FileConnectionAdd.vala:99: Could not reach the desktop.` The two lines are the same millisecond. This is not the 10-second connect timeout.
- ✔️ Line 243 is the `ClientCert.pair` handshake in `complete_pairing`. That runs only when `ollmrpc-ca.pem` is already on the phone. `request_registration` is the other branch and logs at line 165.
- ✔️ The phone has a certificate directory `9990d325-cda3-40f0-9718-8776736497ce` dated 2026-10-31. The desktop CA `~/.local/share/ollmchat/tls/server-ca.pem` is dated 2026-11-14.
- ✔️ `FileConnectionAdd.request` repeats the call with `force_register` only for `CERT_NOT_REGISTERED`. A handshake failure is `INTERNAL_ERROR`, so the PIN is never sent.
- 🚫 A delay or a second registration RPC is not what this log shows.

## Root cause

- ✔️ The stored CA does not match the desktop certificate. The PIN submit uses that CA, the handshake rejects the desktop, and the dialog describes the TLS failure as unreachable.

## Proposed fix

- 🔷 On the first failure, `CERT_NOT_REGISTERED` and `INTERNAL_ERROR` both take the existing `force_register` path, which sends the PIN and replaces the stored CA.

#### Replace with

```vala
			if (!force_register) {
				switch (code) {
					case (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED:
					case (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR:
						force_register = true;
						continue;
					default:
						break;
				}
			}
```

File: `ollmapp/android/FileConnectionAdd.vala`, inside `request`, in place of the `CERT_NOT_REGISTERED` check.

## Pairing crash (2026-11-20)

- ✔️ Log: stale CA → `FilesdClient.vala:243: Unacceptable TLS certificate` → `g_mutex_clear` abort on GTK thread in `libocrpc` during `try_connection` retry.
- ✔️ `TlsClient` declared `GLib.Mutex` without `= GLib.Mutex()`; destructor aborts after the first failed `complete_pairing`.
- ✔️ 2026-11-22 — `TlsClient.call` unlocks the mutex when `Bin.Stream.parse` throws `StreamError.PROTOCOL` (not only `IOError`). `FilesdClient.try_connection` drops a stale `ollmrpc-ca.pem` when `force_register` is true. PIN field matches Argus `RegisterWindow` layout (not `ActionRow` suffix).

## IME numeric keyboard (2026-11-22)

- ✔️ Logcat: `IME onCreateInputConnection kind=GtkText inputType=0x1` — QWERTY, not `TYPE_CLASS_NUMBER`.
- ✔️ `getInputType()` uses `GtkIMContextAndroid.input_purpose` (default free-form), not `gtk_text_get_input_purpose()` on the focused `GtkText` entry.
- ✔️ 2026-11-22 — Pixie GTK comes from Knowles gtk `track: latest` (`resolve-pixie-gtk-pins.sh` queries GitLab at fetch). Drops the stale hand-pinned `20261110g` row.

## Post-pair reconnect (2026-11-22)

- ✔️ `probe_addresses` probed every daemon address in list order; phone hit `10.0.3.1`, bridges, then `expected object type byte, got 0x70` before the LAN host.
- ✔️ Pairing already sets `filesd_client.url`; probe now tries that `tcp://` host first.

## Next

- ✔️ 2026-11-19 — `FileConnectionAdd.request` now repeats with `force_register` after `INTERNAL_ERROR`. APK rebuilt and installed on SM-S9380.
- ✔️ 2026-11-20 — `TlsClient.mutex` initialized; unlock on `bin.write` failure.
- ✔️ 2026-11-22 — `FileConnectionAdd` follows Argus `RegisterWindow`: `registering` guard, `input_hints` for numeric IME, 1.5s auto-submit on sixth digit.
- ⏳ 🔷 Rebuild APK, install on SM-S9380, open Allow New Device, enter PIN (auto-submit after pause). Expect retry with `force_register` without crash.
