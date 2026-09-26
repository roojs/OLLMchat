# 8.2.8.10 — `bash` as a remote tool Android can use

**Status:** **PROPOSED** — design only; code proposals not yet written

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md) Phase 12

**Depends on:**

- [`RPC-8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) — Agent Pi on `LIVE` / `SOCKET`. Registers `write` / `read` only. Does not register `Bash`.
- [`BWRAP-2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) — daemon `Bubble.can_wrap` / `Bubble.exec` wire. Not on the wire yet.

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`.

---

## Purpose

- **🔷** A separate ticket. Not stuffed into [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md).
- **🔷** Turn `bash` into a tool the phone can use **remotely**.
  - The command runs on the desktop `ollmfilesd`.
  - Not on the phone.
- **ℹ️** [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) already said that. It pointed at [`BWRAP-2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) and left no child ticket.
- **ℹ️** [`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) is the daemon sandbox RPC. This ticket is the Android `bash` **tool**.
- **⏳** Design in this file. Code fences after the RPC caller shape is agreed.

---

## Current behaviour

- **ℹ️** `liboctools/RunCommand/Bash.vala` is a Pi-facing name on `RunCommand.Tool`. Same `Request` as `run_command`.
- **ℹ️** `Request.execute_tool_async` calls in-process `OLLMbwrap.Bubble.exec` (or `GLib.Subprocess` when bwrap is missing / Flatpak / `run_as_root`).
- **ℹ️** Overlay apply after a local exec is File.* RPC ([`done/2.10.4.19-DONE-runcommand-overlay-index.md`](done/2.10.4.19-DONE-runcommand-overlay-index.md)). The command itself never left the app process.
- **ℹ️** `write` / `read` already go through `ProjectManager` RPC when the client is on HTTPS.
- **ℹ️** Android `initialize_client` registers `write` / `read` only ([`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) Phase 2).
- **ℹ️** `AgentPi.Factory.register_config` `GLib.error`s without `write` / `read` / `bash`. Android therefore does not call `register_config` yet.
- **ℹ️** Daemon `Bubble.*` is still **DEFERRED** ([`FILES-2.10.4.1`](FILES-2.10.4.1-ollmfilesd-rpc-api.md) · [`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md)).

---

## Design decisions

- **🔷** Phone `bash` is an RPC tool. Exec is on the desktop daemon.
- **🔷** Do not register in-process `Bash` on Android.
- **ℹ️** Wire names and result shape stay [`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) Phase A (`Bubble.can_wrap`, `Bubble.exec`). Do not invent a second exec object.
- **💩** This ticket is why `2.10.4.15` Phase A ships. Do not wait for a later V2 flip.
- **💩** Linux desktop keeps in-process `OLLMbwrap.Bubble.exec`. The RPC caller is for a remote file client (`LIVE`).
- **💩** `RunCommand.Request` is the one caller change. `Bash` stays a thin subclass.
- **💩** After `Bubble.exec` is on the wire, Android registers `Bash` then `AgentPi.Factory.register_config`, the same way `write` / `read` are registered today.

---

## Phase 1 — Daemon `Bubble.exec` (`⏳`)

- **🔷** `⏳` `ollmfilesd` answers `Bubble.can_wrap` and `Bubble.exec`.
- **ℹ️** Design, params, and vetoes live in [`BWRAP-2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md). Copy nothing into this file.
- **⏳** Code proposals — in `2.10.4.15`, or a later fence here that only names the files once that plan has hunks.

---

## Phase 2 — `RunCommand.Request` calls `Bubble.exec` over RPC (`⏳`)

- **🔷** `⏳` When the file client is `LIVE`, `Request` runs the command through `Bubble.exec` RPC. Not `OLLMbwrap` in the Android process.
- **💩** `⏳` `SOCKET` (local Unix desktop) stays in-process bwrap unless a later review says otherwise.
- **ℹ️** Overlay / index update after daemon exec is the daemon's job in `2.10.4.15` (`Scan` + `FileVerification` on `ollmfilesd`).
- **⏳** Code proposals — after Phase 1 is on the wire.

---

## Phase 3 — Android registers `bash` (`⏳`)

- **🔷** `⏳` `ollmapp/android/OllmchatWindow.vala` `initialize_client` registers `OLLMtools.RunCommand.Bash` next to `write` / `read`, then `AgentPi.Factory.register_config`.
- **🔷** `⏳` Still no in-process exec on the phone. Registration is only valid once Phase 2 uses RPC.
- **⏳** Code proposals — after Phase 2 compiles.

---

## Suggested order

1. **⏳** Phase 1 — daemon `Bubble.*` ([`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) Phase A)
2. **⏳** Phase 2 — `RunCommand.Request` RPC caller when `LIVE`
3. **⏳** Phase 3 — Android `Bash` + `AgentPi.Factory.register_config`

---

## LLM notes

- **🚫** Registering in-process `Bash` on Android so Agent Pi can start. That runs on the phone.
- **🚫** A new RPC object (`Exec.*`, `Bash.*`, `RunCommand.*`). The wire is `Bubble.*`.
- **🚫** Putting these hunks into [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md).
- **🚫** `run_as_root` / sudo over RPC ([`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md)).
- **🚫** MCP stdio session RPC (`2.10.4.15` Phase B).
- **🚫** Helper methods unless a later fence names one.
