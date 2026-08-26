# 6.1.9 Offer to create `AGENTS.md`

Status: ⏳ proposed

ℹ️ Checklist: `docs/guide-to-writing-plans.md` — Checklist for plans.  
ℹ️ Parent: [6.1.2](done/6.1.2-DONE-pi-like-agent.md) Phase 1. Content / skill: [6.1.12](CODER-6.1.12-write-agents-md-skill.md). Split out of former Phase 9.  
ℹ️ Banner: [`ollmapp/ActivityBanner`](../../ollmapp/ActivityBanner.vala) — [5.0.6](../plans/done/5.0.6-DONE-activity-progress-actions.md).

## Purpose

- 🔷 `⏳` When Agent Pi is selected and a project is active/opened and project-root has no `AGENTS.md`, offer to create one (Pi never prompts; we may).
- 🔷 `⏳` Create runs the **`writing-agents-md` skill** ([6.1.12](CODER-6.1.12-write-agents-md-skill.md)) — not a canned stub.
- ℹ️ Agent-facing missing-file hint (even without the banner) is [6.1.12](CODER-6.1.12-write-agents-md-skill.md). This plan is the **user** banner.
- ℹ️ Phase 1 still **omits** a fake agents body when missing — [6.1.12](CODER-6.1.12-write-agents-md-skill.md) adds a `missing_project_agents` hint instead.

---

## Copy / trigger

Pi never prompts. We may when **Agent Pi is selected** and a **project is active/opened** and project-root has no `AGENTS.md` (CLAUDE-only **💩**):

> This project has no AGENTS.md — create one?

**Where:** ActivityBanner — header status strip used for scan/vector/download progress. Same spine: `History.Manager.notification` → banner; action via `action` / `action_label` → `notification_reply`.

- 🔷 `⏳` Emit a `client.*` (or similar) notification: message = missing-AGENTS copy; `action_label` = e.g. `Create`; `action` = handler id for Agent Pi / Window.
- 🔷 `⏳` On Create: start [6.1.12](CODER-6.1.12-write-agents-md-skill.md) (agent turn / user message that runs `writing-agents-md`). Do **not** write a canned stub.
- 🔷 `⏳` Trigger when: switch **to** `agent-pi` with a project already active, **and/or** activate/open a project while Agent Pi is current. Debounce / once-per-project-per-session **💩**.
- 💩 Dismiss without Create — banner auto-hide timeout already exists; explicit Dismiss needs a second button (banner today has **one** action) or treat hide-as-dismiss.
- 💩 Collision with live progress (scan/index/download): don’t clobber an in-flight progress notification; queue or wait until banner idle (**💩** exact policy).

---

## Suggested order

1. Lock trigger + debounce + CLAUDE-only edge case.
2. Wire notification → ActivityBanner Create action.
3. Create → [6.1.12](CODER-6.1.12-write-agents-md-skill.md) skill path; confirm inject picks up the real file on next send.

---

## LLM notes

- ℹ️ Soft-cap for AGENTS inject size (% of model context) remains a **later** item after this offer lands (optional follow-up; noted on [done/02](done/6.1.2-DONE-pi-like-agent.md)).
- 🔷 Agent id `agent-pi`.
- 🚫 Do not invent a default packaged AGENTS.md body for empty projects (Phase 1: omit inject). Content contract is [6.1.12](CODER-6.1.12-write-agents-md-skill.md).
