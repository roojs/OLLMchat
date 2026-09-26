# 8.2.8.14 — LATER — Windows desktop server

**Status:** **LATER** — not the critical path. Decide later whether to push this further down the line.

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Depends on:** [`RPC-8.2.8.13-filesd-desktop-server-rows.md`](RPC-8.2.8.13-filesd-desktop-server-rows.md) — the Windows row layout is drawn there

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- 🔷 Windows equivalent of `systemctl --user`: a per-user service that starts `ollmfilesd`.
- 🔷 Windows host list for HTTPS server and Local network SSL server.
- ℹ️ The row layout, including Localhost TCP as a Running row with no toggle, is [`8.2.8.13`](RPC-8.2.8.13-filesd-desktop-server-rows.md).
- ℹ️ Changing the localhost TCP port is [`docs/bugs/2026-09-20-filesd-windows-socket-port.md`](../bugs/2026-09-20-filesd-windows-socket-port.md), not this plan.
- ⏳ Code proposals — only if this plan is kept.

---

## Windows support

- 🔷 `⏳` A per-user service that starts `ollmfilesd`. The tree has none today.
- 🔷 `⏳` A Windows host list for HTTPS server and Local network SSL server. `Linux.Network.getifaddrs` does not exist on that build. No Windows interface query is in the tree.
- ℹ️ `FileServerRow` is not built on Windows today (`ConnectionsPage.vala`, `#if !ANDROID && !G_OS_WIN32`).
- ℹ️ Localhost TCP stays the Running row from [`8.2.8.13`](RPC-8.2.8.13-filesd-desktop-server-rows.md). No toggle. No port editor on that row.

---

## LLM notes

- 🚫 TLS on Windows `127.0.0.1`. That listener stays plaintext `TcpListen`.
- 🚫 A port editor for Localhost TCP. That is the bug log.
- 🚫 Doing this work inside [`8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md) or [`8.2.8.13`](RPC-8.2.8.13-filesd-desktop-server-rows.md).
