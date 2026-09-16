# 8.2.8.1 — Desktop Connections: File Server + pending banner

**Status:** **PROPOSED** — design locked in parent; code proposals not yet written

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Depends on:** Phase 1 of parent (**✔️** agent-done) — `RPC-ClientCert.pending_cert` / `client_cert` / int status / IP drop

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Connections tab: **File Server** expander (connection-like row).
  - Edit listen values: host/port (→ `filesd.https`), **proxy**, and related `filesd` fields already on config (`systemd`, etc.).
  - Saving updates `Config2.filesd` and persists; daemon pick-up = restart / existing install path (do not invent a live-rebind API unless needed).
- **🔷** Preferences-dialog **banner** (same area as `PullManagerBanner` on `SettingsDialog.MainDialog` / `action_bar_area`) for the **latest** pending registration only.
  - Shows enough to decide (IP + short fingerprint + time).
  - Buttons: **Accept** / **Reject** / **Ban**.
  - After any action: reload **newest remaining** pending into the same banner; hide when none left.
- **🔷** After Accept: that client appears in the Connections list like a remote connection.
  - **Expand** (read-only detail: fingerprint, accepted time, …).
  - **Remove** only (no edit of cert fields).
- **🔷** Reject → delete that pending row → banner shows next latest (or hides).
- **🔷** Ban → that **IP** blocked (pending row becomes IP-ban record); banner shows next latest (or hides).

---

## Current behaviour

- **ℹ️** Desktop Connections tab = LLM API `Settings.Connection` rows only (`ConnectionAdd` / `ConnectionRow`).
- **ℹ️** Banner pattern: `PullManagerBanner` prepended on `MainDialog.action_bar_area`.
- **ℹ️** Admin RPC (local Unix): `RPC-ClientCert.pending_cert` → one `ClientCert`; `RPC-ClientCert.client_cert` (`sx`) → bool (`accept` / `reject` / `ban` / `remove`).
- **ℹ️** No list-approved wire yet — add a thin third wire on `ClientCert` if Connections rows need it.

---

## Goal detail

- **🔷** `⏳` File Server expander edits `Config2.filesd` (https / proxy / systemd / related).
- **🔷** `⏳` Banner shows **one** newest `status = 0` via `pending_cert`; Accept / Reject / Ban call `client_cert`.
- **🔷** `⏳` Approved clients (`status = 1`) as parallel Connections rows (not `Settings.Connection`) — expand + remove only.
- **🔷** `⏳` Remove approved → `client_cert("remove", id)` → bool.
- **💩** `⏳` File Server expander **always** present on desktop Connections (empty `https` = server off) — confirm in open questions.
- **💩** `⏳` Thin list-approved wire on `ClientCert` if needed for rows.
- **💩** `⏳` Refresh newest-pending when preferences opens / gains focus; optional short poll while open.

---

## Open questions (need 🔷)

1. Desktop File Server expander: **always shown**, or only after an “Add file server” action?
2. After Accept, remove approved client = `client_cert("remove", id)` → bool, correct?

---

## Notes

- **ℹ️** Pattern: `PullManagerBanner` on `MainDialog.action_bar_area` — registration banner lives there, not a Connections-tab list.
- **🔷** **No** pending-registration list, table, or multi-row UI — banner only, one at a time.
- **💩** Registered client rows are **not** `Settings.Connection` (LLM API). Parallel UI rows backed by `client_cert` via RPC — same tab, different row type.
- **⏳** Code proposals — after design sign-off on open questions.

---

## LLM notes

- **ℹ️** Parent Phase 1 owns daemon/RPC/ban drop — do not re-open int status or HTTPS accept path here.
- **🚫** Unban UI.
- **🚫** Pending list UI (of any kind).
- **🚫** Mixing banned-IP rows into the registered-connection list as editable connections.
- **🚫** Showing banned IPs as “banned certificates”.
- **🚫** Putting file-server listen settings into `Settings.Connection` LLM map.
- **💩** Live HTTPS rebind without daemon restart when `filesd.https` changes from the UI.
