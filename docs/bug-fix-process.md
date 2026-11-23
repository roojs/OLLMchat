# Bug Fix Process

## Never hide bugs

**NEVER add protective or defensive checks** (null checks, fallbacks, "just in case" guards, swallowing errors, default values that mask bad state) **to mask failures or symptoms.** That only hides the problem: the underlying defect stays, and you fix the wrong layer.

**Aim for the root cause** — why the bad value, wrong path, or invalid state appears — **not** only what it triggers downstream (a crash, a warning, a bad UI). Fixing or silencing the trigger without fixing the source repeats the failure in another form.

We only discover issues like the documentation search null because we don't paper over them—failures surface and get fixed at the source.

## Required process

When fixing a bug, follow this order. Do not skip steps or apply code changes before approval.

### a) DEBUG first

- Reproduce the failure.
- **Issue log (`docs/bugs/`):** **Always** create or update a file under **`docs/bugs/`** **unless** the change is **trivial**: a **single line** and you already know it is the correct fix. Otherwise keep a **paper trail**. **Shape, sections, and filename** are defined in **`docs/guide-to-writing-bug-reports.md`** (read that guide when opening or restructuring a log).
  - **Resolved logs:** When the **user confirms the whole bug is done**, set **`Status:`** **✅** and **move** the file to **`docs/bugs/done/`** in the same update (add **`FIXED`** or **`CLOSED`** in the slug when that matches existing convention). **Active `docs/bugs/`** holds only **⏳** and **✔️** — no user-done reports left in the open folder.
  - **Name:** **`YYYY-MM-DD-{ISSUE|FEATURE}-{kebab-slug}.md`** — **today’s date** when you create the file, plus **`ISSUE`** (broken behavior) or **`FEATURE`** (new/extended behavior), plus a **kebab-case** slug.
  - **Body:** **User decisions required** (**💩** or **`None.`** — update when stopping for approval/device/cross-repo), **User reported**, **Success scenario**, **Current behavior** (relevant only: what you said, tool calls, verbatim tool/assistant text when it is the repro, tight outcomes — rest in **LLM**), **Codebase observed behavior** (file links + short snippets), **Debugging** (**Current debug output** = `*.debug.log` fences only; session JSON text → **Current behavior**; **Debug code added**), **Proposed fix** (phased when large; **✔️** on applied phase headings), **LLM** (everything else agents need; user can skip). **Lists, not paragraphs** — **`docs/guide-to-writing-bug-reports.md`**. Do not use the old generic “Problem / Evidence / Attempts” layout for new reports.
  - **After apply** — set **`Status:`** to **✔️**; file stays in **`docs/bugs/`**. **After user verify of the whole fix** — **`Status:`** **✅** and **must** live under **`docs/bugs/done/`** (see **`docs/guide-to-writing-bug-reports.md`** — **Filenames and folders**). Remove temporary **`GLib.debug()`** when merged (note under **Debug code added** / **LLM** if helpful).
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
- When the fix needs code edits, put **verbatim** **`#### Remove`** / **`#### Replace with`** / **`#### Add`** fences in the bug log under the topic that owns the change — same contract as **`docs/guide-to-writing-plans.md`** (**Edit syntax contract**, **Code proposals — one place, not two**). Do not leave “change X to Y” as prose only.
- Do not hack product code while discovering the fix. Debugging may add minimal, recorded instrumentation, but implementation must match the documented proposal. If evidence changes the fix, update the proposal before changing product code.

### d) Continue or request a decision

- Continue autonomously when the root cause is confirmed and the proposal uses an existing in-tree pattern or is a routine, reversible correction with no material product-design choice.
- **Stop turns** only as in **`docs/guide-to-writing-bug-reports.md`** (**Agent stop points**): **A**–**E** (including **E** cross-repo bug report + **scope** — no edits outside this workspace without explicit permission), or the listed **material decision** exception.
- **Requesting a decision (especially **B** or a material choice):** put the full argument in the bug report (**Proposed fix**, **LLM**, etc.). In chat, **one line only** — stop code + pointer to what to read, e.g. “**B** — review **Proposed fix → Phase 2** in [`docs/bugs/….md`](docs/bugs/….md).” **Never** dump the proposal, evidence, or options into the prompt; that belongs in the report.
- Other stops (**A**, **C**, **D**, **E**): same rule — **one sentence** in chat (code + minimal fact), not an essay.
- Do not stop merely to report progress, restate status, or ask permission for a routine next step already determined by the evidence.
- **“Was that a valid stop point?”** (or similar): means **carry on** — resume **d** → **e** as allowed. **Do not** explain that the stop was invalid; see **`docs/guide-to-writing-bug-reports.md`** (**Agent stop points** — *When the user asks about stop points*).
- When a new failure appears during verification, record and diagnose it, update the proposal, and continue under the same rule. Do not apply an improvised workaround.

### e) Apply the documented proposal

- Implement only the documented proposal once section d permits continuing or the user approves the major change.
- Do not add extra "safety" checks or fallbacks unless they were part of the approved fix.

## Bug log markup (emoji + shape)

**Canonical layout:** **`docs/guide-to-writing-bug-reports.md`**. Summary:

- **Header:** title + **`Status:`** **⏳** (open), **✔️** (applied), or **✅** (user confirmed done) only — **✅** is **not** for applied-only; see plans guide **✅** vs **✔️**.
- **🔷** only in **User reported** (user intent, grammar-fixed).
- **No emoji** in **Success scenario**, **Current behavior**, **Codebase observed behavior**, or **Current debug output** intro lines (blocks are raw log text).
- **LLM** section: full legend from **`docs/guide-to-writing-plans.md`** (**Discussion style (emoji prefixes)**) — **ℹ️**, **💩**, **🚫**, **⏳**, **✔️**, etc.

| Marker | Typical use (mostly **LLM**) |
| ------ | ------------------------------ |
| 🔷 | **User reported** only |
| 💩 | Agent hypothesis or unconfirmed proposal |
| ℹ️ | Pointers (log, plan, file, prior bug) |
| 🚫 | Ruled out / do not implement |
| ⏳ | Open work |
| ✔️ | Report **Status** when fix **applied**; also evidence/changelog in **LLM** |
| ✅ | Report **Status** when **user confirmed whole fix** — file **only** in **`docs/bugs/done/`**; **✅** on individual phase headings is OK |

**🚫** Report-level **✅** in **`docs/bugs/`** (active folder). **🚫** Using **✅** on the header for “applied but not verified”. **🚫** Analysis dressed as user report. **🚫** Promoting **✔️ → ✅** without the user.

## Summary

1. **DEBUG first** (including **`docs/bugs/YYYY-MM-DD-{ISSUE|FEATURE}-*.md`** unless a **one-line** fix is already certain) → 2. **Understand real issue** → 3. **Propose fix** (fences in **Proposed fix**; scratch in **LLM**) → 4. **Continue routine fixes or request a major decision** → 5. **Apply only the documented proposal**

No guards or symptom-only patches that hide the real bug.
