# 09. Offer to create `AGENTS.md`

Status: ⏳ proposed

ℹ️ Checklist: `docs/guide-to-writing-plans.md` — Checklist for plans.  
ℹ️ Parent: [02-pi-like-agent.md](02-pi-like-agent.md) Phase 1 (inject omits when missing). Split out of former Phase 9.  
ℹ️ Banner: [`ollmapp/ActivityBanner`](../../ollmapp/ActivityBanner.vala) — [5.0.6](../plans/done/5.0.6-DONE-activity-progress-actions.md).

## Purpose

- 🔷 `⏳` When Agent Pi is selected and a project is active/opened and project-root has no `AGENTS.md`, offer to create one (Pi never prompts; we may).
- ℹ️ Phase 1 still **omits** inject when missing — this only offers to create a real file.
- 🚫 Not part of Phase 1 implement.

---

## Copy / trigger

Pi never prompts. We may when **Agent Pi is selected** and a **project is active/opened** and project-root has no `AGENTS.md` (CLAUDE-only **💩**):

> This project has no AGENTS.md — create one?

**Where:** ActivityBanner — header status strip used for scan/vector/download progress. Same spine: `History.Manager.notification` → banner; action via `action` / `action_label` → `notification_reply`.

- 🔷 `⏳` Emit a `client.*` (or similar) notification: message = missing-AGENTS copy; `action_label` = e.g. `Create`; `action` = handler id for Agent Pi / Window.
- 🔷 `⏳` On Create: write a starter `AGENTS.md` at **project root** (template content **💩** — short stub vs richer scaffold).
- 🔷 `⏳` Trigger when: switch **to** `agent-pi` with a project already active, **and/or** activate/open a project while Agent Pi is current. Debounce / once-per-project-per-session **💩**.
- 💩 Dismiss without Create — banner auto-hide timeout already exists; explicit Dismiss needs a second button (banner today has **one** action) or treat hide-as-dismiss.
- 💩 Collision with live progress (scan/index/download): don’t clobber an in-flight progress notification; queue or wait until banner idle (**💩** exact policy).

---

## Suggested order

1. Lock trigger + debounce + CLAUDE-only edge case.
2. Wire notification → ActivityBanner Create action.
3. Write starter template at project root; confirm inject picks it up on next send (Phase 1 path).

---

## LLM notes

- ℹ️ Soft-cap for AGENTS inject size (% of model context) remains a **later** item on [02](02-pi-like-agent.md) suggested order — after this offer lands.
- 🔷 Agent id `agent-pi`.
- 🚫 Do not invent a default packaged AGENTS.md body for empty projects (Phase 1: omit inject).
