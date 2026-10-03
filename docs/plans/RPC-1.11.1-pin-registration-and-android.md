# RPC-1.11.1 — PIN registration and Android discovery

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan** until it is done and archived.

**Status:** proposed

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

**Parent:** [`RPC-1.11-URGENT-vpn-local-pin-pairing.md`](RPC-1.11-URGENT-vpn-local-pin-pairing.md) — Phases 3 and 4

**Depends on:** Phase 1 and Phase 2 of the parent (PIN dialog, listen choice, mDNS publish)

---

## Purpose

- **🔷** `⏳` During the pairing window the phone submits a CSR and the 6-digit PIN on the TLS bin socket.
- **🔷** `⏳` A valid PIN signs that CSR with the server CA and returns the signed cert, the CA public certificate, and the listen-choice address list.
- **🔷** `⏳` Android **Add connection** finds that server over mDNS, then asks for the PIN. No typed IP.
- **🔷** `⏳` The phone stores every returned address and, on later starts, connects to one that answers.
- **ℹ️** The PIN dialog, the 60-second window, **All** as `0.0.0.0`, and the `_rpc._tcp.local` publish are Phase 1 and Phase 2 of the parent.

---

## Phase 3 — Registration response

### Goal

- **🔷** `⏳` During the pairing window the phone submits a CSR and the 6-digit PIN on the TLS bin socket.
- **🔷** `⏳` Server checks the PIN against the value from Phase 1.
- **🔷** `⏳` Valid PIN: sign the CSR with the server CA key from disk, return that client certificate and the CA public certificate, and return the listen-choice address list from Phase 2 (one IP, or all).
- **🔷** `⏳` Wrong PIN: refuse that attempt, leave pair mode on, leave the PIN unchanged, and toast **number rejected**. No pending row.
- **🔷** `⏳` Expired window or pair mode off: reject the connection outright. Do not run registration. No pending row.
- **🔷** `⏳` One successful pairing ends the window (Phase 1).

### Notes

- **ℹ️** Landed clients already hold a self-signed device cert and wait for Accept. This phase returns a server-signed cert instead. The phone does not get the CA private key.
- **ℹ️** Already-approved `client_cert` rows stay the steady-state allow list. This plan does not describe wiping them.
- **ℹ️** `⏳` Code proposals after Phase 1’s gate shape is confirmed.

---

## Phase 4 — Android discovery and route selection

### Goal

- **🔷** `⏳` **Add connection** on the phone shows **Listening for connection** and browses for the pairing service. No manual IP entry. The six-digit prompt waits until mDNS finds the server.
- **💩** `⏳` Browse with Android `NsdManager` (`android.net.nsd`) through JNI, same pattern as `ollmapp/android/android-partial-wake-lock.c`. The service type is the one the Linux Avahi publisher registered. `Avahi.ServiceBrowser` does not run on the phone.
- **🔷** `⏳` After discovery, prompt for the six digits.
- **🔷** `⏳` Connect the TLS bin socket, send CSR + PIN, read the signed cert and the address list.
- **🔷** `⏳` Store every returned address with the connection, including the VPN address and the local address.
- **🔷** `⏳` On each app start, probe the stored addresses and connect to one that answers.
  - 2-second timeout per address
  - In the house or the office the local address answers
  - Outside, the local network is absent, so the stored VPN address is the one that answers
- **🔷** `⏳` Later RPC stays on that bin socket so server notifications have a live connection.

### Notes

- **ℹ️** `FileConnectionAdd` today asks for a URL and calls `request_registration` over HTTPS. This phase is the socket pairing path on Android (`FilesdClient.State.SOCKET`).
- **ℹ️** `OLLMchat.Settings.FilesdClient` stores one `url` today. This phase stores the full address list beside that connection.
- **ℹ️** [`RPC-8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md) sent the phone to HTTPS when it left the LAN. This plan does not add that downgrade. Notifications need the socket.
- **ℹ️** `⏳` Code proposals after Phase 3 response fields are confirmed.

---

## LLM notes

- **ℹ️** The pasted draft said `register_client`. Tree name is `RPC-ClientCert.request_registration`. Gate the existing method. Do not add a parallel RPC until a rename is explicitly requested.
- **ℹ️** Nginx WAN registration in `docs/filesd-behind-nginx-proxy.md` is the exposure this plan removes. Update that doc in the same change as the listener gate, not as a drive-by.
- **ℹ️** Avahi stays on the Linux server as the mDNS publisher. The Android browser is `NsdManager` via JNI. Do not link `Avahi.ServiceBrowser` into the phone build.
- **ℹ️** Do not add an HTTPS registration or steady-state fallback. [`RPC-8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md) still describes HTTPS outside the LAN. The parent wins for pairing and for notifications.
