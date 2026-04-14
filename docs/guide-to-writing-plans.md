# Guide to writing plans

Plan markdown files live in **`docs/plans/`**; completed work is archived under **`docs/plans/done/`** (see **Done / archive** below). This document is intentionally **not** named `README.md` so it is not mistaken for a generic package readme.

It is the **canonical** place for: plan shape, code-proposal fences, **ordered chunk format** for large methods, and **implementation workflow** (what implementers and agents must follow). Keep this material here—do not maintain a parallel copy under **`.cursor/rules/`**.

## Plan implementation workflow

Applies when implementing **feature or refactor work** from **`docs/plans/*`**, tickets, or explicit user instructions.

1. **Implement only what was approved** (the written plan or agreed scope). Do not expand scope silently.

2. **If something blocks you** (build errors, missing fields, wrong API split, design hole):
   - **Revert** speculative or partial code rather than piling on workarounds.
   - **Update the plan** (or the relevant doc): what failed, what must change, options if any.
   - **Stop and ask for explicit user approval** before continuing implementation.

3. **No surprise fixes**: do not add drive-by refactors, unrelated cleanups, or “compile-only” API changes unless the user approved that change in the plan or in chat.

4. **Exception**: trivial edits the user asked for in the same message (typos, formatting) are fine—still avoid unrelated code changes.

**Bug fixes** follow **`docs/bug-fix-process.md`** (debug → understand → propose → approval → apply). This workflow adds the **revert + plan update + approval** loop when **planned implementation** hits design gaps.

## Audience

- **Humans** skim **title, status, scope, acceptance criteria**, and **`## Concrete code proposals`** (or equivalent). Long narrative sections are **rarely read** — do not rely on them for requirements.
- **Implementers** need **verbatim hunks** (**Remove** / **Replace with** / **Add** / **Keep**) and file paths.
- **Long prose** is at best **AI/session context**; it is not a substitute for checklist items and code blocks.

## Tone and length

- **Requests + very brief summaries only** (purpose in a short paragraph or bullets).
- Avoid essays, “current behaviour” novels, and duplicated explanations — put the contract in **code blocks** and tables.
- **Strongly prefer nested bullet points** over long prose. If a sentence would run past **one line** in a typical editor width, split it into sub-bullets or tighten the wording — dense paragraphs are hard to skim and easy to miss in review.
- **Do not chain several key points in one paragraph** using **semicolons (`;`)** or **long dashes** (em dash, en dash, or hyphen used as a “second clause” separator). That pattern usually means the content should be **nested bullets** (one idea per bullet, optional sub-bullets under a parent).
- **Prefer short sentences over paragraphs** for narrative bits: one sentence per bullet when possible, not a block of three sentences glued together.

## Discussion style (emoji prefixes)

For **discussion, rationale, risks, and notes** (anything that is not a mechanical **Keep** / **Remove** / **Replace** section), **prefix each paragraph or bullet group with one emoji** from the legend below so readers can scan intent quickly. The **first token** on the line should be the emoji (then a space, then the text).

**Status and workstream (use liberally for backlog honesty):**

| Marker | Meaning |
| ------ | ------- |
| **✅** | Done and verified in the codebase |
| **⏳** | Not implemented or not matching spec — backlog (use this liberally) |
| **🔶** | Partially done — polish or follow-up still owed |

**Provenance (who said what):**

| Marker | Meaning |
| ------ | ------- |
| **⚠️** | Specific requirement or constraint **the user added** — treat as authoritative |
| **💩** | Suggestion **introduced by the LLM** that the **user did not ask for** — optional, confirm before building it in |
| **ℹ️** | Reference or pointer — external doc, spec, ticket, prior plan, or file path worth opening (not a status claim) |

You can combine a **status** emoji with a short sub-bullet under **⚠️** / **💩** / **ℹ️** when both apply (e.g. **⚠️** parent with **⏳** child for a user-requested item still open).

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

### Do / don’t (keep / remove / replace / add)

- **Don’t publish duplicate stitched-together versions** of the same unit of work. A plan must **not** leave implementers choosing between (a) a long chain of **Keep** / **Remove** / **Replace** parts and (b) a second, parallel “full method” or “full file” paste that could **drift** from the parts—nor require **mental assembly** of unstated lines between fences. Pick **one** canonical form:
  - **Small change:** parts + anchors are fine if every **removed** line appears in a **Remove** fence and every **new** line appears in **Replace with** / **Add**, with **Keep** only as **local** anchors (already in this guide); or
  - **Large replacement:** one **Remove** of the old region (method, ctor, or whole file) and one **Replace with** containing the **complete** new text—no separate “Part 1 … Part 7” that duplicates the same outcome.
- **Do** put the contract in **fenced code blocks** under **Keep** / **Remove** / **Replace with** / **Add**. The implementer applies **verbatim hunks**, not a paraphrase.
- **Don’t** replace code blocks with long prose about what to keep or replace (“delete the old loop and insert …”) **without** the matching fences.
- **Do** use **`#### Add`** (or an **Add** chunk in the ordered format) for **pure insertions** — new lines only, nothing deleted.
- **Don’t** use **`Remove`** with `// (nothing)` or “nothing to remove” to mean insertion. If there is nothing to delete, there is **no Remove** — use **Add** (after a **Keep** anchor when you need one).
- **Do** keep a **one-line reason** on **Replace with** / **Add** where the format calls for it (ordered chunks); keep it short — the **fence** carries the real content.

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

- **Whole-method / whole-file `Replace with`:** Prefer this when the change is **large** or when **parts** would force unstated glue between fences—see **Don’t publish duplicate stitched-together versions** above. One **Remove** + one complete **Replace with** is **not** inferior to seven parts if the parts would duplicate the same outcome or omit lines.
- **Why use parts at all?** Small, localized diffs preserve a clear review story—but only when each part is **mechanically complete** and **not** mirrored by a second full copy elsewhere in the plan.
- **Empty default bodies** (e.g. a virtual hook): short **Goal** text; **Remove**/**Replace with** for the old vs new **fragment** (e.g. signature + comment), not a lone **Replace with** with no **Remove**.
- **When every line of the method changes** or the method is **new:** a single full-method **`Replace with`** (with **`Remove`** of the old method) is OK; say so in prose.

**Very short** methods (a few lines) may use a single **Keep** spanning the whole method if it stays readable.

### Ordered chunk format for large methods

Use this when a **single** fenced block would be ambiguous—typically **large or heavily edited methods**, or any region where the reader must apply edits **in sequence** through the body.

**Small, one-off edits** can stay a **single** fenced `vala` block with enough surrounding context.

#### Cycle (repeat top → bottom until the method or region is done)

Interleave in this order:

1. **Keep** — Fenced block of **unchanged** code (enough lines to anchor the next edit—usually starts or ends a stable span).
2. Then either:
   - **Remove** + **Replace with** — **Remove** is only for **verbatim lines to delete**. **Replace with** — *one-line reason*, then a fence of **new** code that replaces what was removed; or
   - **Add** — *one-line reason* (e.g. **Add** — insert local state before the rest of the method), then a fence of **new** code only — use this for **pure insertions** (do **not** pair with an empty **Remove**).

Then **Keep** again and repeat as needed.

The **reason** sits on the **Replace with** or **Add** line **immediately above** that block’s code fence. Example: **Replace with** — Set status to REFINEMENT while refinement runs.

#### Rules

- Each **Keep**, **Remove**, **Replace with**, and **Add** that carries code gets its **own** fenced block.
- Do **not** merge several logical edits into one **Replace with** / **Add** unless they are inseparable.
- **Keep** blocks must match the **current** source so a reader can verify line-for-line before editing.

You may label each block with plain **Keep** / **Remove** / **Replace with** / **Add** (as in many plans) or with the same headings as elsewhere in this guide (**`#### Keep`**, etc.)—same meaning.

#### Example (one cycle — insertion after anchor)

**Keep**

```vala
	void foo() {
```

**Add** — Initialize state required for the following logic.

```vala
		this.bar = 1;
```

**Keep**

```vala
	}
```

#### Reference plan (long worked example)

**`docs/plans/7.14.1.3-details-vala.md`** — **Files** section: **`Details.refine`**, **`run_exec`**, **`extract_exec`**, and **`####` … `— ordered chunks`** subsections (uses **Add** for pure insertions per **Do / don’t** above).

### Implementable code belongs in fences

- Anything the implementer must apply must appear as verbatim code under **`#### Remove`**, **`#### Replace with`**, **`#### Add`**, or **`#### Keep`** — **not** only in narrative bullets (“add a case for X”, “move the call after the catch”) without a matching fence.
- Quoted notes, tickets, or user paste-ins: use **`#### Keep (verbatim)`** (or similar) above each fence so the mandatory **`####` + fence** rule still holds.

### Plans and defensive code

Follow **`.cursor/rules/CODING_STANDARDS.md`** — *Defensive code* and *Checklist for all plans*: do not specify speculative guards, redundant validation, or “just in case” API surface (e.g. extra **`deserialize_property`** branches) unless there is a **real boundary** or **external contract**. Prefer the smallest change that matches the actual call paths.

## Done / archive

When implemented: move or copy to **`docs/plans/done/`**, prefix filename with **`DONE`** or **`REJECTED`**, one-line **Status: DONE** and pointer to files changed.

## Related

- **`.cursor/rules/CODING_STANDARDS.md`** — checklist for plans + Vala/style rules (also links here for plan layout)
- **`docs/bug-fix-process.md`** — bug fix flow (contrast with **Plan implementation workflow** above)
- **`docs/plans/done/6.9-DONE-debugging-performance.md`** — nested thinking / history replay perf (see **`docs/plans/done/6.8-DONE-fixing-large-restore.md`** for parser work)
