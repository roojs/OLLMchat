# 8.2.8.3 — Desktop File Server expander + TLS CA key auto-install

**Status:** **PROPOSED** — design moved from [`8.2.8.1`](RPC-8.2.8.1-filesd-desktop-connections-ui.md); code proposals not yet written

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Depends on:**
- Phase 1 of parent (**✔️** agent-done) — `Config2.filesd` + `OLLMfilesd.Https.listen` CA PEM extraction
- [`RPC-8.2.8.1-filesd-desktop-connections-ui.md`](RPC-8.2.8.1-filesd-desktop-connections-ui.md) — Connections tab / `MainDialog.action_bar_area` expander pattern (`ConnectionRow`)

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

---

## Current behaviour

- **ℹ️** `Config2.filesd` — `https`, `proxy`, `systemd` (and reserved `unix` / `socket`); class `libollmchat/Settings/Filesd.vala`, `Json.Serializable`.
- **ℹ️** `ollmfilesd` starts `OLLMfilesd.Https` when `filesd.https` is non-empty (`ollmfilesd/Https.vala` `listen()`).
- **ℹ️** `Https.listen` extracts CA PEM from GResource (`/ollmrpc/ollmrpc-ca.pem`) into `{data_dir}/tls/ollmrpc-ca.pem`; CA **key** hard-errors with `GLib.error("missing CA key %s (copy libocrpc/data/ollmrpc-ca-key.pem)")`.
- **ℹ️** GResource ships the PEM only (`libocrpc/data/ollmrpc.gresource.xml`); the CA key file `libocrpc/data/ollmrpc-ca-key.pem` is repo-only, not bundled.
- **ℹ️** Desktop Connections tab = LLM API `Settings.Connection` rows only (`ConnectionRow` / `ConnectionsPage`) — no File Server expander yet.
- **ℹ️** `docs/filesd-behind-nginx-proxy.md` still tells operators to copy the CA private key by hand.

---

## File Server expander

- **🔷** `⏳` Always present on desktop Connections.
- **🔷** `⏳` Edits `Config2.filesd` (https / proxy / systemd / related) and persists.
- **⏳** Code proposals — draft fences (new expander row reusing the `ConnectionRow` expandable pattern, bound to `Config2.filesd` fields; save → `config.save()`).

---

## TLS material on enable (no hand-copy)

- **🔷** `⏳` On HTTPS enable / first listen: install CA key from shipped resources the same way as CA PEM (no operator copy step).
- **🔷** `⏳` Rewrite the “Place the product CA private key once…” section in [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md) to match automatic install.
- **⏳** Code proposals — draft fences:
  - Bundle `ollmrpc-ca-key.pem` into the GResource (`libocrpc/data/ollmrpc.gresource.xml`) the same way as the PEM.
  - `Https.listen`: replace the `GLib.error("missing CA key … (copy …)")` block with a GResource extraction mirror of the PEM path, writing `{data_dir}/tls/ollmrpc-ca-key.pem`.

---

## Notes

- **ℹ️** Expander UX copies [`8.2.8.1`](RPC-8.2.8.1-filesd-desktop-connections-ui.md) `ConnectionRow` (`Adw.ExpanderRow` + `Adw.ActionRow` suffixes) — read/write here (File Server is editable, unlike approved-client rows).
- **ℹ️** Pattern reference: `Https.listen` CA PEM extraction (`ollmfilesd/Https.vala`).
- **⏳** Code proposals — after design sign-off; otherwise ready to draft fences.

---

## LLM notes

- **ℹ️** Parent Phase 1 owns `Config2.filesd` + `Https.listen` CA PEM extraction — this sub-plan extends the key install, not the PEM path.
- **🚫** Live HTTPS rebind without daemon restart when `filesd.https` changes from the UI (deferred — see parent LLM notes).
- **🚫** Putting file-server listen settings into `Settings.Connection` LLM map.
- **🚫** Operator hand-copy of CA key as the supported enable path.
