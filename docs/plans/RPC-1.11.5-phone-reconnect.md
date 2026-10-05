# RPC-1.11.5 — the phone reconnects when the socket drops

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan** until it is done and archived.

**Status:** proposed

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

**Parent:** [`RPC-1.11.3`](RPC-1.11.3-tcp-client-handover.md)

**Depends on:** [`RPC-1.11.3`](RPC-1.11.3-tcp-client-handover.md) — after the address probe, `ProjectManager` keeps a `Client` on `tcp://`.

---

## Purpose

- **🔷** `⏳` When that connection drops, try to reconnect.
- **🔷** `⏳` On the phone, walking off the local network onto the VPN uses the stored VPN address. VPN up or VPN down drops the current socket and tries the stored addresses a few times.
- **🔷** `⏳` If those tries fail, and the user is actually using the file daemon, tell them it can no longer connect. Follow the existing disabling of `ollmfilesd`: state `UNREACHABLE`, the banner `The desktop environment is unavailable.`, leave Agent Pi, and use Chatter. `AgentDropdown` already hides Agent Pi unless the state is `LIVE` or `SOCKET`.

---

## Current behaviour

- **ℹ️** `probe_addresses` in `ollmapp/android/OllmchatWindow.vala` runs at startup only. It tries each stored address once. None answering sets `UNREACHABLE`, shows `The desktop environment is unavailable.`, and opens Chatter. Nothing retries after a later drop.
- **ℹ️** That failure path is `initialize_client`: `filesd_client.state = UNREACHABLE`, banner `The desktop environment is unavailable.`, session agent `chatter`. `AgentDropdown.wire` hides `agent-pi` for every state except `LIVE` and `SOCKET`.
- **💩** How the phone notices that the VPN came up is not chosen. The drop of the current socket is the trigger already named.

---

## Proposed behaviour

- **🔷** A drop, or the VPN going up or down, disconnects the current `tcp://` and tries the stored addresses a few times.
- **🔷** Outside, on the VPN, that try uses the stored VPN address. When the VPN drops, it tries the local address.
- **🔷** After those tries fail, if the user is using the file daemon, the phone follows the startup failure path already in `OllmchatWindow.initialize_client`.

No code fences yet. The VPN notice is not chosen, so a reconnect fence would be guessing the trigger.
