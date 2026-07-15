# Coding standards router

**AI agents:** Before editing Vala, work through this checklist. Collect every
section slug marked **yes**, union with **universal**, then read each matching
block in **`docs/coding-standards.md`** in full (grep `section: <slug>`). Do **not**
read the whole file unless every section below is in your set (rare). Do **not**
implement until required reads are done. **Top mistakes: helper methods, gratuitous line-length chopping**
(`ensure_*`, “extract for clarity”, DRY) — **inline** in the method you are
already editing unless user or plan names the helper (`method-names-new-methods`).
Short `if` / `||` lines stay on one line unless genuinely long (`line-length-breaking`).
Keep format-string calls (`throw` / error-ctor / `GLib.debug` / `warning` /
`critical`) with the **message on the same line as the call**. If too long, wrap
**remaining args grouped** — not one argument per line.

Do **not** read the whole coding-standards file unless every section below is
in your set (rare). Do **not** implement until required reads are done.

**How to read a section:** Grep `section: <slug>` in `docs/coding-standards.md`,
note the line number, then use the Read tool from that line through the line
before the next `##` heading (read the entire block, not a summary).

---

## Universal (every Vala edit)

Any Vala change will touch these patterns. **Read** each section below before
your first edit. **Re-scan your diff** against the same questions before you
say the task is done.

| Did your change (or will it)…? | Read section | Before done — STOP if you… |
|--------------------------------|--------------|----------------------------|
| Declare a **local** or **loop** variable (`for` / `foreach`)? | `temporary-variables` | Used `string x =`, `int n =`, `bool b =`, etc. on a local (only `string[] = {}` allowed) |
| Access an instance field, property, or method? | `this-prefix` | Left off `this.` on instance members inside methods |
| Add or change **`if`** / **`else`** / nested branches? | `reducing-nesting` | Added gratuitous `else` instead of early return or separate `if (!cond)` |
| Compare **enum** or **permission response** values (`if (x == A \|\| x == B)`)? | `switch-case` | Used `\|\|` / `else if` chains instead of `switch` for discrete values |
| Add a **null check**, empty guard, or “just in case” validation? | `defensive-code-null-checks` | Duplicated checks already enforced upstream (UI, permission, caller) |
| Tempted to add a **helper method** (`ensure_*`, extract “for clarity”)? | `method-names-new-methods` | Added a helper the user or plan did not name — **inline instead** |
| Add a **new named constant** (`const`)? | `method-names-new-methods` | New `const` without user/plan approval — use literal at use site |
| Add or change **`if`** with `\|\|` / `&&` on a **short** line? | `line-length-breaking` | Split a line that fits on one line in the surrounding file |
| Add or change **`throw`** / error ctor / `GLib.debug`/`warning`/`critical` with a format message? | `line-length-breaking` | Broke so the format/literal sits alone after `(`; or one-arg-per-line wrap for that call |
| Finish the task? | `agent-compliance-gate` | Skipped the verification table or the `rg` local-type search |

**Temporary variables (most common miss):** if you wrote any local declaration,
grep your diff for `string `, `int `, `bool ` at line start inside methods.
Re-read `temporary-variables` and fix before done.

---

## Scenario checklist

Answer each question for your task. **Yes** → add the section slug(s).

| Does your task…? | Read section slug(s) |
|------------------|----------------------|
| Add or change docblocks, `@param`, or API comments? | `docblocks` — also read **`docs/code-documentation.md`** in full |
| Build error messages, UI labels, or concatenate strings (not `@"""` tool help)? | `string-interpolation`, `null-coalescing`, `line-length-breaking` |
| Use `??` or default a nullable expression? | `null-coalescing` |
| Add new classes, methods, or namespaces? | `brace-placement` |
| Add or rename fields, properties, or constructor defaults? | `underscore-prefix`, `property-initialization`, `gobject-construct-blocks` |
| Use `GLib.Path`, `GLib.File`, `GLib.Environment`, or other GLib types? | `glib-namespace-prefix` |
| Call `query_info`, `query_exists`, or other file metadata? | `file-info-try-catch` |
| Add or change `try` / `catch` blocks? | `try-catch-scope` |
| Add or change GObject / `Json.Serializable` properties? | `property-initialization`, `serializable-classes` |
| Use nullable types (`Type?`) or `if (x == null)`? | `avoiding-nullable-types`, `defensive-code-null-checks` |
| Add `GLib.debug`, `GLib.warning`, or change logging? | `debug-warning-statements` |
| Use `Gee.HashMap` with `[]` accessors? | `gee-hashmap-access` |
| Use `Gee.ArrayList` (non-string element type)? | `gee-arraylist-access` |
| Embed SQL in Vala source? | `sql-table-aliases` |
| Build strings inside a `for` / `while` / `foreach` loop? | `building-strings-in-loops` |
| Loop over string characters or index `str[i]`? | `character-looping` |
| Slice string arrays or join lines with `string.joinv`? | `string-array-operations`, `arraylist-for-strings` |
| Use `GLib.StringBuilder`? | `stringbuilder-usage` |
| Grow `string[]` with `+=` or join string lists? | `arraylist-for-strings` |
| Connect signals in a `construct` block? | `signal-handlers-construct` |
| Connect GTK button/menu/widget signals (e.g. `clicked`)? | `signal-handlers-construct` |
| Add or rename `get_*` methods? | `property-getters-vs-get-methods` |
| Edit GTK / Adwaita UI (widgets, dialogs, permissions)? | `signal-handlers-construct`, `property-initialization`, `reducing-nesting`, `switch-case` |
| Run subprocesses, async I/O, or permission flows? | `try-catch-scope`, `file-info-try-catch`, `defensive-code-null-checks` |
| Add `using` namespace imports? | `using-statements` |
| Write long lines (calls, concatenation, docblocks)? | `line-length-breaking` |

---

## Section index (line hints)

Line numbers drift when the canonical file edits; **grep `section: <slug>`**
is authoritative. Hints below are for humans only.

| Slug | ~line |
|------|-------|
| `docblocks` | 13 |
| `string-interpolation` | 52 |
| `null-coalescing` | 84 |
| `temporary-variables` | 110 |
| `brace-placement` | 206 |
| `underscore-prefix` | 266 |
| `this-prefix` | 286 |
| `reducing-nesting` | 320 |
| `glib-namespace-prefix` | 432 |
| `file-info-try-catch` | 450 |
| `try-catch-scope` | 487 |
| `using-statements` | 571 |
| `switch-case` | 602 |
| `property-initialization` | 643 |
| `gobject-construct-blocks` | 703 |
| `serializable-classes` | 730 |
| `avoiding-nullable-types` | 730 |
| `defensive-code-null-checks` | 776 |
| `line-length-breaking` | 859 |
| `debug-warning-statements` | 903 |
| `gee-hashmap-access` | 983 |
| `gee-arraylist-access` | 1013 |
| `sql-table-aliases` | 1045 |
| `building-strings-in-loops` | 1069 |
| `character-looping` | 1100 |
| `string-array-operations` | 1174 |
| `stringbuilder-usage` | 1194 |
| `arraylist-for-strings` | 1253 |
| `signal-handlers-construct` | 1331 |
| `property-getters-vs-get-methods` | 1355 |
| `method-names-new-methods` | 1535 |
| `agent-compliance-gate` | 1451 |

---

## Other documents (full read when task applies)

| Task | Read in full |
|------|----------------|
| Meson / build files | `docs/build-rules.md` |
| Docblocks / Valadoc markup | `docs/code-documentation.md` |
| Plans in `docs/plans/*` | `docs/guide-to-writing-plans.md` |
| Bug fixes | `docs/bug-fix-process.md` |

---

## Before you say the task is done

1. Re-read section `agent-compliance-gate` in `docs/coding-standards.md`.
2. Run every check in its table on files you changed.
3. For `var` on locals:

```bash
rg '^\s+(string|int|bool|uint|int64|float|double)\s+\w+\s*[=;]' --glob '*.vala' <your-changed-files>
```

Fix every **local** match (not parameters, not fields). Exception: `string[] … = {}`.
