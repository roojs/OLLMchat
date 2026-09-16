# 8.2.8 — File-server Connections UI + registration approval

**Status:** **IN PROGRESS** — Phase 1 **✔️** agent-done · Phase 2–3 in sub-plans

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2.7-client-cert-registration.md`](RPC-8.2.7-client-cert-registration.md) — replaces Phase 2 CLI admin with GUI; adds Android client connection

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Wire **file-server** into the **Connections** settings tab on **desktop** and **Android**.
- **🔷** Desktop hosts `ollmfilesd` HTTPS: expander edits listen settings (`filesd` port / proxy / etc.).
- **🔷** Desktop preferences dialog shows a **banner** for the **single latest** pending registration (same slot as model-download / `PullManagerBanner` on `MainDialog`) — **Accept** / **Reject** / **Ban**.
- **🔷** Only **one** pending is shown at a time; clearing it (any of the three actions) reveals the **next latest** if any remain — **no pending list UI**.
- **🔷** Reject deletes the pending row.
- **🔷** Ban blocks that **IP** from further registration attempts (flood control) — **not** a permanent cert ban; **no unban** UI.
- **🔷** Banned IPs also live in an **in-memory list** on the HTTPS server: load from DB on listen; update on `"ban"`. Drop the TCP connection as soon as the client IP is known (PROXY header path or direct peer) — do not hand the stream to Soup / TLS for banned IPs.
- **🔷** After Accept, the client appears in the Connections list like a remote connection — **expand + remove only**.
- **🔷** Android: **Add file connection** (HTTPS URL of the file server) on the Connections tab.
- **🔷** A working Android file connection **unlocks** agents that need the file daemon / project tools.
- **ℹ️** Phase 0–1 of **8.2.7** are largely in tree (`Filesd`, `Https`, `ClientCert`, `request_registration`).
- **ℹ️** This plan **supersedes** **8.2.7 Phase 2** CLI (`list` / `accept` / `reset`) with the Connections UI.

---

## Sub-plans

| Phase | Plan | Status |
| --- | --- | --- |
| **1** | Daemon: `ClientCert` RPC + int status + IP drop (this file) | **✔️** agent-done |
| **2** | [`RPC-8.2.8.1-filesd-desktop-connections-ui.md`](RPC-8.2.8.1-filesd-desktop-connections-ui.md) — Desktop File Server expander + pending banner + registered rows | **⏳** |
| **3** | [`RPC-8.2.8.2-filesd-android-file-connection.md`](RPC-8.2.8.2-filesd-android-file-connection.md) — Android Add file connection + client cert + unlock agents | **⏳** |

---

## Suggested order

1. **✔️** Phase 1 — `ClientCert` RPC + int `status` + accept drop (this file)
2. **⏳** Phase 2 — [`8.2.8.1`](RPC-8.2.8.1-filesd-desktop-connections-ui.md)
3. **⏳** Phase 3 — [`8.2.8.2`](RPC-8.2.8.2-filesd-android-file-connection.md)

---

## Current behaviour

- **ℹ️** `Config2.filesd` — `https`, `proxy`, `systemd` (and reserved `unix` / `socket`).
- **ℹ️** `ollmfilesd` starts `OLLMfilesd.Https` when `filesd.https` is non-empty.
- **✔️** `client_cert.status` is int `0` / `1` / `-1`; cert RPC on `RPC-ClientCert` (`request_registration`, `pending_cert`, `client_cert`).
- **✔️** Banned IPs: DB `status = -1` + `HttpServer.banned_ips`; drop on accept with `GLib.debug`.
- **ℹ️** Desktop Connections tab = LLM API `Settings.Connection` rows only — Phase 2.
- **ℹ️** Android Connections tab reuses the same page; no file-server connection yet — Phase 3.
- **ℹ️** Android `OLLMfiles.ProjectManager` is a stub; desktop boots local Unix `ollmfilesd` and registers Code Assistant / related agents.
- **ℹ️** `OLLMrpc.Client` HTTP path exists; `Transport.HttpClient.tls_certificate` is ready — Android client-cert mint/load not wired — Phase 3.

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
- **💩** `⏳` List approved (`status = 1`) for Connections rows — Phase 2 ([`8.2.8.1`](RPC-8.2.8.1-filesd-desktop-connections-ui.md)).

---

## Phase 2 — Desktop Connections UI

**➡️** [`RPC-8.2.8.1-filesd-desktop-connections-ui.md`](RPC-8.2.8.1-filesd-desktop-connections-ui.md)

---

## Phase 3 — Android file connection + unlock agents

**➡️** [`RPC-8.2.8.2-filesd-android-file-connection.md`](RPC-8.2.8.2-filesd-android-file-connection.md)

---

## Open questions (need 🔷)

Tracked on the sub-plans:

1. Desktop File Server expander always shown? → [`8.2.8.1`](RPC-8.2.8.1-filesd-desktop-connections-ui.md)
2. Android one file-server URL or multiple? → [`8.2.8.2`](RPC-8.2.8.2-filesd-android-file-connection.md)
3. Which agents unlock on Android? → [`8.2.8.2`](RPC-8.2.8.2-filesd-android-file-connection.md)
4. Remove approved = `client_cert("remove", id)` → bool? → [`8.2.8.1`](RPC-8.2.8.1-filesd-desktop-connections-ui.md)

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
- **🚫** Putting file-server listen settings into `Settings.Connection` LLM map.
- **💩** Live HTTPS rebind without daemon restart when `filesd.https` changes from the UI.
- **🚫** Row-level string→int migrate — unused; drop+recreate table instead.
- **🚫** `ALTER TABLE …` to change column type — SQLite still does not support that.
- **💩** Int action codes instead of string actions — strings kept for readability unless you prefer ints.
