# Guide to writing plans

Plan markdown files live in **`docs/plans/`**; completed work is archived under **`docs/plans/done/`** (see **Done / archive** below). This document is intentionally **not** named `README.md` so it is not mistaken for a generic package readme.

## Audience

- **Humans** skim **title, status, scope, acceptance criteria**, and **`## Concrete code proposals`** (or equivalent). Long narrative sections are **rarely read** — do not rely on them for requirements.
- **Implementers** need **verbatim hunks** (**Remove** / **Replace with** / **Add** / **Keep**) and file paths.
- **Long prose** is at best **AI/session context**; it is not a substitute for checklist items and code blocks.

## Tone and length

- **Requests + very brief summaries only** (purpose in a short paragraph or bullets).
- Avoid essays, “current behaviour” novels, and duplicated explanations — put the contract in **code blocks** and tables.

## New methods and helpers

- **Do not add new methods** unless the plan or the user **explicitly** asks for them (see **CODING_STANDARDS.md** — new methods).
- **Private helpers are not automatically an improvement** — they are often **bloat**, hide the real flow, and scatter logic. Default to **changing existing methods** and **inlining** at the call site.
- **Readability via extraction is the user’s decision**, not the implementer’s default. Do not introduce helpers “for clarity” unless the user wants that refactor.

## Required shape (match `docs/plans/done/6.6-DONE-*.md` and `docs/plans/done/6.8-DONE-fixing-large-restore.md`)

1. **Title** — `# N.N Title`
2. **`Status:`** — proposed | done | rejected
3. **Pointer** — `.cursor/rules/CODING_STANDARDS.md` **Checklist for all plans** (copy bullets or link to that section)
4. **`## Purpose`** — 1 short paragraph or bullets (what problem, what outcome)
5. **`## Scope`** — table: In scope | Out of scope
6. **`## Acceptance criteria`** — bullets, testable
7. **`## Concrete code proposals`** (or **`## Proposed code changes`**) — **main deliverable**

Optional, keep short:

- **`## Current behaviour`** — bullets only
- **`## Proposed behaviour`** — bullets only

## Code proposals section (mandatory pattern)

Intro line: hunks are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

For **each** file/topic, use a **numbered** `###` heading, then **only** these subheadings above code:

| Subheading | Use |
| ---------- | --- |
| **`#### Remove`** | Verbatim code to delete |
| **`#### Replace with`** | Full replacement of the **Remove** block (or the named fragment) — not necessarily the whole file |
| **`#### Add`** | New code only (no removal) |
| **`#### Keep`** | **Local** unchanged lines that **anchor** the next **Remove** / **Replace with** / **Add** — e.g. the lines **immediately above** the fragment you are about to change. Break big methods into **parts** (see below); **do not** paste the **entire** method in one **`Keep`** fence (hard to scan). **`Remove`** / **`Replace with`** carry the **small** verbatim delta. |

**Example** (outer fence is `~~~` so inner fences parse):

~~~markdown
### 1. `lib/foo/Bar.vala` — frob the widget

#### Remove

```vala
		old_call();
```

#### Replace with

```vala
		new_call();
```
~~~

One **`####` heading immediately above each fenced block.** No code fence without a **`####`** label.

### Editing existing methods (strong preference)

When changing a **method that already exists**, **split it into parts** — one logical edit per subsection (e.g. **`##### Part 1 — Signature`**, **`##### Part 2 — …`**). For **each** part:

- **`#### Keep`** — Only the **unchanged lines immediately above** (or beside) the edit, so the reader knows **where** in the method this hunk applies. **Not** the full method in one fence (that becomes unreadable).
- **`#### Remove`** / **`#### Replace with`** / **`#### Add`** — The **small** verbatim fragments for **that part only**.

Apply parts **in order** (Part 1, then 2, …). **`Remove`** / **`Replace with`** must be enough to apply mechanically; **`Keep`** is the anchor, not a duplicate of the whole function.

- **Why not one big `Replace with` for the whole method?** It hides the real delta. **Parts** + **small** remove/replace preserve a clear diff.
- **Empty default bodies** (e.g. a virtual hook): short **Goal** text; **Remove**/**Replace with** for the old vs new **fragment** (e.g. signature + comment), not a lone **Replace with** with no **Remove**.
- **When every line of the method changes** or the method is **new:** a single full-method **`Replace with`** (with **`Remove`** of the old method) is OK; say so in prose.

**Very short** methods (a few lines) may use a single **Keep** spanning the whole method if it stays readable.

### Implementable code belongs in fences

- Anything the implementer must apply must appear as verbatim code under **`#### Remove`**, **`#### Replace with`**, **`#### Add`**, or **`#### Keep`** — **not** only in narrative bullets (“add a case for X”, “move the call after the catch”) without a matching fence.
- Quoted notes, tickets, or user paste-ins: use **`#### Keep (verbatim)`** (or similar) above each fence so the mandatory **`####` + fence** rule still holds.

### Plans and defensive code

Follow **`.cursor/rules/CODING_STANDARDS.md`** — *Defensive code* and *Checklist for all plans*: do not specify speculative guards, redundant validation, or “just in case” API surface (e.g. extra **`deserialize_property`** branches) unless there is a **real boundary** or **external contract**. Prefer the smallest change that matches the actual call paths.

## Done / archive

When implemented: move or copy to **`docs/plans/done/`**, prefix filename with **`DONE`** or **`REJECTED`**, one-line **Status: DONE** and pointer to files changed.

## Related

- **`.cursor/rules/CODING_STANDARDS.md`** — checklist for plans + Vala/style rules
- **`.cursor/rules/plan-implementation-workflow.mdc`** — implement only approved scope; update plan on blockers
- **`docs/plans/done/6.9-DONE-debugging-performance.md`** — nested thinking / history replay perf (see **`docs/plans/done/6.8-DONE-fixing-large-restore.md`** for parser work)
