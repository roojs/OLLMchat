# 8.2.8 — File-server Connections UI + registration approval

**Status:** **PROPOSED** — design from chat; code proposals after review

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
- **🔷** Ban sets `status = -1` (blocks that **IP** from registering again); **no unban** UI.
- **🔷** After Accept, the client appears in the Connections list like a remote connection — **expand + remove only**.
- **🔷** Android: **Add file connection** (HTTPS URL of the file server) on the Connections tab.
- **🔷** A working Android file connection **unlocks** agents that need the file daemon / project tools.
- **ℹ️** Phase 0–1 of **8.2.7** are largely in tree (`Filesd`, `Https`, `ClientCert`, `request_registration`).
- **ℹ️** This plan **supersedes** **8.2.7 Phase 2** CLI (`list` / `accept` / `reset`) with the Connections UI.

---

## Suggested order

1. Phase 1 — Daemon RPC + int `status` (admin ops over local Unix socket)
2. Phase 2 — Desktop Connections: File Server expander + pending banner + registered rows
3. Phase 3 — Android: Add file connection + client cert + unlock agents
4. Phase 4 — Code proposals (after design sign-off)

---

## Current behaviour

- **ℹ️** `Config2.filesd` — `https`, `proxy`, `systemd` (and reserved `unix` / `socket`).
- **ℹ️** `ollmfilesd` starts `OLLMfilesd.Https` when `filesd.https` is non-empty.
- **ℹ️** Unknown client certs may only call `RPC-Daemon.request_registration`; rows in `client_cert` (today string `pending` / `registered` — this plan migrates to int status).
- **ℹ️** Desktop Connections tab = LLM API `Settings.Connection` rows only (`ConnectionAdd` / `ConnectionRow`).
- **ℹ️** Android Connections tab reuses the same page; no file-server connection yet.
- **ℹ️** Android `OLLMfiles.ProjectManager` is a stub; desktop boots local Unix `ollmfilesd` and registers Code Assistant / related agents.
- **ℹ️** `OLLMrpc.Client` HTTP path exists; `Transport.HttpClient.tls_certificate` is ready — Android client-cert mint/load not wired.

---

## Phase 1 — Daemon admin RPC + int status

### Goal

- **🔷** `⏳` `client_cert.status` is an **int**:
  - `0` — pending
  - `1` — approved
  - `-1` — banned
- **🔷** `⏳` Migrate existing string `pending` / `registered` schema + call sites (`ClientCert`, `Daemon.request_registration`, `Https.allow_rpc`) to these ints.
- **🔷** `⏳` Admin ops available to the desktop app over the **existing local Unix** RPC (not HTTPS admin):
  - newest pending (`status = 0`, highest `created` — banner source; not a list for the UI)
  - accept (`0` → `1`; clear IP per **8.2.7**)
  - reject (delete pending row)
  - ban (`status = -1`; keep IP; no unban)
  - list approved (`status = 1` — Connections rows after accept)
  - remove approved (expand-row Remove)
- **🔷** `⏳` Ban: set `status = -1` on that row (IP kept so further `request_registration` from that IP is rejected).
- **🔷** `⏳` **No unban** UI or RPC.
- **🚫** CLI `list` / `accept` / `reset` from **8.2.7 Phase 2** — superseded by this UI path.
- **🚫** Unban.
- **🚫** Separate `banned` boolean column — status alone carries ban.

### Notes

- **💩** Wire names (confirm): e.g. `RPC-Daemon.newest_pending_cert`, `accept_cert`, `reject_cert`, `ban_cert_ip`, `list_registered_certs`, `remove_registered_cert` — or one small admin surface on `Daemon`.
- **🔷** Ban keeps a row with `status = -1` and IP set (fingerprint may remain or clear — reject deletes; ban does not).
- **🔷** `request_registration` must reject when any row has that client IP with `status = -1` (check before insert).
- **ℹ️** Desktop always talks to local `ollmfilesd` via Unix socket for these admin calls (same as today’s `ProjectManager.rpc`).
- **⏳** Code proposals — Phase 4.

---

## Phase 2 — Desktop Connections UI

### Goal

- **🔷** `⏳` Connections tab: **File Server** expander (connection-like row).
  - Edit listen values: host/port (→ `filesd.https`), **proxy**, and related `filesd` fields already on config (`systemd`, etc.).
  - Saving updates `Config2.filesd` and persists; daemon pick-up = restart / existing install path (do not invent a live-rebind API unless needed).
- **🔷** `⏳` Preferences-dialog **banner** (same area as `PullManagerBanner` on `SettingsDialog.MainDialog` / `action_bar_area`) for the **latest** pending registration only.
  - Shows enough to decide (IP + short fingerprint + time).
  - Buttons: **Accept** / **Reject** / **Ban**.
  - After any action: reload **newest remaining** pending into the same banner; hide when none left.
- **🔷** `⏳` After Accept: that client appears in the Connections list like a remote connection.
  - **Expand** (read-only detail: fingerprint, accepted time, …).
  - **Remove** only (no edit of cert fields).
- **🔷** `⏳` Reject → delete that pending row → banner shows next latest (or hides).
- **🔷** `⏳` Ban → IP blocked; that pending cleared → banner shows next latest (or hides).

### Notes

- **ℹ️** Pattern: `PullManagerBanner` prepended on `MainDialog.action_bar_area` — registration banner lives there, not a Connections-tab list.
- **🔷** **No** pending-registration list, table, or multi-row UI — banner only, one at a time.
- **💩** File Server expander is **always** present on desktop Connections (not behind “Add”), vs only after “Add file server” — lean **always present**; empty `https` = server off.
- **💩** Registered client rows are **not** `Settings.Connection` (LLM API). Parallel UI rows backed by `client_cert` via RPC — same tab, different row type.
- **💩** Refresh newest-pending when the preferences dialog opens / gains focus; optional short poll while open.
- **🚫** Unban UI.
- **🚫** Pending list UI (of any kind).
- **🚫** Mixing banned IPs into the registered-connection list as editable connections.
- **⏳** Code proposals — Phase 4.

---

## Phase 3 — Android file connection + unlock agents

### Goal

- **🔷** `⏳` Connections tab: **Add file connection** — HTTPS URL of the remote file server (`https://host:port` or public nginx front).
- **🔷** `⏳` On connect: mint/load **device client cert**, present it, call `request_registration` if not registered, then use normal file RPC when approved.
- **🔷** `⏳` A verified file connection **unlocks** agents that need file/project tools (today Android only registers Chatter; desktop registers Code Assistant etc. after `ProjectManager` connects).

### Notes

- **ℹ️** Product CA trust on Android already has TLS helpers (`AndroidConnectionTls` / config TLS) for LLM HTTPS — file-server CA trust must use the **product CA** PEM, not the device trust store alone.
- **💩** Config shape: dedicated `Config2` field (e.g. file-server URL / `FilesdClient`) **or** a typed row beside LLM connections — **not** reusing `Settings.Connection` URL-as-Ollama without a type discriminant. Prefer a small nested settings object + one URL.
- **💩** One file connection on Android for v1 (not a list).
- **💩** “Unlock agents” = when HTTPS `ProjectManager` / `OLLMrpc.Client` is connected and registered, register the same agent factories / tools Android can support (subset of desktop). Exact agent list = confirm (Code Assistant? Agent Pi? Chatter stays always).
- **ℹ️** `libocfiles.ProjectManager` today hard-wires Unix sock under `~/.local/share/ollmchat` — Android needs construct-time HTTPS socket path + client cert on the HTTP transport.
- **💩** While pending approval: show status on the file-connection row (“waiting for desktop accept”); do not unlock agents until `status = 1` / successful non-registration RPC.
- **⏳** Code proposals — Phase 4.

---

## Phase 4 — Code proposals

- **⏳** After design sign-off: **Remove** / **Replace with** / **Add** fences per file (daemon, `ClientCert`, Connections pages, Android bootstrap).
- **⏳** No helpers unless named here or in chat.

---

## Open questions (need 🔷)

1. Desktop File Server expander: **always shown**, or only after an “Add file server” action?
2. Android: **one** file-server URL, or multiple?
3. Which agents unlock on Android once the file connection works?
4. After Accept, remove approved client = delete the `status = 1` row, correct? (earlier **8.2.7** vetoed per-cert revoke in favour of reset-all — this plan **reintroduces remove-one** for the Connections row.)

---

## LLM notes

- **ℹ️** Extends **8.2.7**; does not replace Phase 0/1 transport/gate.
- **ℹ️** Operator nginx doc stays [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md).
- **🚫** Unban.
- **🚫** Pending registration **list** — banner shows latest only; clear → next latest.
- **🚫** CLI admin as the primary surface (GUI owns approval).
- **🚫** Putting file-server listen settings into `Settings.Connection` LLM map.
- **💩** Live HTTPS rebind without daemon restart when `filesd.https` changes from the UI.
