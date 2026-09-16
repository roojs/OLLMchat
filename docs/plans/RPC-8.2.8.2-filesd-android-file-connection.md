# 8.2.8.2 — Android file connection + unlock agents

**Status:** **PROPOSED** — design locked in parent; code proposals not yet written

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Depends on:**
- Phase 1 of parent (**✔️** agent-done) — `RPC-ClientCert.request_registration` + gate
- [`RPC-8.2.8.1-filesd-desktop-connections-ui.md`](RPC-8.2.8.1-filesd-desktop-connections-ui.md) — desktop Accept so Android can leave pending

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Connections tab: **Add file connection** — HTTPS URL of the remote file server (`https://host:port` or public nginx front).
- **🔷** On connect: mint/load **device client cert**, present it, call `request_registration` if not registered, then use normal file RPC when approved.
- **🔷** A verified file connection **unlocks** agents that need file/project tools (today Android only registers Chatter; desktop registers Code Assistant etc. after `ProjectManager` connects).

---

## Current behaviour

- **ℹ️** Android Connections tab reuses the desktop Connections page; no file-server connection yet.
- **ℹ️** Android `OLLMfiles.ProjectManager` is a stub; desktop boots local Unix `ollmfilesd` and registers Code Assistant / related agents.
- **ℹ️** `OLLMrpc.Client` HTTP path exists; `Transport.HttpClient.tls_certificate` is ready — Android client-cert mint/load not wired.
- **ℹ️** Product CA trust on Android already has TLS helpers (`AndroidConnectionTls` / config TLS) for LLM HTTPS — file-server CA trust must use the **product CA** PEM, not the device trust store alone.
- **ℹ️** `libocfiles.ProjectManager` today hard-wires Unix sock under `~/.local/share/ollmchat` — Android needs construct-time HTTPS socket path + client cert on the HTTP transport.

---

## Goal detail

- **🔷** `⏳` Add file connection UI (HTTPS URL).
- **🔷** `⏳` Mint/load device client cert; present on TLS; call `RPC-ClientCert.request_registration` when unknown.
  - Include a basic **machine type** on registration (see [`8.2.8.1`](RPC-8.2.8.1-filesd-desktop-connections-ui.md)) so the desktop can label the client.
- **🔷** `⏳` After desktop Accept (`status = 1`), use normal file RPC over HTTPS.
- **🔷** `⏳` Verified connection unlocks agents that need file/project tools.
- **💩** `⏳` Config shape: dedicated `Config2` field (e.g. file-server URL / `FilesdClient`) **or** a typed row beside LLM connections — **not** reusing `Settings.Connection` URL-as-Ollama without a type discriminant. Prefer a small nested settings object + one URL.
- **💩** `⏳` One file connection on Android for v1 (not a list).
- **💩** `⏳` “Unlock agents” = when HTTPS `ProjectManager` / `OLLMrpc.Client` is connected and registered, register the same agent factories / tools Android can support (subset of desktop). Exact agent list = confirm (Code Assistant? Agent Pi? Chatter stays always).
- **💩** `⏳` While pending approval: show status on the file-connection row (“waiting for desktop accept”); do not unlock agents until `status = 1` / successful non-registration RPC.

---

## Open questions (need 🔷)

1. Android: **one** file-server URL, or multiple?
2. Which agents unlock on Android once the file connection works?

---

## Notes

- **ℹ️** Operator nginx doc: [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md).
- **⏳** Code proposals — after design sign-off on open questions.

---

## LLM notes

- **ℹ️** Registration gate and int status live in parent Phase 1 — Android only consumes `request_registration` + approved RPC.
- **🚫** Unban / admin cert mutate over HTTPS.
- **🚫** Treating ban as a permanent certificate revoke.
- **🚫** Reusing `Settings.Connection` as the file-server URL without a type discriminant.
