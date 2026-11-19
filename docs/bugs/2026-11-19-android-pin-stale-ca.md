# Android PIN submit keeps the stale desktop certificate

**Status:** ⏳ OPEN — fix written, phone install still to confirm.

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

## Next

- ✔️ 2026-11-19 — `FileConnectionAdd.request` now repeats with `force_register` after `INTERNAL_ERROR`. APK rebuilt and installed on SM-S9380.
- ⏳ 🔷 Open Allow New Device on the desktop and enter that PIN once. The first handshake still rejects the October certificate. The same press then sends the PIN.
