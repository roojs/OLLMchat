# Windows file-daemon TCP port is not configurable

**Status:** ⏳ OPEN — user report 2026-09-20; fix not applied

**Started:** 2026-09-20

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ Config already reserves `filesd.socket` as `host:port` (`libollmchat/Settings/Filesd.vala`) — listen never reads it
- ℹ️ Linux File Server expander is HTTPS only (`ollmapp/SettingsDialog/FileServerRow.vala`); Windows does not build that row (`#if !ANDROID && !G_OS_WIN32` in `ConnectionsPage.vala`)
- ℹ️ LAN TCP + TLS registration (Linux, non-loopback) is a plan, not this bug: [`RPC-8.2.8.7-filesd-tcp-socket-lan.md`](../plans/RPC-8.2.8.7-filesd-tcp-socket-lan.md)

---

## Problem

🔷 Windows local `ollmfilesd` speaks **bin RPC over TCP**, not a Unix socket. The listen port is **not** in Connections / File Server settings.

🔷 Expected: the operator can **set the Windows TCP port** (persist it, spawn and connect on that port).

🔷 Actual: the port is **hardcoded 4141** in the daemon CLI defaults, Windows `ClientBoot`, `TcpListen`, and `is_running()`. `filesd.socket` stays empty and unused.

---

## Evidence

- ✔️ `ollmfilesd/Application.vala` — `opt_tcp_port = 4141`; `#if G_OS_WIN32` forces `opt_tcp`; `is_running()` probes `127.0.0.1:4141` only
- ✔️ `libocrpc/windows/ClientBoot.vala` — parse/spawn/connect default port **4141**; `connect()` requires a `tcp://` URL
- ✔️ `libocrpc/Transport/TcpListen.vala` — default `127.0.0.1:4141`
- ✔️ `OLLMfiles.ProjectManager` always constructs `OLLMrpc.Client(…, "ollmfilesd.sock")` — no `filesd.socket`, no `tcp://`
- ✔️ [`RPC-8.2.8.3`](../plans/done/RPC-8.2.8.3-DONE-filesd-file-server-tls.md) — Windows is loopback TCP `127.0.0.1:4141`; File Server expander is Linux HTTPS, not that port

---

## Root cause

✔️ `filesd.socket` was reserved in [`RPC-8.2.7`](../plans/RPC-8.2.7-client-cert-registration.md) as config-only. Windows never grew a UI or a read of that field, so 4141 stayed the only listen/connect port.

---

## Proposed fix

🔷 Persist the Windows listen endpoint on `filesd.socket` (`host:port`, same shape as `filesd.https`).

🔷 Connections (Windows): a **port** control for that loopback TCP listener so 4141 is a default, not a constant.

🔷 Spawn, probe, and client connect must use the saved `filesd.socket` (including `is_running()` and `windows/ClientBoot`).

ℹ️ Linux `filesd.socket` empty / port **0** means **no TCP** (Unix socket stays). That sentinel and LAN TLS are [`8.2.8.7`](../plans/RPC-8.2.8.7-filesd-tcp-socket-lan.md), not this bug.

💩 Ephemeral bind (port `0` → OS-chosen port, then write it back) — `HttpServer` already does that for HTTPS; not asked for Windows.

🚫 TLS / client-cert registration on the Windows loopback socket — LAN TLS is the Linux plan.

🚫 nginx PROXY / WAN on this listener.

⏳ Verbatim **Remove** / **Replace with** / **Add** fences after the UI surface is agreed (Windows File Server row vs port-only suffix).

---

## Attempts / changelog

- ✔️ 2026-09-20 — User: Connections / File Server has no Windows socket port; split Windows port (this log) from Linux LAN TCP plan.

## Next

- ⏳ 🔷 Agree Windows UI: port field only vs a Windows File Server expander (no HTTPS / systemd)
- ⏳ 🔷 Propose fences: `Filesd` / Windows `ClientBoot` / `ProjectManager` or Window connect path / `is_running()`
