# Code documentation (Valadoc markup)

Written for **AI agents** — **mandatory** when an agent adds or changes docblocks. Human contributors may treat this as a helpful guide.

This project uses [Vala’s comment markup](https://valadoc.org/markup.htm) for API documentation. Valadoc turns these comments into generated docs (e.g. for valadoc or IDE tooltips).

## Documentation comment structure

Use a single block per symbol: brief line, optional long description, then taglets.

```vala
/**
 * Brief description (one line).
 *
 * Optional longer description: paragraphs separated by a blank comment line.
 * Line breaks within a paragraph are allowed; two spaces after newline for
 * line break in output.
 *
 * @param name description of parameter
 * @return description of return value
 * @throws TypeName when this error is thrown
 */
```

- **Brief**: First line(s) before a blank line; keep short.
- **Long description**: After the first blank line; use full sentences and structure (lists, code, links).
- **Taglets**: At the end; use block taglets for parameters, return value, and errors.

## Line breaks and paragraphs

- One blank comment line `*` = new paragraph in output.
- Same paragraph: no blank line between lines.
- For a visible line break inside a paragraph use `<<BR>>`.

```vala
/**
 * First paragraph,
 * still the first paragraph
 *
 * Second paragraph, first line,<<BR>>
 * second paragraph, second line
 */
```

## Text highlighting

| In comment | In output |
|------------|-----------|
| `''bold''` | **bold** |
| `//italic//` | _italic_ |
| `__underlined__` | underlined |
| `` `block quote` `` | block quote |

Combined: `''//__bold italic underlined__//''` → **_bold italic underlined_**

## Lists

Use a leading space and list marker; two spaces required after newlines for list layout.

As with long `@param` text, **CODING_STANDARDS** line-length guidance is not a reason to wrap a list item so that only a word or two sits alone on the next line—keep a bullet on one line when that reads better, or break at a natural phrase boundary.

- Numbered: ` 1.` or ` #.` or ` i.` / ` I.` or ` a.` / ` A.`
- Bullet: ` *`

```vala
/**
 *  1. First item
 *  1. Second item
 *
 *  * Bullet one
 *  * Bullet two
 */
```

**Multi-line bullet (same item):** [Valadoc list rules](https://valadoc.org/markup.htm) require two spaces after newlines; continuation lines use the same extra indent as nested list lines in that page’s example (` *` then four spaces before the rest of the line: ` *    …`). Use as many continuation lines as needed so no single line is an unreadable run-on (do not start another ` *  *` line, or it becomes a new bullet):

```vala
/**
 *  * First line of the bullet, break after a phrase or punctuation:
 *    second line of the same bullet.
 *    third line still the same bullet.
 */
```

## Code in comments

Use triple braces for **literal code**, identifiers, paths, and CLI tokens — both inline
and as blocks. Valadoc does **not** support Javadoc-style `{@code …}` (CI fails with
`Invalid taglet in this context: code`).

**Inline** (preferred for short names):

```vala
/**
 * Defaults to {{{allow_writes}}} → {{{project}}}; see {@link OLLMbwrap.Bubble}.
 * Daemon hooks live in {{{ollmfilesd}}} or {{{liboctools}}}.
 */
```

**Block** (multi-line samples):

```vala
/**
 * Example:
 *
 * {{{
 *   var list = new List(runner);
 *   yield list.run_all_tasks();
 * }}}
 */
```

| Markup | Valadoc | Use |
|--------|---------|-----|
| `{{{ token }}}` | ✅ | Literals, paths, method names, config keys |
| `{@link Symbol}` | ✅ | Link to a Vala symbol |
| `{@inheritDoc}` | ✅ | Copy parent docblock |
| `{@code …}` | ❌ | **Not valid** — use `{{{ … }}}` |
| `` `backticks` `` | block quote | Not for code — use `{{{ }}}` |

Avoid bare `{` in running text (starts taglets like `{@link}`). Rephrase or wrap in
`{{{ }}}`. **Inside `{{{ … }}}` literals, do not use `{` or `}`** — valadoc treats
them as taglet delimiters and truncates the rendered output (e.g. Hub path templates
like `/api/models/{id}/tree/{rev}` break). Use ALL_CAPS placeholders instead
(`MODEL_ID`, `REVISION`) or describe the shape in prose.

## Links

- `[[http://example.com|label]]` → link with text “label”
- `[[http://example.com]]` → bare URL
- `{@link SymbolName}` → link to a Vala symbol (class, method, property)
- `{@inheritDoc}` → inherit description from parent (e.g. overridden method)

**Package overview wiki (`docs/valadoc-wiki/index.valadoc`):** Valadoc does **not**
resolve relative `[[Page.html|label]]` wiki links in the generated summary body. Use
**full URLs** to the published GitHub Pages docs, e.g.
`[[https://roojs.github.io/OLLMchat/ollmchat/OLLMchat.html|OLLMchat]]`. Keep links
aligned with symbols that exist in `docs/meson.build` (remove stale pages when classes
are deleted). Sidebar navigation is generated separately and still uses relative paths.

## Tables

```vala
/**
 * || ''Header A'' || ''Header B'' ||
 * || cell one    || cell two    ||
 * || cell three  || cell four   ||
 */
```

## Headlines (in long description)

- `= headline 1 =`
- `== headline 2 ==`
- `=== headline 3 ===`
- `==== headline 4 ====`

**valadoc (HTML doc generation):** After a headline line (`== … ==` or `=== … ===`), put a
**blank** documentation line (` * ` only) before the next paragraph. If the first word of a
section body immediately follows a `===` line on the very next line, `valadoc` can fail with
errors such as `unexpected token` on that word. Do **not** put `''…''` markup **inside** the
same line as the `=== … ===` delimiters (put parameters in the body lines below). In
`{{{ … }}}` blocks, avoid a line that contains only a closing brace `}` after ` * ` (e.g. the
closing line of a braced `if`); prefer a one-line `if` without braces or equivalent so the
sample still compiles. For long bullets, use the **Multi-line bullet** indentation under
**Lists** (same idea as nested lines in [Valadoc’s list example](https://valadoc.org/markup.htm));
arbitrary or inconsistent continuation indents can still confuse `valadoc`.

## Block taglets (at end of comment)

| Taglet | Synopsis | Use for |
|--------|----------|--------|
| `@param name description` | Parameter | Each parameter of methods/signals |
| `@return description` | Return value | Non-void methods |
| `@throws TypeName description` | Thrown error | async/throws methods |
| `@since version` | Version | When the API was added |
| `@deprecated version` | Deprecation | When and why deprecated |
| `@see SymbolName` | See also | Related symbol |

### Long `@param` / `@return` / `@throws` text

Prefer **several readable lines** over one very long line. After the first line (` * @param name …`), put each continuation on a new comment line that starts with ` * ` and **two spaces** before the rest of the text, so the description stays one taglet:

```vala
/**
 * @param start_or_count Head mode: line count from the top; ''-1'' or ''0'' = entire file.
 *   Range mode: first line number, **1-based inclusive** (unchanged).
 */
```

This matches common gtk-doc / Valadoc usage and works with `ninja docs/valadoc` (unlike some wiki list continuations in the long description above). **CODING_STANDARDS** suggests keeping docblock lines reasonably short (often cited as ~72 characters); that is **not** a reason to split in the middle of a short phrase or leave a lone word on the next line—prefer natural phrase breaks or leave a slightly longer line.

## Inline taglets (inside text)

- `{@link SymbolName}` — link to another symbol.
- `{@inheritDoc}` — copy description from parent (e.g. overridden method).

**Not supported:** `{@code …}` and other Javadoc taglets. Use `{{{ … }}}` for literals
(see **Code in comments** above).

## Valadoc build (`docs/meson.build`)

Generated HTML docs are built with:

```bash
ninja -C build docs/valadoc
```

CI runs the same target. Keep these in sync when you change the tree:

| When you… | Also update… |
|-----------|----------------|
| Add/remove/rename a `.vala` in any documented library | **`docs/meson.build`** — add the same path to the `valadoc_docs` `input:` list |
| Add a new library subdirectory | Root **`meson.build`** `subdir()` **and** a new block in **`docs/meson.build`** (dependency order) |
| Introduce types used by later files | Put **defining** files **before** users in the valadoc list (same rule as each library's `meson.build`) |

**How valadoc is wired**

- Internal libraries are listed as **source files**, not `--pkg` — using VAPIs duplicates
  definitions and breaks the build (see header comment in `docs/meson.build`).
- External deps stay as `--pkg=…` (gtk4, seccomp, tree-sitter, etc.).
- Linux-only sources (e.g. `libocbwrap/Bubble.vala`, not `libocbwrap/windows/*`) go in
  the list; Windows stub trees are build-only.
- Many library `meson.build` files repeat: *update `docs/meson.build` when sources
  change* — follow that.

**Common ordering traps** (define before use):

- `ollmapp/ChatUserInterface.vala`, `AgentDropdown.vala` before `Window.vala`
- `libocbwrap/*` before `libocmcp/*` (Stdio uses `OLLMbwrap.*`)
- `namespace.vala` / interface files before implementations in each library

After docblock or valadoc-list edits, run `ninja -C build docs/valadoc` locally —
errors are stricter than the Vala compiler (invalid taglets, headline layout, etc.).

## Conventions in this project

1. **Every public class** has a class-level `/** ... */` with at least a brief description; add “Purpose” / “What it does” / “How it fits” where it helps.
2. **Every public method/signal** has a brief description and, where relevant:
   - `@param` for each parameter
   - `@return` for non-void methods
   - `@throws` when the method can throw
3. **Properties** that are part of the public API are documented (brief + optional long).
4. **Private members** may have a short comment when the role is not obvious; full Valadoc is optional.
5. Keep **copyright/license** in the file header as a separate block; do not put Valadoc in the same block as the license.

## Reference

- [Valadoc – Comment Markup](https://valadoc.org/markup.htm)
