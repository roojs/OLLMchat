# Bug Fix Process

## Never hide bugs

**NEVER add protective or defensive checks** (null checks, fallbacks, "just in case" guards, swallowing errors, default values that mask bad state) **to mask failures or symptoms.** That only hides the problem: the underlying defect stays, and you fix the wrong layer.

**Aim for the root cause** — why the bad value, wrong path, or invalid state appears — **not** only what it triggers downstream (a crash, a warning, a bad UI). Fixing or silencing the trigger without fixing the source repeats the failure in another form.

We only discover issues like the documentation search null because we don't paper over them—failures surface and get fixed at the source.

## Required process

When fixing a bug, follow this order. Do not skip steps or apply code changes before approval.

### a) DEBUG first

- Reproduce the failure.
- **Issue log (`docs/bugs/`):** **Always** create or update a file under **`docs/bugs/`** **unless** the change is **trivial**: a **single line** and you already know it is the correct fix. Otherwise keep a **paper trail**:
  - **Resolved logs:** When a bug is **fully** fixed and verified, move its **`…-FIXED-….md`** file to **`docs/bugs/done/`** (keep the same filename). Active **`docs/bugs/`** holds OPEN investigations and non‑trivial in‑progress logs.
  - **Name:** **`YYYY-MM-DD-{short-slug}.md`** — use **today’s date** (calendar day you start or update the log) as the prefix, plus a **kebab-case** slug. Add **`FIXED`** in the name only when the bug is **fully** resolved and verified (e.g. `2026-04-19-FIXED- vector search results.md`, `2026-04-04-FIXED-markdown-link-digit-lead.md`).
  - **Problem** — what's wrong, how to reproduce, expected vs actual.
  - **Attempts / changelog** — code or config changes (file + purpose); **debug code added** (file, what it logs, how to run, e.g. `build/oc-markdown-test --debug tests/markdown/foo.md`).
  - **Conclusions** — what's ruled in/out, root cause if known, open questions.
  - **Record of what was tried** — enough that others don't repeat dead ends.
  - **After the fix** — final conclusion (link plan/commit if useful); remove temporary **`GLib.debug()`** when merged (note in the log if helpful).
- Add **minimal, targeted** logging—only what's needed to see the real values and control flow. Don't splatter debug code everywhere; keep it small so we're less likely to forget to remove it.
- Use **GLib.debug()** for debug output. Do not add method/class name in the message—file and line are already in the output.
- **OLLMchat test apps** (`TestAppBase`, main app): `GLib.debug()` is routed through `ApplicationInterface.debug_log`. Pass **`--debug`** so debug lines are printed to stderr. Setting `G_MESSAGES_DEBUG` alone is not enough for those programs because the default GLib log handler is replaced.
- Prefer **readable output**: use strings when they're more relevant than raw numbers (e.g. paths, IDs with context, "found"/"not found"); length alone is rarely enough. Output length is fine if it helps.
- Run and capture evidence. Do not guess.
- **Performance bugs:** Prefer **narrowing the hotspot** before big refactors — e.g. **A/B-style** runs: temporarily **disable or bypass** a section (feature flag, early return, comment out a call) and measure again; mix that with **targeted** logging or timing at real boundaries (phase starts/ends, not hot-loop spam) so you can see which region dominates. Record each experiment in the same **`docs/bugs/YYYY-MM-DD-*.md`** log (or start a new dated file if it is a separate investigation).

### b) Understand the real issue

- From the evidence, identify the **root cause** (wrong data, wrong place, wrong assumption, missing step) — not merely where it exploded or what symptom appeared first.
- Document it (e.g. in a plan or comment): what's wrong, **why** it happens, and what would be wrong to "fix" if you only patched the trigger.

### c) Propose fix

- Propose a concrete fix that addresses the root cause, not the symptom.
- Describe the change and where it goes. No defensive workarounds.

### d) Get approval

- Present the diagnosis and proposed fix to the user (or reviewer).
- Wait for explicit approval before editing code.

### e) Only apply after approval

- Implement the approved fix only.
- Do not add extra "safety" checks or fallbacks unless they were part of the approved fix.

## Summary

1. **DEBUG first** (including **`docs/bugs/YYYY-MM-DD-*.md`** unless a **one-line** fix is already certain) → 2. **Understand real issue** → 3. **Propose fix** → 4. **Get approval** → 5. **Apply only after approval**

No guards or symptom-only patches that hide the real bug.
