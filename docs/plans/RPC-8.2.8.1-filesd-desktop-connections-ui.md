# 8.2.8.1 — Desktop Connections: File Server + pending banner

**Status:** **PROPOSED** — design decisions locked below; code proposals not yet written

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Depends on:** Phase 1 of parent (**✔️** agent-done) — `RPC-ClientCert.pending_cert` / `client_cert` / int status / IP drop

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Connections tab: **File Server** expander — **always shown** on desktop (empty `https` = server off).
  - Same expandable-block pattern as an LLM `Connection` row.
  - Edit listen values: host/port (→ `filesd.https`), **proxy**, related `filesd` fields (`systemd`, etc.).
  - Saving updates `Config2.filesd` and persists; daemon pick-up = restart / existing install path (do not invent a live-rebind API unless needed).
- **🔷** Enabling HTTPS must **not** require the operator to hand-copy TLS material.
  - Today CA PEM is extracted from GResource; CA **key** still errors with “copy `libocrpc/data/…`”.
  - Extract / install the CA key the same way on first enable; update [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md) so it no longer tells operators to copy certs by hand.
- **🔷** Preferences-dialog **banner** (same area as `PullManagerBanner` on `SettingsDialog.MainDialog` / `action_bar_area`) for the **latest** pending registration only.
  - Shows enough to decide (IP + short fingerprint + time; machine type when present).
  - Buttons: **Accept** / **Reject** / **Ban**.
  - After any action: reload **newest remaining** pending into the same banner; hide when none left.
- **🔷** Approved clients are **the same kind of expandable block** as File Server / Connection.
  - Expand → read-only detail (fingerprint, accepted time, machine type, …).
  - Collapse / **Remove** (delete) only — no edit of cert fields.
- **🔷** Row titles for approved clients: **Client 1**, **Client 2**, … for v1 (few clients expected).
  - Prefer a better title when machine type is known (e.g. Android / Linux / Windows).
  - Expand `request_registration` (and `client_cert` row) with a basic **machine type** field so clients can send it.
- **🔷** Reject → delete that pending row → banner shows next latest (or hides).
- **🔷** Ban → that **IP** blocked; banner shows next latest (or hides).
- **🔷** Remove approved → `client_cert("remove", id)` → bool.
- **🔷** Pending banner live-update via **daemon broadcast** (not a poll loop).
  - Refresh once when the preferences dialog opens is fine as a bootstrap.
  - Emit **only** when a **new registration request** arrives (`request_registration` inserts a pending row).
  - Method: **`event.client_cert`** — short subject event; the notification payload carries that it is a **request** (e.g. action / property), not a long method name.
  - Accept / Reject / Ban / Remove already happen in the UI that issued the RPC — no broadcast needed for those.

---

## Current behaviour

- **ℹ️** Desktop Connections tab = LLM API `Settings.Connection` rows only (`ConnectionAdd` / `ConnectionRow`).
- **ℹ️** Banner pattern: `PullManagerBanner` prepended on `MainDialog.action_bar_area`.
- **ℹ️** Admin RPC (local Unix): `RPC-ClientCert.pending_cert` → one `ClientCert`; `RPC-ClientCert.client_cert` (`sx`) → bool.
- **ℹ️** No list-approved wire yet — Connections rows need one (or an equivalent) to load `status = 1`.
- **ℹ️** `Https.listen` extracts CA PEM from GResource; CA key still requires a manual file copy (and the nginx doc says so).
- **ℹ️** `OllmfilesdApplication.broadcast` already fans out `OLLMrpc.Notification` on the local listen path.

---

## Goal detail

### File Server expander

- **🔷** `⏳` Always present on desktop Connections.
- **🔷** `⏳` Edits `Config2.filesd` (https / proxy / systemd / related) and persists.

### TLS material on enable (no hand-copy)

- **🔷** `⏳` On HTTPS enable / first listen: install CA key from shipped resources the same way as CA PEM (no operator copy step).
- **🔷** `⏳` Rewrite the “Place the product CA private key once…” section in [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md) to match automatic install.

### Pending banner

- **🔷** `⏳` One newest `status = 0` via `pending_cert`; Accept / Reject / Ban → `client_cert`.
- **🔷** `⏳` Bootstrap: refresh when preferences opens.
- **🔷** `⏳` Live: subscribe to daemon broadcast on **new pending request** only; then reload newest pending into the banner.

### Approved client expanders

- **🔷** `⏳` Same expandable-block UX as File Server / Connection (not a table, not a special widget class for “banned”).
- **🔷** `⏳` Expand = read-only detail; Remove = `client_cert("remove", id)` → bool.
- **🔷** `⏳` Titles: **Client N** for v1; upgrade label when machine type is present.
- **🔷** `⏳` Wire to list approved rows (`status = 1`) for the Connections tab (thin list wire on `ClientCert`, or equivalent — needed for the expanders).

### Registration machine type

- **🔷** `⏳` Add a basic **machine type** on the `client_cert` row + `request_registration` payload (e.g. `android` / `linux` / `windows` / empty).
- **🔷** `⏳` Banner + approved expander can show it; Android plan sends it ([`8.2.8.2`](RPC-8.2.8.2-filesd-android-file-connection.md)).

### Broadcast

- **🔷** `⏳` On new pending insert in `request_registration`, broadcast `OLLMrpc.Notification` with method **`event.client_cert`** (via `OllmfilesdApplication.broadcast`).
  - Payload property indicates **request** (registration requested) — do not encode that in a long method name.
- **🔷** `⏳` Desktop banner listens for `event.client_cert` and refreshes newest pending.
- **🚫** Broadcast on Accept / Reject / Ban / Remove / approved-list changes — caller already knows.
- **🚫** Polling while the dialog is open as the primary design (bootstrap-on-open is OK).
- **🚫** Long method names like `event.client_cert.request_registration` — keep method short; put the kind on the notification data.

---

## Open questions (need 🔷)

1. Machine-type vocabulary — fixed short strings (`android` / `linux` / `windows` / `other`), or free text?

---

## Notes

- **ℹ️** Pattern: `PullManagerBanner` on `MainDialog.action_bar_area` — registration banner lives there, not a Connections-tab pending list.
- **🔷** **No** pending-registration list, table, or multi-row pending UI — banner only, one at a time.
- **🔷** Registered client rows are **not** `Settings.Connection` (LLM API). Parallel expandable blocks on the same tab.
- **⏳** Code proposals — after open questions on machine type / event name if needed; otherwise ready to draft fences.

---

## LLM notes

- **ℹ️** Parent Phase 1 owns int status / HTTPS accept drop — extend registration for machine type here; do not re-open ban-drop design.
- **🚫** Unban UI.
- **🚫** Pending list UI (of any kind).
- **🚫** Mixing banned-IP rows into the registered-connection list as editable connections.
- **🚫** Showing banned IPs as “banned certificates”.
- **🚫** Putting file-server listen settings into `Settings.Connection` LLM map.
- **🚫** Operator hand-copy of CA key as the supported enable path.
- **🚫** Poll loop as the live-update mechanism.
- **💩** Live HTTPS rebind without daemon restart when `filesd.https` changes from the UI.
