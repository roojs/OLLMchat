# Code documentation (Valadoc markup)

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

## Code in comments

Use triple braces for code blocks:

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

## Links

- `[[http://example.com|label]]` → link with text “label”
- `[[http://example.com]]` → bare URL
- `{@link SymbolName}` → link to a Vala symbol (class, method, property)
- `{@inheritDoc}` → inherit description from parent (e.g. overridden method)

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

## Block taglets (at end of comment)

| Taglet | Synopsis | Use for |
|--------|----------|--------|
| `@param name description` | Parameter | Each parameter of methods/signals |
| `@return description` | Return value | Non-void methods |
| `@throws TypeName description` | Thrown error | async/throws methods |
| `@since version` | Version | When the API was added |
| `@deprecated version` | Deprecation | When and why deprecated |
| `@see SymbolName` | See also | Related symbol |

## Inline taglets (inside text)

- `{@link SymbolName}` — link to another symbol.
- `{@inheritDoc}` — copy description from parent (e.g. overridden method).

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
