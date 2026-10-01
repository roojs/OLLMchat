# RPC-1.11 — URGENT — VPN/local timed PIN pairing

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Status:** **URGENT** — proposed. Design only. Code fences after the PIN source and Avahi service type are confirmed.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

**Prefix:** `RPC` (`libocrpc` consumers: `ollmfilesd`, `ollmapp`) · see [`RPC-1.0-summary.md`](RPC-1.0-summary.md)

**Parent:** [`RPC-8.2-full-rpc-system.md`](RPC-8.2-full-rpc-system.md) — Phase 7

**Replaces the open registration path in:** [`RPC-8.2.7-client-cert-registration.md`](RPC-8.2.7-client-cert-registration.md)

---

## Purpose

- **🔷** Urgent next step for RPC registration.
- **🔷** Remove every public WAN registration endpoint.
- **🔷** New devices pair only on VPN or LAN, inside a timed window, with a temporary 6-digit PIN.
- **🔷** While the window is open the server advertises itself with mDNS and returns every active server address (VPN, LAN, and any other non-loopback interface).
- **🔷** The GTK client discovers the server, the user types the PIN, and the client picks the fastest working route. The other addresses stay as runtime fallbacks.
- **🔷** Steady-state traffic is mTLS RPC on that private network.
- **⏳** `🔷` Phases 1–4 below. No code in this file yet.
- **ℹ️** Landed registration is always-on `RPC-ClientCert.request_registration` plus desktop Accept / Reject / Ban. This plan is the replacement for that open path.
- **ℹ️** Prior write-up [`RPC-8.2.7`](RPC-8.2.7-client-cert-registration.md) and parent Phase 7 described admin approval with no PIN and no CSR. This plan is the newer requirement.

---

## Current behaviour

- **ℹ️** Unknown client certs may call `RPC-ClientCert.request_registration` whenever HTTPS is listening. See `ollmfilesd/ClientCert.vala`, `ollmfilesd/Https.vala`, `ollmfilesd/SslConnection.vala`.
- **ℹ️** Desktop shows the newest pending row on `ollmapp/SettingsDialog/RegistrationBanner.vala` (Accept / Reject / Ban).
- **ℹ️** The client mints its own cert and posts `request_registration` from `ollmapp/SettingsDialog/FileConnectionAdd.vala`. The user types a server URL.
- **ℹ️** Approved rows live in SQLite `client_cert` (fingerprint, status, ip, requester).
- **ℹ️** [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md) documents an internet-facing nginx stream in front of that listener.
- **ℹ️** No Avahi / mDNS usage anywhere in the tree.

---

## Proposed behaviour

- **🔷** Server pair mode starts only when the GTK user turns on **Allow New Device**.
- **🔷** Pair mode lasts **180 seconds**, then turns itself off.
- **🔷** Turning pair mode on generates a 6-digit PIN and starts the mDNS broadcast.
- **🔷** Pair mode also turns off as soon as one device finishes pairing.
- **🔷** With pair mode off, `register_client` is refused.
- **🔷** A registration attempt with a wrong or missing PIN is dropped immediately.
- **🔷** The client finds the server with Avahi. No typed server address.
- **🔷** The client connects with TLS and sends a CSR plus the PIN.
- **🔷** On a valid PIN the server registers the client cert and returns:
  - the signed client certificate
  - every active server IP (examples: VPN `10.8.0.1`, LAN `192.168.1.5`) with the listen port
- **🔷** The client probes those endpoints, keeps the fastest, and stores the rest as fallbacks.
- **🔷** Later RPC uses the chosen route. Fallback addresses are for when that route dies.

### Workflow

1. GTK server: pair mode off.
2. User clicks **Allow New Device**. Pair mode on for 180s. PIN shown (example shape `849204`). mDNS broadcast starts.
3. GTK client discovers the server on the VPN or LAN.
4. Client asks the user for the 6-digit PIN.
5. Client opens TLS and submits CSR + PIN.
6. Server checks the PIN, signs the client cert, and returns that cert plus the interface address list.
7. Client probes the addresses and binds the fastest. Pair mode turns off.
8. Steady-state mTLS RPC stays on the VPN/LAN addresses.

### Threat and operations

- **🔷** Registration is reachable only on private subnets and VPN. No WAN registration listener.
- **🔷** Requests that lack the current temporary PIN are dropped.
- **🔷** The registration window is three minutes, and only after the server operator opens it in GTK.
- **🔷** Discovery and route choice are automatic. The user supplies the PIN, not an IP.

---

## Suggested order

1. Phase 1 — Timed pair mode on the GTK server
2. Phase 2 — Interface list + mDNS advertise
3. Phase 3 — PIN check, CSR, signed cert, address list in the registration response
4. Phase 4 — GTK client discovery, PIN prompt, route probe, fallbacks

---

## Phase 1 — Timed GTK pairing controller (server)

### Goal

- **🔷** `⏳` A GTK control labeled **Allow New Device** toggles pair mode.
- **🔷** `⏳` Pair mode on:
  - show a 6-digit PIN
  - start a 180-second `GLib.Timeout`
  - start the mDNS broadcast (Phase 2)
- **🔷** `⏳` Pair mode off when the timeout fires, or when one device completes pairing.
- **🔷** `⏳` Pair mode off stops the mDNS broadcast and refuses further registration RPC.
- **🔷** The user named this RPC `register_client`.
- **ℹ️** The live method is `RPC-ClientCert.request_registration`. Gate that method. A second method name needs a separate decision (see **LLM notes**).
- **🔷** `⏳` The PIN must be cryptographically secure. The user named `GLib.Random` as the generator.
- **ℹ️** `GLib.Random` is a PRNG. It does not meet “cryptographically secure”. See **LLM notes**.

### Notes

- **ℹ️** Today’s approval UI is `RegistrationBanner` (Accept / Reject / Ban on a pending row). This phase replaces that open-ended approval with the timed toggle and PIN.
- **💩** `⏳` Where the toggle sits (connections page vs main window) is not specified. Confirm before building the widget.
- **⏳** Code proposals after the PIN source is confirmed.

---

## Phase 2 — Multi-interface discovery (server)

### Goal

- **🔷** `⏳` Component the user named `NetworkUtils`.
- **🔷** `⏳` Enumerate non-loopback interfaces with `Posix.getifaddrs`.
  - VPN adapters (examples `wg0`, `tun0`)
  - local adapters (examples `eth0`, `wlan0`)
- **🔷** `⏳` Publish the pairing service over mDNS while pair mode is on.
- **🔷** Service type the user wrote: `_myapp_pair._tcp`.
- **🔷** `⏳` The registration response carries every reachable IP and port from that enumeration.
- **ℹ️** Avahi is not a dependency in this repo yet. This phase adds it.
- **💩** `⏳` `_myapp_pair._tcp` reads as a placeholder. Confirm a product type (for example `_ollmfilesd-pair._tcp`) before implement.

### Notes

- **ℹ️** Listen port is the existing files daemon HTTPS port. This phase does not invent a second listener.
- **⏳** Code proposals after the service type string is confirmed.

---

## Phase 3 — Registration response

### Goal

- **🔷** `⏳` During the pairing window the client submits a CSR and the 6-digit PIN over TLS.
- **🔷** `⏳` Server checks the PIN against the value from Phase 1.
- **🔷** `⏳` Valid PIN: register the client cert, return the signed client certificate, return the address list from Phase 2.
- **🔷** `⏳` Invalid PIN, expired window, or pair mode off: drop the request. No pending row for the operator to accept later.
- **🔷** `⏳` One successful pairing ends the window (Phase 1).

### Notes

- **ℹ️** Landed clients already hold a self-signed device cert and wait for Accept. This phase returns a server-signed cert instead.
- **ℹ️** Already-approved `client_cert` rows stay the steady-state allow list. This plan does not describe wiping them.
- **⏳** Code proposals after Phase 1’s gate shape is confirmed.

---

## Phase 4 — GTK client discovery and route selection

### Goal

- **🔷** `⏳` `Avahi.ServiceBrowser` finds pairing servers on the VPN or subnet. No manual IP entry.
- **🔷** `⏳` Prompt the user for the 6-digit PIN.
- **🔷** `⏳` TLS connect, send CSR + PIN, read the signed cert and the address list.
- **🔷** `⏳` Probe every returned endpoint asynchronously.
  - 2-second timeout per route
  - bind the fastest route that answers
  - keep the other addresses as runtime fallbacks
- **🔷** `⏳` Later mTLS RPC uses the chosen route and those fallbacks.

### Notes

- **ℹ️** `FileConnectionAdd` today asks for a URL and calls `request_registration`. This phase replaces that for the GTK client.
- **💩** `⏳` Android has no `Avahi.ServiceBrowser`. Phone discovery is outside this plan until asked.
- **⏳** Code proposals after Phases 1–3 response fields are confirmed.

---

## LLM notes

- **ℹ️** User text says both “cryptographically secure” and “via `GLib.Random`”. `GLib.Random.int_range` is not a CSPRNG. Draw the six digits from the OS CSPRNG. Confirm that swap before writing the generator. Do not ship `GLib.Random` as the PIN source.
- **ℹ️** User RPC name is `register_client`. Tree name is `RPC-ClientCert.request_registration`. Gate the existing method. Do not add a parallel RPC until that rename is explicitly requested.
- **ℹ️** Parent Phase 7 and **8.2.7** still say “no CSR, no pairing codes, admin approval, internet-facing daemon”. This file wins for new pairing work.
- **ℹ️** Nginx WAN registration in `docs/filesd-behind-nginx-proxy.md` is the exposure this plan removes. Update that doc in the same change as the listener gate, not as a drive-by.
- **💩** One completed pairing closes the window. A second device needs the operator to open **Allow New Device** again. Do not extend the window to multiple clients unless asked.
