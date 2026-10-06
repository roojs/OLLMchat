# Pairing — hello says certificate not registered

**Status:** ⏳ per-server PEM directory is in the tree — await a phone pair against two desktops

**Device:** SM-S9380, `adb-R5CY134DA0W`.  
**Related:** ℹ️ `docs/bugs/2026-10-05-android-pair-listen.md`, `ollmapp/android/FileConnectionAdd.vala`, `ollmfilesd/ClientCert.vala`, `ollmfilesd/SslConnection.vala`

---

## Problem

- **🔷** The phone shows the six digits. Filling them in answers `certificate not registered`.
- **🔷** The same phone paired this morning. It failed after `ollmchat` started a new `ollmfilesd` at 15:56.

Reproduction: desktop Allow New Device, phone Add Remote Desktop, type the six digits, Request.

---

## Evidence

- **✔️** Phone logcat pid 30871, 15:59:24.578: `FileConnectionAdd.vala:91: certificate not registered`.
- **✔️** Daemon `~/.cache/ollmchat/ollmfilesd.debug.log` at that second: `recv id=0 method=RPC-Daemon.hello`, then `Unexpected early end-of-stream`. No `ClientCert.request_registration` in this process (started 15:56:52, pid 2605718).
- **✔️** Phone files under `files/share/ollmchat/`: `client.pem` and `ollmrpc-ca.pem` are both 10:29. Leaf is `CN=ollmchat-device`, issuer `CN=OLLMrpc Product CA`, notBefore `Oct 6 02:29:19 2026 GMT`. DER SHA-256 is `a3122940d1349a64066ba612356df53c3dbcd4662f8ea4c5ab23c0a63770f58a`. Key modulus matches `client-key.pem`.
- **✔️** `~/.local/share/ollmchat/files.sqlite` `client_cert` has five `status = 1` rows. Created times are all 2026-10-05 07:10–07:40 UTC. None is that DER hash. File mtime is 11:26.
- **✔️** `FileConnectionAdd.request` calls `ClientCert.request_registration` only when `ollmrpc-ca.pem` is absent. The PIN text is not read on this path. Hello is what `SslConnection.allow_request` rejects when the fingerprint is missing.
- **✔️** `SQ.Database` keeps sqlite in memory. `Query.insert` does not set `is_dirty` and does not call `backupDB`. Disk updates on the 60s dirty timer, or `OllmfilesdApplication.cleanup` → `backup_real`. The 15:56 start found no running daemon (`pid_running=false`) and loaded the 11:26 file.

---

## Root cause

- **🔷** PEM paths were `client.pem` and `ollmrpc-ca.pem` for every desktop. A second server reused the first server’s certificate, and hello answered `certificate not registered`.
- **✔️** The phone skipped `request_registration` because that one CA file already existed.

---

## Fix

- **✔️** The desktop writes `server-id` once under the user data directory and publishes TXT `id` on `_rpc._tcp`.
- **✔️** 16:49 `/usr/bin/ollmchat` SIGSEGV in `avahi_string_list_reverse` from `add_service_full_strlist`. That C function takes an `AvahiStringList`, and the Vala binding passed the `id=` string. Publish now uses `add_service_full`, freezes the record, sets `id`, commits, then thaws.
- **✔️** The phone keeps that desktop’s PEMs in `{user_data}/ollmchat/{id}/`. A second desktop’s id is a different directory.
- **🚫** Do not key the directory on the host or the certificate fingerprint. The id is the mDNS TXT value.

## Next

- **⏳** **🔷** Rebuild the desktop app and the APK. Open Allow New Device so the broadcast includes `id`. Pair the phone. Pair a second desktop and confirm the first desktop’s directory is still there.
