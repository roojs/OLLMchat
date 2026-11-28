# 2.16 Edit output format — strategy (archived fork)

## Status

✅ **CLOSED** — **Path A only.** Enable-then-fence and Path B removed. Canonical spec: [EDIT-2.17](EDIT-2.17-always-on-edit-capabilities-syntax-permissions.md).

## Purpose

Historical decision record: why we abandoned `write` → fence streaming and gated `write` + tags.

- [Phone/desktop `write` loops](../bugs/2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md) — `ornith-1.5:35b` loops empty `write`.
- [Always-on POC](../bugs/2026-11-27-FEATURE-always-on-edit-brace-syntax-poc.md) — one-turn `<write>` without tools.
- [Activation not viable](../bugs/2026-11-27-ISSUE-edit-mode-tool-activation-plan-not-viable.md).

## Outcome

| Path | Verdict |
| ---- | ------- |
| **A — always-on `<write>` tags** | **Proceed** — parser + permissions per [EDIT-2.17](EDIT-2.17-always-on-edit-capabilities-syntax-permissions.md). |
| Enable-then markdown fences | **Dead end** — do not invest in prompts or harness copy. |
| **B — `write` then tag body** | **Dead end** — same model failure class as fences. |

## Probes (record)

| Id | Result |
| -- | ------ |
| A0 | ✔️ `ornith`, no tools, complete file in one `<write>` ([`last-run.txt`](../../tests/data/always-on-edit-brace-poc/last-run.txt)). |
| B0 | Tag copy on tool without parser — observation only; **does not revive Path B**. |

## CLI scriptable mode (future)

Line-oriented markers for multi-turn bash drivers — defer to implementation plan under EDIT-2.17 § suggested order. Proposal kept in [EDIT-2.17](EDIT-2.17-always-on-edit-capabilities-syntax-permissions.md) LLM / follow-on.

## LLM

- ℹ️ Closed **2026-11-28**; do not extend this file — use EDIT-2.17.