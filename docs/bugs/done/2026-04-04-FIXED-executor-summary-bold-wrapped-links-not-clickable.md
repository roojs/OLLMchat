# Executor Result summary: “links” plain in UI — `**[text]**(url)` not valid markdown

**Status: FIXED**

## Problem

- **Symptom:** Near the end of a skill run, **## Result summary** text listed documents with what looked like markdown links, but in the chat UI they **did not render as clickable links** (no link styling / activation).
- **Source session (local history):** `~/.local/share/ollmchat/history/2026/04/04/15-56-20.json`
- **Message:** `content-stream` entry whose body starts with `## Result summary` and contains “The completed analysis points to three key documents…”.
- **Expected:** Inline markdown links render as `<a>` / GTK link tags like other assistant messages.
- **Actual:** Those spans render as **bold + literal parentheses**, not links.

### Exact model output (representative fragment)

The stored content uses this pattern repeatedly:

```markdown
**[1.23.4‑DONE-task-refinement-prompt.md]**(docs/plans/done/1.23.4-DONE-task-refinement-prompt.md)
```

That is **not** CommonMark link syntax. A valid inline link is `[label](destination)`. For **bold link text**, the usual form is:

```markdown
[**1.23.4‑DONE-task-refinement-prompt.md**](docs/plans/done/1.23.4-DONE-task-refinement-prompt.md)
```

Here the model placed `**` **outside** the `[…](…)` pair in a way that inserts `**` **between** the closing `]` of the notional label and the opening `(` of the URL — i.e. `…md]**(docs/…` — so the parser never sees a contiguous `](` that closes a link.

## Attempts / changelog

1. **Inspected history JSON** — Located message index **175**, `role: content-stream`, containing the Result summary paragraph above.
2. **`oc-markdown-test` repro** — Added `tests/markdown/repro-bold-wrapped-link.md` with:
   - “Broken” line matching the model pattern `**[…]**(…)`
   - Control lines: plain `[label](url)` and bold-inside-brackets `[**label**](url)`
3. **Run:** `build/oc-markdown-test tests/markdown/repro-bold-wrapped-link.md`
   - **Broken line:** Callback trace shows `<strong>` around `[1.23.4…md]` (partial) and the `(docs/plans/…)` part as **plain text** — **no `<a>`**.
   - **Valid line:** `<a href="docs/plans/…">` as expected.

## Conclusions

- **Primary cause (likely):** The **LLM emitted malformed markdown** (`**[title]**(path)` instead of `[**title**](path)` or `[title](path)`). The markdown pipeline (parser + GTK) is behaving consistently with CommonMark-style expectations: **no link token** is produced, so the UI cannot show links.
- **Ruled out (for this specific text):** A separate GTK-only regression like the digit-leading link issue (`docs/bugs/done/2026-04-04-FIXED-markdown-link-digit-lead.md`) — here the parser trace shows **no** `<a>` for the broken pattern.
- **Open:** Whether **nested** `[**label**](url)` is fully styled in all GTK paths (third line in repro showed odd single TEXT blob in trace — worth a follow-up if bold+link is required in product).

## Suggested debugging approach (no code changes yet)

1. **Confirm in UI:** Paste the broken vs valid one-liners into a scratch chat or `oc-test-gtkmd` and confirm GTK matches `oc-markdown-test` (links only on valid line).
2. **Prompt / skill layer:** In **`task_execution.md`** (and similar executor prompts), add an explicit **Don’t**: do **not** wrap links as `**[text]**(url)`; use `[text](url)` or `[**text**](url)` for bold labels.
3. **Optional hardening (only if product must tolerate bad MD):** Post-process or lint executor output — high risk / wrong layer; prefer fixing prompts and model behavior.
4. **Remove or keep** `tests/markdown/repro-bold-wrapped-link.md` — useful for regression if we add prompt-only fixes; delete if we want zero extra files until a fix is approved.

## Record of what was tried

| Step | Result |
|------|--------|
| Read history JSON via Python | Found exact `content-stream` body with `**[…]**(…)` pattern |
| `oc-markdown-test` on repro | Broken pattern → no `<a>`; plain `[…](…)` → `<a>` |

## After a fix (when approved)

- Update this file name with **`FIXED`** when verified; note whether the fix was **prompt-only**, **parser** (unlikely), or **both**.
- If temporary `GLib.debug` was added during investigation, remove it per `docs/bug-fix-process.md`.
