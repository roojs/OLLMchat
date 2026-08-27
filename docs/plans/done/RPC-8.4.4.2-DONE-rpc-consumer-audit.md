# 8.4.4.2 — DONE — RPC consumers: Phase 2 items 6–13

**Status:** **DONE** ✅

**Parent:** [`RPC-8.4.4-DONE-rpc-invoke-errors.md`](RPC-8.4.4-DONE-rpc-invoke-errors.md)

**Prior:** [`RPC-8.4.4.1-DONE-rpc-consumer-audit.md`](RPC-8.4.4.1-DONE-rpc-consumer-audit.md)

---

## Purpose (landed)

Phase 2 items **6–13** — catch vs Banner / Alert / log / LLM error string per site.

| # | Site | Severity |
| --- | --- | --- |
| 6 | `ValidateLink` | Log only (narrow try per yield) |
| 7 | File dropdown / review list | Banner; keep last good page |
| 8 | Save / reload / disk-check | Alert / Banner / Banner |
| 9 | Approve / revert buttons | Alert; no refresh on fail |
| 10 | Load / create / remove project | Alert (startup/create/remove); Banner (Settings tab) |
| 11 | HF download / Summarize vectors | Banner / log only |
| 12 | Activate project / banner `rpc.*` | Banner |
| 13 | `WriteFile.validate` / `EditMode/Stream` | Error string / LLM summary |

**Tree:** `liboccoder/`, `libocfiles/`, `liboctools/`, `ollmapp/Window.vala`, `ollmapp/SettingsDialog/ProjectsPage.vala`.
