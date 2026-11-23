# Guide to writing bug and feature reports

Written for **AI agents** — **mandatory** when creating or restructuring files under **`docs/bugs/`**. Human contributors may use it as a checklist.

Process order (debug before code) stays in **`docs/bug-fix-process.md`**. **Code proposals** in reports follow the same **Remove** / **Replace with** / **Add** rules as **`docs/guide-to-writing-plans.md`** (**Edit syntax contract**). Vala proposals must match **`docs/coding-standards.md`** (use **`docs/coding-standards-router.md`** when implementing).

This guide defines **shape and tone** of a report. It replaces the old “one generic layout with emoji everywhere” pattern.

## Agent stop points (chat turn)

When you **end a turn** on bug or report work, stop **only** for a reason in the table below (or the single exception after it). In the **chat reply**, **one line only**: stop code (**A**–**E**) + where to look (report path and **User decisions required** or **section/phase heading**). Put the decision write-up in **`### User decisions required`** (💩 bullets) — **never** paste the proposal, evidence, or decision essay into the prompt.

| Code | Stop when |
| ---- | --------- |
| **A** | A **minor** fix is **applied** in the tree (trivial or already-approved proposal; build/lint as usual). |
| **B** | **Proposed fix** is written in the report under **Proposed fix** and you are **waiting** for user approval before changing product code (**DEBUG first** / non-trivial). Chat: e.g. “**B** — review **Proposed fix** (or named phase) in `docs/bugs/…`.” |
| **C** | The next step needs action **only the user** can do on the machine — things an unprivileged agent session cannot do (e.g. `sudo`, system package install, writing under `/usr`, release scripts the user runs, device-only verify). One sentence: what to run or check. |
| **D** | The user asked for **documentation-only** work (report, guide, changelog note) and that request is **finished**. |
| **E** | The fix or evidence belongs in **another repository** (not this workspace) — you will **not** edit that tree this turn. One sentence: you want a **bug report opened there** and **why** (single reason, not a write-up). Wait for explicit permission before creating or editing files outside this repo. |

**Scope:** Work **only** in this workspace unless the user **explicitly** allows another path or repo. **Never** edit another project’s product code, vendor trees, or “someone else’s” checkout without that explicit allowance — even if you can read paths on disk (e.g. Argus logs). Cross-repo need → **E**, not silent edits elsewhere.

**Only other allowed stop:** a **material** product, API, persistence, security, compatibility, or destructive choice with **no** clear in-tree precedent — **💩** lines in **User decisions required** (options + ask); chat **one line** pointing there (same as **B**).

**Do not stop** to restate status, ask “want me to apply?” after the proposal is already in the report, pause for routine verify you can run yourself, or for any reason outside **A**–**E** and the exception above. Record progress in the report **LLM** section and keep going when the process allows.

**When the user asks about stop points** (“was that a valid stop point?”, “continue”, “carry on”, rule tweaks, etc.): they mean **no — keep working**. Resume the open bug or task (apply, debug, edit the report, verify). **Do not** answer the question literally (no “that wasn’t valid because…”, no table recap, no apology). Note any course correction in the report **LLM** if needed; in chat, **do the next step** — or **one line** only if a real **B**/**C** block still requires them.

## Markdown formatting (prose)

Bug logs are markdown, not Vala — **do not chop prose** to imitate code line-length rules.

- **One logical line per bullet or sentence** in the source file. Do not hard-wrap at ~72/80 columns so a sentence continues on the next physical line mid-phrase.
- **Do not** break links, `` `paths` ``, or file names across lines — e.g. keep [`libocrpc/Client.vala`](../../libocrpc/Client.vala) on one line.
- **Code fences** inside **Proposed fix** follow the plans **Edit syntax contract**; wrapping inside ```vala blocks follows **`docs/coding-standards.md`** when you paste real code — that is separate from markdown prose.

### Lists, not paragraphs (mandatory)

Same spirit as **`docs/guide-to-writing-plans.md`** (**Discussion style** — nested bullets, no essays). Applies to **Success scenario**, **Current behavior**, **Codebase observed behavior**, **Debugging** (context only), **Proposed fix** (**Why** / **Investigate** / **Steps**), and **LLM**.

- **One idea per bullet.** If a bullet would need a second sentence, a comma-heavy clause, or **`;`**, split into **nested sub-bullets** under a short parent label.
- **🚫 Paragraph blocks** under section headings (three or more sentences in a row without list markup).
- **🚫 “Wall” bullets** that pack repro + logs + interpretation into one line — parent bullet names the topic; children hold each fact or log pointer.
- **Prefer labels as parents** — e.g. `- Repro`, `- On device`, `- ollmfilesd.debug.log` — with 2–4 child bullets or a single fence child.
- **Debug log evidence** (`*.debug.log`, daemon/client traces) belongs under **Debugging → Current debug output** (fences), not long paraphrase bullets in **Current behavior**.
- **Current behavior** holds **what you said**, **tool calls**, **verbatim harness/chat text** when it defines the repro (tool results to the model, assistant fences, empty turns), and **tight observable outcomes** — see that section; repro metadata and hypotheses → **LLM**; raw debug logs → **Debugging**.

## Filenames and folders

| Location | What belongs there |
| -------- | ------------------- |
| **`docs/bugs/`** | **Active** only — **`Status:`** **⏳** or **✔️**. Applied-but-unverified reports stay here so they are easy to find. |
| **`docs/bugs/done/`** | **Closed** only — the whole report is user-done. Header **`Status:`** **✅** (or legacy **FIXED** / **CLOSED** slugs). |

**🚫 Never** leave a **user-confirmed-done** report in **`docs/bugs/`**. When the **whole** issue is fixed and the user confirms, **move the file to `done/` in the same edit** that sets **`Status:`** **✅**. A file with report-level **✅** must not sit in the active folder.

Rename on archive if needed (e.g. add **`FIXED`** or **`CLOSED`** in the slug) per existing convention — see **`docs/bug-fix-process.md`**.

**Pattern:**

```text
YYYY-MM-DD-{ISSUE|FEATURE}-{kebab-slug}.md
```

| Kind | Use when |
| ---- | -------- |
| **ISSUE** | Something is wrong: regression, incorrect behavior, hang, data loss, etc. |
| **FEATURE** | New or extended behavior that is not purely “fix broken X” (may still block users; urgency is separate from kind). |

Use **today’s calendar date** when you **create** the file or start a **new** investigation file. Keep the date prefix when renaming for ISSUE/FEATURE only.

**Examples:** `2026-11-22-ISSUE-client-disconnect-idempotent.md`, `2026-11-21-FEATURE-rpc-daemon-hello-version-mismatch.md`.

## Header (only two lines)

1. **`#` Title** — One short sentence: the problem (**ISSUE**) or the capability gap (**FEATURE**). No subtitle stack.
2. **`**Status:**`** — **Only** one marker (same **✅** / **✔️** contract as **`docs/guide-to-writing-plans.md`** — **Discussion style (emoji prefixes)**):
   - **⏳** — Open: investigating, proposing, or awaiting approval to apply.
   - **✔️** — **Applied** — fix is in the tree (agent landed it); user has **not** confirmed done yet. Use this so applied reports are easy to spot for bulk moves to **`docs/bugs/done/`** after verify.
   - **✅** — **User confirmed done** for the **whole report** — only on files under **`docs/bugs/done/`**. **Do not** use **✅** for “applied but not verified”. **Do not** promote **✔️ → ✅** without the user.

Do **not** put pointers, dates, “Started”, Argus paths, or process links under the header. Those belong in **LLM** (below).

**✔️** reports stay in **`docs/bugs/`** until the user confirms the whole fix; then **✅**, **move to `done/`**, and optionally rename (e.g. `…-FIXED-…`).

## Body sections (in order)

Use these headings. **ISSUE** and **FEATURE** share the same skeleton; FEATURE reports still describe “what’s missing” in **Current behavior** and “what we want” in **Success scenario**.

### User decisions required

**First section after the header.** What the user must decide, approve, or do **before** work can continue — scan this before reading the rest.

- Each open item: **💩** at the start of the line (per **`docs/guide-to-writing-plans.md`** — needs user input, not yet authoritative).
- One short sentence per item: approve a **Proposed fix** phase, pick between options, run something on device, allow cross-repo work (**E**), etc.
- When you **stop** the chat turn for **B**, **C**, **E**, or a material choice, **update this section** before ending — add or refresh **💩** lines; clear or replace items when the user answers.
- When nothing is blocked on the user: a single plain line **`None.`** (no **💩**).

### User reported

- Bullets prefixed with **🔷** only here (and only for **verbatim user intent**).
- Light grammar fix only — **no** jargon rewrite, **no** analysis, **no** “we think” or evidence language.
- Append new bullets when the user adds detail in chat; still **no** analysis.

### Success scenario

Plain bullets (no emoji): what must be true on device or in logs before this report can move to **✅** (user confirmed) and archive. Acceptance criteria, not implementation steps.

### Current behavior

**Relevant information only** — what a human needs to understand **what happened in the repro**, without reading the rest of the report. **Nested bullets only** (see **Lists, not paragraphs**).

**Include (typical shape):**

- **What you said** — user utterance(s) from the session (quote or light grammar fix), or one line that the transcript is missing and where it will be filled from.
- **Tool calls** — tool name + material arguments, **in session order** (from saved history JSON `tool-calls`, or log lines that name the tool — e.g. `Executing tool 'write'`). One line per call; collapse only identical repeats when the count is the point.
- **Observable product outcome** — only facts tied to those utterances/calls (e.g. “next assistant turn called `write` again with empty body”, “UI showed Edit Mode Activated again”), not mood words or comparisons to other bugs.
- **Verbatim session text** — when the bug is “what did the harness tell the model” or “what did the model stream”, paste the **exact** tool reply or assistant block here (fenced), not a paraphrase. Source: saved session JSON, not `*.debug.log`.

**🚫 No invented tool inventories** — do not infer tool order from `ollmfilesd` sandbox/`bash` noise, RPC method names, or `FileDiffPart.apply` counts unless the session or client log names the assistant tool that triggered them. Unverified counts and “many `bash` …” summaries belong in **LLM** or **Debugging**, not **Tool calls**.

**🚫 Not here** — move to **LLM** (investigation context) or **Debugging** (raw evidence):

- Timestamps, log paths, session ids, project paths, build/binary labels, device models.
- “Same as gtktest1”, “felt stuck”, “failure family”, expected-vs-actual essays.
- Root cause, hypotheses, pointers to other bugs, repro checklists, interpretation.
- **Debug log** fences (→ **Debugging**). Session/history JSON path-only pointers can go in **LLM** if not needed to read the repro. Source code (→ **Codebase observed behavior**).

### Codebase observed behavior

Plain bullets: what the tree **actually** does today (files, signatures, control flow). Factual; not “should”.

- Name the file on every bullet — preferably as a markdown link from **`docs/bugs/`** using a repo-relative path, e.g. [`libocrpc/Client.vala`](../../libocrpc/Client.vala), [`ollmfilesd/Daemon.vala`](../../ollmfilesd/Daemon.vala).
- When a few lines make the fact obvious, add a **short** fenced snippet **under** that bullet (not a wall of code). Trim with `…` only when the middle is irrelevant; keep the lines that prove the claim.
- One snippet per bullet when possible; split bullets rather than stacking many blocks.

### Debugging

#### Current debug output

**Evidence-first.** Mostly **fenced excerpts from debug logs** (`ollmchat.debug.log`, `ollmfilesd.debug.log`, `--debug` captures) — not saved chat/session JSON (that verbatim text belongs in **Current behavior** when it is the repro). Not Vala and not bullet essays.

**Pattern (repeat per capture):**

- Parent bullet: **source** — path, run date/time, how it was captured (one short line).
  - Child: fenced excerpt (trim middle with `…` only inside the fence).
  - Optional child: **one-line takeaway** (what the excerpt proves).

**Do not:**

- Paraphrase logs in bullets without a fence.
- Use multi-sentence paragraphs under this heading.
- Put interpretation dumps here — use **LLM** instead.

If nothing captured yet: **`None yet.`** (plain line) — follow-up in **LLM**.

Superseded runs and old hypotheses belong in **LLM**, not here.

#### Debug code added (remove when complete)

List temporary instrumentation: file, what it logs, how to run (e.g. `--debug`). Use fenced snippets if helpful. **Empty** is fine: state that none was added.

### Proposed fix

Required when the fix is more than a couple of lines or needs review. **Trivial one-line fixes** should usually be applied **without** opening a report (see **`docs/bug-fix-process.md`**).

- Concrete **Remove** / **Replace with** / **Add** fences in the section that owns each change (same as plans).
- **Large fixes:** split into ordered **phases** (or **topics**), same pattern as **`docs/guide-to-writing-plans.md`**. Apply in order; do not skip ahead.
- **Phase headings:** prefix when progress is clear — **`### ✔️ Phase 1 — …`** when that phase is **applied** (code in tree); **`### ✅ Phase 1 — …`** when the user **confirmed that phase** on device (green check on the phase is fine). Unapplied: **`### Phase 2 — …`** with no prefix. **Report** **`Status:`** **✅** means the **entire** report is user-done and the file lives in **`docs/bugs/done/`** — not “one phase verified” while the rest is open.
- When **every** phase that matters is **✔️** (or **✅** on phases after partial verify), set report **`Status:`** to **✔️** if the **whole** fix is applied but the user has not signed off the full report yet; keep the file in **`docs/bugs/`**.
- Omit this section only when there is nothing left to approve (already **✔️** applied — set **Status:** **✔️** and note in **LLM**).

### LLM

**Agent scratchpad.** Readers can ignore it. **Default home for anything not needed in **Current behavior** for human review** — if it does not belong under *what you said*, *tool calls*, or a tight *observable outcome*, put it here.

- Repro metadata (when, which project/file, agent, model, log paths, connections).
- Pointers (`docs/…`, Argus paths, related bugs/plans, transcripts).
- Hypotheses, ruled-out ideas, debate, changelog, “Next”, old debug summaries, comparisons to prior bugs.
- Stop-turn history only if useful after **User decisions required** was cleared (do not duplicate live **💩** items here)
- Emoji legend usage (**ℹ️**, **💩**, **🚫**, **✔️**, etc.) **only** in this section unless **🔷** in **User reported**
- Test plans not yet run, implementation ordering notes, cross-links

Do **not** duplicate the full proposed fix in prose here if it already lives under **Proposed fix**.

## Emoji rules (summary)

Canonical definitions: **`docs/guide-to-writing-plans.md`** (**Status and workstream**). For reports:

| Marker | Report **Status:** | Elsewhere in report |
| ------ | ------------------ | ------------------- |
| **⏳** | Open / backlog | **LLM** (pair with **🔷** or **💩** on task bullets) |
| **✔️** | **Applied** (code landed; not user-confirmed) | Phase headings when applied; **LLM** changelog |
| **✅** | **User confirmed done** for the **whole report** (file in **`done/`** only) | Phase headings when user verified that phase; **LLM** sign-off bullets |

| Where | Markers |
| ----- | ------- |
| **User decisions required** | **💩** on each open item; **`None.`** when empty |
| **User reported** | **🔷** only |
| **Success scenario**, **Current behavior**, **Codebase observed behavior**, **Current debug output** (intro lines) | Prefer **no** emoji |
| **LLM** | **ℹ️**, **💩**, **🚫**, **⏳**, **✔️**, **✅**, etc. per plans guide |

**Mandatory:** **✔️** = implemented/applied; **✅** = user verified/approved complete. Never swap them.

## Relation to **`docs/bug-fix-process.md`**

1. **DEBUG first** — update **Debugging** and **LLM**, not product code, until the process allows apply.
2. **Trivial fix** — skip the report or close it quickly; do not maintain a novel for a one-liner.
3. **Apply** — only the approved **Proposed fix**; remove entries from **Debug code added** when merged.
4. **Stop turns** — only per **Agent stop points** above; refresh **User decisions required** (**💩**); chat gets one sentence (**A**–**E** or material decision); no cross-repo edits without **E** + permission; user asks about stops → **carry on**, not stop-compliance commentary.

When this guide and **`docs/bug-fix-process.md`** disagree on **filename** or **section shape**, this guide wins for **new and restructured** reports; legacy files may stay until touched.

## Checklist before **✔️** or **✅**

- [ ] Header is title + **Status** only (**⏳**, **✔️**, or **✅**).
- [ ] **User decisions required** is up to date (**💩** or **`None.`**); refreshed on any stop turn.
- [ ] **User reported** is user words (**🔷**), not analysis.
- [ ] **Success scenario** matches what the user will accept as done.
- [ ] **Current behavior** is **relevant only**: what you said, tool calls (ordered), tight observable outcomes — no essays, comparisons, or repro metadata (**LLM** / **Debugging**).
- [ ] **Current behavior** vs **Codebase observed behavior** are separated (session facts vs what code does).
- [ ] **Codebase observed** bullets link source files; short snippets where they clarify.
- [ ] **Proposed fix** phases marked **✔️** (applied) or **✅** (user confirmed that phase) on headings.
- [ ] **Current debug output** is log excerpts in fences (context line + block), not bullet prose; stale runs in **LLM**.
- [ ] Temporary debug called out in **Debug code added**.
- [ ] Non-trivial fix has **Proposed fix** fences; trivial fix was not over-documented.
- [ ] Filename uses **`ISSUE`** or **`FEATURE`** and today’s date for new files.
- [ ] After apply: **Status** is **✔️** (not **✅**) until the user confirms done.
- [ ] After user verify of the **whole** fix: **Status** is **✅** and file is **moved** to **`docs/bugs/done/`** (never **✅** in the active folder).
- [ ] Prose bullets are not hard-wrapped mid-sentence (see **Markdown formatting (prose)**).
- [ ] **Lists, not paragraphs** — no wall bullets, no `;`-chained facts; **Current debug output** uses fence children, not log narration.