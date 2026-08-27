# 8.4.4.1 — DONE — RPC consumers: throw, then audit callers (items 1–5)

**Status:** **DONE** ✅

**Parent:** [`RPC-8.4.4-DONE-rpc-invoke-errors.md`](RPC-8.4.4-DONE-rpc-invoke-errors.md)

**Continuation:** [`RPC-8.4.4.2-DONE-rpc-consumer-audit.md`](RPC-8.4.4.2-DONE-rpc-consumer-audit.md)

---

## Purpose (landed)

- **🔷** `✔️` **Phase 1** — wrappers / `rpc.call` sites throw; delete old `response.error` / canned-`FAILED` swallows.
- **🔷** `✔️` **Phase 2 items 1–5** — see below.

### Items 1–5

| # | Site | Outcome |
| --- | --- | --- |
| 1 | `rpc_project_description` | Catch, critical, return `""` |
| 2 | `rpc_roots` | Catch, critical, empty list |
| 3 | Tools / CLI that already throw | No code |
| 4 | Restore / revert reload | `Alert.show` + Window Banner queue |
| 5 | Overlay scan | `has_file` throws; soft fails → `Banner.show` |

**Shared contract:** Progress → ActivityBanner; soft notice → `Banner.show`; must-act → `Alert.show`; else log.

**Tree:** `libocfiles/`, `liboctools/FileVerification.vala`, `libocbwrap/`, `ollmapp/Window.vala`.
