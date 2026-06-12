# Guide to writing plans

Written for **AI agents** — **mandatory** when an agent drafts, reviews, or implements from **`docs/plans/*`**. Human contributors may treat this as a helpful guide.

Plan markdown files live in **`docs/plans/`**; completed work is archived under **`docs/plans/done/`** (see **Done / archive** below). This document is intentionally **not** named `README.md` so it is not mistaken for a generic package readme.

It is the **canonical** place for: plan shape, code-proposal fences, **ordered chunk format** for large methods, **implementation workflow**, and the **checklist for plans**. Coding and build standards live in **`docs/coding-standards.md`** and **`docs/build-rules.md`**.

## Checklist for plans

Copy or reference this section at the top of new plan documents in **`docs/plans/`**. Use it before marking a plan ready to implement.

### Plan structure and code proposals

- **Single canonical code proposal** — no duplicate stitched-together versions (e.g. Part 1…N **and** a separate full-method block that could drift). See **Code proposals section** — *Don't publish duplicate stitched-together versions*.
- **Edit syntax** — actionable fences as **Remove** / **Replace with** / **Add** only; **Keep** is unchanged context, never an edit instruction. See **Edit syntax contract**.
- **No orphan code** — fenced code only under **`## Concrete code proposals`**. See **No orphan or illustrative code**.
- **New methods in plans** — do not add helpers unless the user or plan explicitly asks. See bullets under **Discussion style** below and **Method names and new methods** in **`docs/coding-standards.md`**.

### Verify proposed Vala code

All proposed code must follow **`docs/coding-standards.md`**. Check each item against the linked section:

- **Nullable types** — [Avoiding Nullable Types](coding-standards.md#avoiding-nullable-types)
- **Null checks** — [Defensive code and null checks](coding-standards.md#defensive-code-and-null-checks)
- **String interpolation** — [String Interpolation](coding-standards.md#string-interpolation)
- **Temporary variables** — [Temporary Variables](coding-standards.md#temporary-variables)
- **Brace placement** — [Brace Placement](coding-standards.md#brace-placement)
- **`this.` prefix** — [This Prefix](coding-standards.md#this-prefix)
- **GLib prefix & using statements** — [GLib Namespace Prefix](coding-standards.md#glib-namespace-prefix), [Using Statements](coding-standards.md#using-statements)
- **Property initialization** — [Property Initialization](coding-standards.md#property-initialization)
- **Line length & breaking** — [Line Length and Breaking](coding-standards.md#line-length-and-breaking)
- **StringBuilder usage** — [StringBuilder Usage](coding-standards.md#stringbuilder-usage)
- **String building in loops** — [Building Strings in Loops](coding-standards.md#building-strings-in-loops)
- **ArrayList for strings** — [ArrayList for Strings](coding-standards.md#arraylist-for-strings)
- **Loops and nesting** — [Reducing Nesting](coding-standards.md#reducing-nesting)
- **Character looping** — [Character Looping](coding-standards.md#character-looping)
- **File info try/catch** — [File info and try/catch](coding-standards.md#file-info-and-trycatch)
- **Try/catch scope** — [Try/Catch Scope](coding-standards.md#trycatch-scope)
- **Underscore prefix** — [Underscore prefix on variables and fields](coding-standards.md#underscore-prefix-on-variables-and-fields)
- **get_* methods** — [Property Getters vs Get Methods](coding-standards.md#property-getters-vs-get-methods)
- **Method names (length)** — [Method names and new methods](coding-standards.md#method-names-and-new-methods)
- **New methods** — [Method names and new methods](coding-standards.md#method-names-and-new-methods)
- **Signal handlers in `construct`** — [Signal handlers in construct blocks](coding-standards.md#signal-handlers-in-construct-blocks)
- **Docblocks** — [Docblocks / code documentation](coding-standards.md#docblocks--code-documentation) and **`docs/code-documentation.md`**
- **Debug time & debug-only logic** — [Debug and Warning Statements](coding-standards.md#debug-and-warning-statements)

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

- **Humans** skim **title**, **status**, **`## Purpose`**, and **`## Concrete code proposals`** (when implementing). Long narrative sections are **rarely read** — do not rely on them for requirements.
- **Implementers** need **verbatim hunks** (**Remove** / **Replace with** / **Add** / **Keep**) and file paths.
- **Long prose** is at best **AI/session context**; it is not a substitute for **code blocks** and emoji-prefixed bullets.

## Tone and length

- **Requests + very brief summaries only** (purpose in a short paragraph or bullets).
- Avoid essays, “current behaviour” novels, and duplicated explanations — put the contract in **code blocks** and nested bullets.
- **Strongly prefer nested bullet points** over long prose. If a sentence would run past **one line** in a typical editor width, split it into sub-bullets or tighten the wording — dense paragraphs are hard to skim and easy to miss in review.
- **Do not chain several key points in one paragraph** using **semicolons (`;`)** or **long dashes** (em dash, en dash, or hyphen used as a “second clause” separator). That pattern usually means the content should be **nested bullets** (one idea per bullet, optional sub-bullets under a parent).
- **Prefer short sentences over paragraphs** for narrative bits: one sentence per bullet when possible, not a block of three sentences glued together.

## Discussion style (emoji prefixes)

For **discussion, rationale, risks, and notes** (anything that is not a mechanical **Keep** / **Remove** / **Replace** section), **prefix each paragraph or bullet group with one emoji** from the legend below so readers can scan intent quickly. The **first token** on the line should be the emoji (then a space, then the text).

- **Do not** wrap emoji prefixes or code identifiers in bold — use plain `🔷` / `💩` / `⏳` and single backticks for paths, table/column names, and file paths (e.g. `pressrelease_webview_queue`, not `**pressrelease_webview_queue**`).

**Status and workstream (use liberally for backlog honesty):**

| Marker | Meaning |
| ------ | ------- |
| **✅** | Done and verified in the codebase |
| **⏳** | Not implemented or not matching spec — backlog (use this liberally) |
| **🌗** | Partially done — polish or follow-up still owed |

**Provenance (who said what):**

| Marker | Meaning |
| ------ | ------- |
| **🔷** | **User-specified requirement** — treat as authoritative (use this for anything the user stated as a requirement in chat or in the plan) |
| **💩** | Suggestion **introduced by the LLM** that the **user did not ask for** — optional, confirm before building it in |
| **ℹ️** | Reference or pointer — external doc, spec, ticket, prior plan, or file path worth opening (not a status claim) |
| **🚫** | Rejected for this plan or **do not implement** — out of scope, anti-pattern, or user veto (list these so implementers do not “helpfully” add them) |

**Legacy:** older plans may still use **⚠️** for the same meaning as **🔷** (user-authored requirement). Prefer **🔷** in new and updated plans. Older plans may still use **👎** for the same meaning as **🚫** (rejected / out of scope). Prefer **🚫** in new and updated plans. Older plans may still use **🔶** for the same meaning as **🌗** (partially done). Prefer **🌗** in new and updated plans.

**✅** is **only** for **done and verified in the codebase** (see **Status** table above). **Do not** use **✅** for “user approved” a requirement — use **🔷** for user-specified requirements.

**Combining provenance + backlog:**

- **⏳** means **not done yet** (todo / backlog). It is a **status**, not provenance.
- **🚫 Do not** prefix a todo bullet with **⏳** alone — readers cannot tell whether you or the user asked for the work.
- **Do** pair **⏳** with **🔷** or **💩** on every open work item:
  - One line: **`🔷` `⏳`** … (you asked; not done) or **`💩` `⏳`** … (LLM inferred; not done)
  - Or parent **`🔷`** / **`💩`** with a child bullet **`⏳`** … for the same item
- **ℹ️** / **🚫** bullets are pointers or vetoes — no **⏳** unless there is also an explicit follow-up task; then use **`🔷` `⏳`** or **`💩` `⏳`**.
- Plan **`Status:`** line may use **⏳** alone for overall plan state (meta, not a task bullet).

### 💩 Mark LLM-only content (mandatory in plans)

When drafting or updating a plan from user chat, **separate what they said from what you invented**:

- **🔷** — user stated it, or clearly approved it in the thread (requirements, constraints, names they chose).
- **💩** — **anything you add that the user did not mention** — extra fields, heuristics, save behaviour, CLI guards, helpers, scope expansion, acceptance bullets, “still visible” lists, etc.
- **🚫** — user said **no** or it is explicitly rejected in review (so implementers do not reintroduce it).

**Rules:**

- Do **not** bury **💩** ideas inside **🔷** bullets — give each its **own** **💩** line or table row so review is one glance.
- Before finishing a plan, scan: every requirement is **🔷**, **💩**, **ℹ️**, or **🚫** — nothing unmarked that reads like a mandate.
- **💩** does not mean “wrong” — it means **confirm before build**. User can promote **💩 → 🔷** in review.

**Example:**

- **🔷** Detection uses **`GET /api/version`** via **`Call.Version`**.
- **🚫** URL shape / **`…/api/`** heuristics for detection — not part of this feature.
- **💩** Also hide **`top_k`** in options UI (not mentioned in chat; optional).

---

- **Do not add new methods** unless the plan or the user **explicitly** asks for them (see **`docs/coding-standards.md`** — [Method names and new methods](coding-standards.md#method-names-and-new-methods)).
- **Private helpers are not automatically an improvement** — they are often **bloat**, hide the real flow, and scatter logic. Default to **changing existing methods** and **inlining** at the call site.
- **Readability via extraction is the user’s decision**, not the implementer’s default. Do not introduce helpers “for clarity” unless the user wants that refactor.

## Required shape (match `docs/plans/done/6.6-DONE-*.md` and `docs/plans/done/6.8-DONE-fixing-large-restore.md`)

1. **Title** — `# N.N Title`
2. **`Status:`** — proposed | done | rejected
3. **Pointer** — **`docs/guide-to-writing-plans.md`** **Checklist for plans** (copy bullets or link to that section); proposed Vala code must follow **`docs/coding-standards.md`**
4. **`## Purpose`** — nested bullets for **human planning review**: **🔷** what we are doing, **⏳** backlog, **ℹ️** pointers only — **not** a dump of **🚫** vetoes (see **LLM implementer guardrails** at end of this guide)
5. **Topic sections** — design, schema, tasks, audit lists, etc. (emoji-prefixed bullets; **no** boilerplate sections below)
6. **`## Concrete code proposals`** (or **`## Proposed code changes`**) — **main deliverable** when implementing (can say **⏳** deferred during planning-only passes)

Optional, keep short:

- **`## Current behaviour`** — bullets only
- **`## Proposed behaviour`** — bullets only

## Sections to avoid in plans

**🚫 Do not add these** — they duplicate **Purpose** and are rarely maintained:

- **`## Scope`** / “In scope | Out of scope” — duplicates **Purpose**; omit
- **🚫** bullets in **`## Purpose`** or topic sections — vetoes belong in **LLM implementer guardrails** (this guide), parent plan phase boundaries, or optional **`## LLM notes`** at plan bottom — not mixed into what the human is reviewing
- **`## Acceptance criteria`** — use **⏳** bullets in **Purpose** or **Phase N tasks** instead
- **Markdown tables** in plan bodies — **strongly avoid**; they are hard to read in review. Use **nested bullets** instead (emoji legend tables in *this guide* are fine)

**🚫** Do not abbreviate names for speech-to-text (e.g. `snapshot_q`) — use the real identifier with the correct **table prefix** (e.g. **`pressrelease_snapshot_queue`**, not bare `snapshot_queue`).

## Database table names (Media Outreach / Pman)

When a plan adds tables or columns in **`web.MediaOutreach`**:

- **🔷** New tables use the **module prefix** on the table name: **`pressrelease_*`**, **`shop_*`**, etc. (see existing SQL under **`Pman/<Module>/sql/`**).
- **ℹ️** **`clipping_*`** / **`Pman/Clipping/`** = **legacy**, kept for **backward compatibility** — **do not** add new greenfield tables there unless the plan explicitly extends BC surfaces (e.g. a column on **`clipping_domain`**).
- **🔷** **Press-release webview / queue work** (browser workers, Chrome/extension workers) → `pressrelease_*` tables under `Pman/PressRelease/sql/` (e.g. `pressrelease_webview_queue`, `pressrelease_webview_queue_archive`).
- **🚫** T8237 / `pressrelease_snaphost` / `wip_leon_T8237_Screenshot_Workers` — not being implemented; dead branch. Do not plan on it; replace with webview queue work. May borrow minor ideas only.
- **ℹ️** Legacy PascalCase clipping tables (**`Clipping`**, **`ClippingTree`**) stay as-is — do not rename for “consistency”.
- **ℹ️** FK columns are usually **`<related_table>_id`** (e.g. **`clipping_id`**, **`clipping_domain_id`** on queue rows).
- **ℹ️** BC column on **`clipping_domain`** for **snapshot policy** — e.g. **`use_snapshot_queue`** (`0` = inline webkit; **`> 0`** = enqueue **`work_type = screenshot`** on **`pressrelease_webview_queue`**). Domain flag names **snapshotting**; queue table names stay **generic** (html, spider, …).

## Code proposals section (mandatory pattern)

Intro line: hunks are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

### Edit syntax contract (strict)

- **Action syntax is only:** **`Remove`**, **`Replace with`**, and **`Add`**.
- **`Keep` means unchanged context only**. It is never an edit operation.
- If a plan can be applied without `Keep` fences, prefer that simpler form.
- When needed, describe unchanged context in **Where** text rather than adding a
  `Keep` code block.

### Do / don’t (remove / replace / add)

- **Don’t publish duplicate stitched-together versions** of the same unit of work. A plan must **not** leave implementers choosing between (a) a long chain of **Keep** / **Remove** / **Replace** parts and (b) a second, parallel “full method” or “full file” paste that could **drift** from the parts—nor require **mental assembly** of unstated lines between fences. Pick **one** canonical form:
  - **Small change:** parts + anchors are fine if every **removed** line appears in a **Remove** fence and every **new** line appears in **Replace with** / **Add**, with **Keep** only as **local** anchors (already in this guide); or
  - **Large replacement:** one **Remove** of the old region (method, ctor, or whole file) and one **Replace with** containing the **complete** new text—no separate “Part 1 … Part 7” that duplicates the same outcome.
- **Do** put the contract in **fenced code blocks** under **Remove** /
  **Replace with** / **Add**. The implementer applies **verbatim hunks**, not a
  paraphrase.
- **Don’t** replace code blocks with long prose about what to keep or replace (“delete the old loop and insert …”) **without** the matching fences.
- **Do** use **`#### Add`** (or an **Add** chunk in the ordered format) for **pure insertions** — new lines only, nothing deleted.
- **Don’t** use **`Remove`** with `// (nothing)` or “nothing to remove” to mean
  insertion. If there is nothing to delete, there is **no Remove** — use
  **Add**.
- **Don’t** publish a **`#### Add`** (or ordered-chunk **Add**) that is
  **only** a code fence. The implementer must get **mechanical context**
  without guessing: every **Add** must state **where** the new lines go (file,
  method or region, and position relative to a named line) and **what** they do
  (one short sentence). Put that in the **`#### Add — …`** heading suffix
  and/or **immediately below** **`#### Add`** as a line or bullets **before**
  the fence. A pointer (**see § X**) is allowed **only if** the referenced
  section contains the **same** verbatim fence and the same placement
  sentence—otherwise the **Add** block is incomplete.
- **Do** keep that **placement + purpose** line on **Replace with** / **Add** (ordered chunks use it on the line immediately above the fence—see below); keep it short — the **fence** carries the literals.

### No orphan or illustrative code (outside **Concrete code proposals**)

Plans are **edit specs**, not codebase tours. If a reader cannot apply a fence mechanically, the plan is wrong.

- **Don’t** put **fenced code** anywhere except under **`## Concrete code proposals`** — not in Purpose, Precedent, Notes, or Related.
- **Don’t** paste “pattern” or “precedent” excerpts from other files (e.g. two
  lines from `Pressrelease_entry.php`) unless that excerpt is itself the
  **exact** hunk to apply, labelled **Remove** / **Replace with** / **Add**.
- **Don’t** use investigation-style citations (`startLine:endLine:path` blocks, random mid-file snippets) in implementation plans. **ℹ️** Point at `path/to/file.php` and commit hash; the implementer opens the file.
- **Don’t** split one logical edit across multiple `###` sections if that
  forces the reader to merge hunks mentally (e.g. “Part A adds `else`” + “Part
  B replaces `if` body”). Use **one** **Remove** + **Replace with** for the
  whole region, or **ordered chunks** inside a **single** `###`.
- **Do** label every `###` with: **file path**, **function/method/region name**, and **one-line intent** (e.g. `### 1. \`Foo.php\` — \`get()\` foreach: FTP XML import + Events log`).
- **Do** make every edit locatable: include the **enclosing** `function` /
  `foreach` / `if` line in the `###` title and state exact position in
  **Where** text.
- **Investigation / query docs** (`*-query.md`, `docs/bugs/*`) may quote existing code to explain behaviour. **Implementation plans** (`docs/plans/*.md` except query docs) must not — link to the investigation instead.
- **Don’t** use the **next** `function` below your edit as a locator (e.g. putting `function getContent` inside **Remove**/**Replace with** when only `return true` changes). The next method is not being edited — it confuses *where* vs *what*.
- **Don’t** use disconnected context snippets for one small change. Use one
  tight **Remove** + **Replace with** pair and a precise **Where** line.
- **Do** under each `###`, before the fences, state **Why** (dependency / outcome), **Where** (function + position in plain English), and **Depends on** (other `###` in this plan, if any). The hunks alone are not enough.
- **Don’t** use `…`, `// ...`, or “rest unchanged” inside **Keep** / **Remove** / **Replace with** fences. Every line in a fence must be **verbatim** from the tree (or the exact new lines to apply). If the anchor is long, include the real lines — do not abbreviate.

**Bad (do not write plans like this):**

~~~markdown
### 2. `Pman/PressRelease/Import/EQSRelease.php` — `addRelease()` success return

#### Keep
```php
    function addRelease($data, $force = false) 
    {
```

#### Keep
```php
        $this->log('DONE', …);
```

#### Remove
```php
        return true;
    }

    function getContent($html)
```
~~~

Problems: signature **Keep** is far from the edit; `…` is not real code; **Remove** includes the **next** function; no **Why** / **Where** / **Depends on**.

**Good (real one-line change — same file, same edit):**

~~~markdown
### 2. `Pman/PressRelease/Import/EQSRelease.php` — `addRelease()`: return inserted row

**Why:** §1 assigns `$pe = $this->addRelease($data)` and logs `$pe->id` in `writeEventLog`. Returning `true` forces a second DB lookup.

**Where:** `addRelease()`, last statement before `function getContent`.

**Depends on:** §1 (`get()` loop).

#### Keep
```php
        $pe = DB_DataObject::factory('pressrelease_entry');
        $pe->setFrom($add);
        $pe->insert();
        if (!empty($data['companyLogo'])) {
            $this->addClientLogo($pe->id, $data['companyLogo']);
        }

        $this->log('DONE', 'Release Id "' . $pe->id . '"');

```

#### Remove
```php
        return true;
```

#### Replace with
```php
        return $pe;
```
~~~

Reader can open `addRelease()`, find `log('DONE'`, and apply without guessing.

For **each** file/topic, use a **numbered** `###` heading, then **only** these subheadings above code:

| Subheading | Use |
| ---------- | --- |
| **`#### Remove`** | Verbatim code to delete |
| **`#### Replace with`** | Full replacement of the **Remove** block (or the named fragment) — not necessarily the whole file |
| **`#### Add`** | New code only (no removal). Must include **where** + **what** (heading suffix or line above fence)—see **Don’t** “only a code fence” in **Do / don’t**. |

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

When changing a **method that already exists**, **split it into parts** — one
logical edit per subsection (e.g. **`##### Part 1 — Signature`**,
**`##### Part 2 — …`**). For **each** part:

- **`#### Remove`** / **`#### Replace with`** / **`#### Add`** — The **small**
  verbatim fragments for **that part only**.

Apply parts **in order** (Part 1, then 2, …). Each part must be mechanically
applicable from **Remove/Replace with/Add** plus the section's **Where** text.

- **Whole-method / whole-file `Replace with`:** Prefer this when the change is **large** or when **parts** would force unstated glue between fences—see **Don’t publish duplicate stitched-together versions** above. One **Remove** + one complete **Replace with** is **not** inferior to seven parts if the parts would duplicate the same outcome or omit lines.
- **Why use parts at all?** Small, localized diffs preserve a clear review story—but only when each part is **mechanically complete** and **not** mirrored by a second full copy elsewhere in the plan.
- **Empty default bodies** (e.g. a virtual hook): short **Goal** text; **Remove**/**Replace with** for the old vs new **fragment** (e.g. signature + comment), not a lone **Replace with** with no **Remove**.
- **When every line of the method changes** or the method is **new:** a single full-method **`Replace with`** (with **`Remove`** of the old method) is OK; say so in prose.

**Very short** methods (a few lines) may use one small **Remove** /
**Replace with** pair without splitting into parts.

### Ordered chunk format for large methods

Use this when a **single** fenced block would be ambiguous—typically **large or heavily edited methods**, or any region where the reader must apply edits **in sequence** through the body.

**Small, one-off edits** can stay a **single** fenced `vala` block with enough surrounding context.

#### Cycle (repeat top → bottom until the method or region is done)

Interleave in this order:

1. **Keep** — Fenced block of **unchanged** code (enough lines to anchor the next edit—usually starts or ends a stable span).
2. Then either:
   - **Remove** + **Replace with** — **Remove** is only for **verbatim lines to delete**. **Replace with** — *one-line reason*, then a fence of **new** code that replaces what was removed; or
   - **Add** — *reason* naming **where** + **what** (placement relative to the prior **Keep** and purpose—may be one line or two short lines), then a fence of **new** code only — use this for **pure insertions** (do **not** pair with an empty **Remove**). A fence **without** that reason is incomplete (**Do / don’t**).

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

**`docs/plans/done/7.14.1.3-DONE-details-vala.md`** — **Files** section: **`Details.refine`**, **`run_exec`**, **`extract_exec`**, and **`####` … `— ordered chunks`** subsections (uses **Add** for pure insertions per **Do / don’t** above).

### Implementable code belongs in fences

- Anything the implementer must apply must appear as verbatim code under **`#### Remove`**, **`#### Replace with`**, **`#### Add`**, or **`#### Keep`** — **not** only in narrative bullets (“add a case for X”, “move the call after the catch”) without a matching fence.
- Quoted notes, tickets, or user paste-ins: use **`#### Keep (verbatim)`** (or similar) above each fence so the mandatory **`####` + fence** rule still holds.

### Plans and defensive code

Follow **`docs/coding-standards.md`** — [Defensive code and null checks](coding-standards.md#defensive-code-and-null-checks): do not specify speculative guards, redundant validation, or “just in case” API surface (e.g. extra **`deserialize_property`** branches) unless there is a **real boundary** or **external contract**. Prefer the smallest change that matches the actual call paths.

## Done / archive

When implemented: move or copy to **`docs/plans/done/`**, prefix filename with **`DONE`** or **`REJECTED`**, one-line **Status: DONE** and pointer to files changed.

### Sub-plans and `1.0-summary.md`

- **Do not** add or edit entries in **`docs/plans/1.0-summary.md`** for in-progress sub-plans.
- Put a **prominent blockquote at the top** of each sub-plan stating that 1.0 is **not** updated until the sub-plan is **done** and archived.
- Update 1.0 **only** when closing a plan (optional — user may skip even then).

## Related

- **`docs/coding-standards.md`** — Vala/style rules for proposed and implemented code
- **`docs/build-rules.md`** — Meson/Ninja build workflow
- **`docs/bug-fix-process.md`** — bug fix flow (contrast with **Plan implementation workflow** above)
- **`docs/plans/done/6.9-DONE-debugging-performance.md`** — nested thinking / history replay perf (see **`docs/plans/done/6.8-DONE-fixing-large-restore.md`** for parser work)

## LLM implementer guardrails (not for human planning review)

**🚫 Do not** fill **`## Purpose`** (or design sections) with **out-of-scope**, **“do not implement”**, or **“that’s Phase N”** bullets. Humans use the plan to review **what we are building**; a wall of **🚫** is noise and reads like the author stalling itself.

**Where guardrails live instead:**

- **This guide** — workflow, sections to avoid, DB prefixes, don’t expand scope.
- **Parent / overview plan** — phase boundaries in **Phase summary** (short), not repeated in every sub-plan.
- **Sub-plans** — **🔷** + **⏳** + **ℹ️** only in **Purpose**; trust the parent for “Phase 2 is elsewhere”.
- **Optional** — if a plan truly needs agent-only reminders, add **`## LLM notes`** as the **last** section (after **Concrete code proposals**). Keep it short. **Do not** duplicate the same **🚫** list in **Purpose**.

**When implementing:** follow **Plan implementation workflow** above; if tempted to add a feature outside **🔷** bullets, **stop and ask** — do not “document” every temptation as **🚫** in the plan file.
