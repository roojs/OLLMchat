# 8.2.8 — File-server Connections UI + registration approval

**Status:** **IN PROGRESS** — Phase 1–3 **✔️** · Phase 4 **✅** · Phase 5 **✔️** · Phase 6 **✅** · Phase 7 **✔️** · Phase 8 in sub-plan · Phase 9 **✔️** · Phase 10 **⏳**

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2.7-client-cert-registration.md`](RPC-8.2.7-client-cert-registration.md) — replaces Phase 2 CLI admin with GUI; adds Android client connection

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Wire **file-server** into the **Connections** settings tab on **desktop** and **Android**.
- **🔷** Desktop **Linux** hosts `ollmfilesd` HTTPS: expander picks a listen IP from this machine, plus port / proxy / systemd.
- **🔷** Desktop preferences dialog shows a **banner** for the **single latest** pending registration (same slot as model-download / `PullManagerBanner` on `MainDialog`) — **Accept** / **Reject** / **Ban**.
- **🔷** Only **one** pending is shown at a time; clearing it (any of the three actions) reveals the **next latest** if any remain — **no pending list UI**.
- **🔷** Reject deletes the pending row.
- **🔷** Ban blocks that **IP** from further registration attempts (flood control) — **not** a permanent cert ban; **no unban** UI.
- **🔷** Banned IPs also live in an **in-memory list** on the HTTPS server: load from DB on listen; update on `"ban"`. Drop the TCP connection as soon as the client IP is known (PROXY header path or direct peer) — do not hand the stream to Soup / TLS for banned IPs.
- **🔷** After Accept, the client appears in the Connections list like a remote connection — **expand + remove only**.
- **🔷** **Client** (Android + Linux): **Add file connection** on the Connections tab — name + HTTPS URL, **Request** registration, single row with Check / Enable / Remove.
- **🔷** An approved + enabled file connection **unlocks Agent Pi** (`agent-pi`); local Unix `ollmfilesd` on Linux is overridden only when enabled.
- **ℹ️** Phase 0–1 of **8.2.7** are largely in tree (`Filesd`, `Https`, `ClientCert`, `request_registration`).
- **ℹ️** This plan **supersedes** **8.2.7 Phase 2** CLI (`list` / `accept` / `reset`) with the Connections UI.

---

## Sub-plans

| Phase | Plan | Status |
| --- | --- | --- |
| **1** | Daemon: `ClientCert` RPC + int status + IP drop (this file) | **✔️** agent-done |
| **2** | [`RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md`](done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md) — Desktop pending banner + registered client rows | **✔️** agent-done |
| **3** | [`RPC-8.2.8.2-DONE-filesd-android-file-connection.md`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md) — Client file connection UI + registration request; Android + Linux | **✔️** agent-done |
| **4** | [`RPC-8.2.8.3-DONE-filesd-file-server-tls.md`](done/RPC-8.2.8.3-DONE-filesd-file-server-tls.md) — Desktop File Server expander + TLS CA key auto-install | **✅** |
| **5** | [`RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md`](done/RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md) — `OLLMrpc.Client.http`, `disconnect()` fix, `ProjectManager.replace_rpc` + `notification` (library half of 8.2.8.2 Phase 2) | **✔️** agent-done |
| **6** | [`RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) — Linux takeover, Check probe, live `enabled` toggle (UI half of 8.2.8.2 Phase 2) | **✅** |
| **7** | [`RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md`](done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) — Android `ProjectManager`, HTTPS takeover, full liboccoder compile. Precursor [`FILES-2.10.4.33`](FILES-2.10.4.33-client-tree-sitter-daemon.md) **✔️** | **✔️** |
| **8** | [`RPC-8.2.8.7-filesd-tcp-socket-lan.md`](RPC-8.2.8.7-filesd-tcp-socket-lan.md) — Linux `filesd.socket` LAN TCP + TLS registration | **⏳** |
| **9** | [`RPC-8.2.8.8-android-phone-tablet-pane.md`](RPC-8.2.8.8-android-phone-tablet-pane.md) — Android `ChatDesktopInterface`, phone stack / tablet landscape columns | **✔️** |
| **10** | (this file) Android register `AgentPi.Factory` when the remote file connection is live | **⏳** |

---

## Suggested order

1. **✔️** Phase 1 — `ClientCert` RPC + int `status` + accept drop (this file)
2. **✔️** Phase 2 — [`8.2.8.1`](done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md) (agent-done; awaiting user ✅)
3. **✔️** Phase 3 — [`8.2.8.2`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md) (agent-done; awaiting user ✅)
4. **✅** Phase 4 — [`8.2.8.3`](done/RPC-8.2.8.3-DONE-filesd-file-server-tls.md)
5. **✔️** Phase 5 — [`8.2.8.4`](done/RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md) (agent-done; awaiting user ✅)
6. **✅** Phase 6 — [`8.2.8.5`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md)
7. **✔️** Phase 7 — [`8.2.8.6`](done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) (Android takeover; [`FILES-2.10.4.33`](FILES-2.10.4.33-client-tree-sitter-daemon.md) **✔️**)
8. **⏳** Phase 8 — [`8.2.8.7`](RPC-8.2.8.7-filesd-tcp-socket-lan.md) — Linux LAN TCP socket (Windows loopback port is [`docs/bugs/2026-09-20-filesd-windows-socket-port.md`](../bugs/2026-09-20-filesd-windows-socket-port.md))
9. **✔️** Phase 9 — [`8.2.8.8`](RPC-8.2.8.8-android-phone-tablet-pane.md) — Android phone/tablet `ChatDesktopInterface`
10. **⏳** Phase 10 — Android `AgentPi.Factory` register when the remote file connection is live (this file; no sub-plan yet)

---

## Current behaviour

- **ℹ️** `Config2.filesd` — `https`, `proxy`, `systemd` (and reserved `unix` / `socket`).
- **ℹ️** `ollmfilesd` starts `OLLMfilesd.Https` when `filesd.https` is non-empty.
- **✔️** `client_cert.status` is int `0` / `1` / `-1`; cert RPC on `RPC-ClientCert` (`request_registration`, `pending_cert`, `client_cert`).
- **✔️** Banned IPs: DB `status = -1` + `HttpServer.banned_ips`; drop on accept with `GLib.debug`.
- **ℹ️** Desktop Connections tab = LLM API `Settings.Connection` rows only — Phase 2.
- **ℹ️** Connections tab has no outbound file-server row yet — Phase 3.
- **ℹ️** Android `OLLMfiles.ProjectManager` is a stub; desktop boots local Unix `ollmfilesd` and registers Code Assistant / Agent Pi / related agents.
- **ℹ️** `OLLMrpc.Client` HTTP path exists; `Transport.HttpClient.tls_certificate` is ready — outbound client-cert mint/load not wired — Phase 3.

---

## Phase 1 — `ClientCert` RPC + int status + IP drop

### Goal

- **🔷** `✔️` `client_cert.status` is an **int**:
  - `0` — pending
  - `1` — approved
  - `-1` — IP banned (flood control; row is an IP block, not a banned cert)
- **🔷** `✔️` Leftover TEXT `status` table → detect + DROP + recreate INTEGER (no row copy).
- **🔷** `✔️` All cert RPC on **`ClientCert`** (`RPC-ClientCert`) — not fat `Daemon`.
  - **`request_registration`**
  - **`pending_cert`** — newest `status = 0`; one object (`id = 0` if none)
  - **`client_cert`** (`sx`) — `"accept"` / `"reject"` / `"ban"` / `"remove"` → **bool**
- **🔷** `✔️` Ban = IP flood control (`status = -1`, `fingerprint = "ip:" + ip`); append to `HttpServer.banned_ips`.
- **🔷** `✔️` In-memory ban list loaded on HTTPS start; early drop before Soup/TLS (PROXY `src_ip` or TCP peer) with `GLib.debug("dropping banned client IP %s", …)`.
- **🔷** `✔️` **No unban** UI or RPC.
- **🚫** CLI `list` / `accept` / `reset` from **8.2.7 Phase 2** — superseded by UI path.
- **🚫** Unban / ban-as-cert-revoke / separate `banned` column / admin over HTTPS / list retval for mutate.

### Landed (tree)

- `ollmfilesd/ClientCert.vala` — row + `for_rpc` + three wires
- `ollmfilesd/Daemon.vala` — registration / admin cert methods removed
- `ollmfilesd/Application.vala` — `ClientCert.rpc_register` + public `https_listen`
- `ollmfilesd/Https.vala` — gate + load bans; allow only `request_registration` for unknown
- `libocrpc/Transport/HttpServer.vala` — `banned_ips` + SocketService accept drop

### Notes

- **🔷** Wire prefix: `RPC-ClientCert`.
- **🔷** Desktop talks to local `ollmfilesd` via Unix socket for admin calls.
- **ℹ️** nginx unchanged — drop is in `ollmfilesd` after PROXY parse (or direct peer).
- **💩** `⏳` List approved (`status = 1`) for Connections rows — Phase 2 ([`8.2.8.1`](done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md)).

---

## Phase 2 — Desktop Connections UI

**➡️** [`RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md`](done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md)

---

## Phase 3 — Client file connection + Agent Pi unlock

**➡️** [`RPC-8.2.8.2-DONE-filesd-android-file-connection.md`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md) — UI + registration request (Android + Linux)

---

## Phase 4 — Desktop File Server expander + TLS CA key auto-install

**➡️** [`RPC-8.2.8.3-DONE-filesd-file-server-tls.md`](done/RPC-8.2.8.3-DONE-filesd-file-server-tls.md)

---

## Phase 5 — Remote file connection: HTTPS RPC client + `replace_rpc`

**➡️** [`RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md`](done/RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md) — library half of 8.2.8.2 Phase 2

---

## Phase 6 — Remote file connection: desktop takeover, Check, live toggle

**➡️** [`RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) — UI half of 8.2.8.2 Phase 2

---

## Phase 7 — Remote file connection: Android takeover

**➡️** [`RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md`](done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) — Android `ProjectManager`, HTTPS takeover, full liboccoder

---

## Phase 8 — Linux LAN TCP socket (`filesd.socket`)

**➡️** [`RPC-8.2.8.7-filesd-tcp-socket-lan.md`](RPC-8.2.8.7-filesd-tcp-socket-lan.md) — bind bin TCP like HTTPS; TLS + cert registration on the LAN; no WAN / PROXY

ℹ️ Windows loopback port (hardcoded 4141) is [`docs/bugs/2026-09-20-filesd-windows-socket-port.md`](../bugs/2026-09-20-filesd-windows-socket-port.md), not this phase.

---

## Phase 9 — Android phone / tablet `ChatDesktopInterface`

**➡️** [`RPC-8.2.8.8-android-phone-tablet-pane.md`](RPC-8.2.8.8-android-phone-tablet-pane.md) — phone globe stack vs tablet landscape columns

---

## Phase 10 — Android Agent Pi register (`⏳`)

- **🔷** `⏳` Register `OLLMcoder.AgentPi.Factory` on Android when the remote file connection is live (`url` + `enabled` + `approved`, after HTTPS hello).
- **🔷** Linux stays as today (local Unix or remote both keep Agent Pi).
- **ℹ️** Needs Phase 7 (`ProjectManager` live) and Phase 9 (`ChatDesktopInterface` host). No sub-plan yet.

---

## Open questions (need 🔷)

Tracked on the sub-plans:

1. ~~Desktop File Server expander always shown?~~ → **🔷** always — [`8.2.8.3`](done/RPC-8.2.8.3-DONE-filesd-file-server-tls.md)
2. ~~One file-server URL or multiple?~~ → **🔷** one — [`8.2.8.2`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md)
3. ~~Which agents unlock?~~ → **🔷** Agent Pi only — [`8.2.8.2`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md)
4. ~~Remove approved = `client_cert("remove", id)` → bool?~~ → **🔷** yes — [`8.2.8.1`](done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md)
5. Machine-type vocabulary → [`8.2.8.1`](done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md)


---

## LLM notes

- **ℹ️** Extends **8.2.7**; does not replace Phase 0/1 transport/gate.
- **ℹ️** Operator nginx doc stays [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md).
- **ℹ️** Phase 1 admin wire: `RPC-ClientCert.pending_cert` (object) + `RPC-ClientCert.client_cert` (`sx`, bool); registration moved off `Daemon`.
- **ℹ️** Banned IPs: DB `status = -1` + in-memory `HttpServer.banned_ips`; drop on accept with `GLib.debug("dropping banned client IP %s", …)`.
- **🚫** Unban.
- **🚫** Ban-as-certificate-revoke — ban is IP flood control only.
- **🚫** List retval for mutate ops — bool only.
- **🚫** Pending registration **list** — banner shows latest only; clear → next latest.
- **🚫** CLI admin as the primary surface (GUI owns approval).
- **🚫** `client_cert` over HTTPS.
- **🚫** Six separate admin cert methods.
- **🔷** File Server listen changes: stop local `ollmfilesd` from the app (pid + SIGTERM) then `ClientBoot` — [`8.2.8.3`](done/RPC-8.2.8.3-DONE-filesd-file-server-tls.md).
- **🚫** Live HTTPS rebind inside a running daemon.
- **🚫** Putting file-server listen settings into `Settings.Connection` LLM map.
- **🚫** Row-level string→int migrate — unused; drop+recreate table instead.
- **🚫** `ALTER TABLE …` to change column type — SQLite still does not support that.
- **💩** Int action codes instead of string actions — strings kept for readability unless you prefer ints.
