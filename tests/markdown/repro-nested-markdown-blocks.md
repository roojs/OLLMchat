<!--
  Three separate ```markdown fenced blocks in one document. Each fence becomes its own
  nested MarkdownGtk.Render (same stacking model as multiple framed blocks in chat).

  oc-test-gtkmd (do not use --thinking here — that wraps the whole file as one thinking block):

    build/examples/oc-test-gtkmd --stream 0 tests/markdown/repro-nested-markdown-blocks.md
    build/examples/oc-test-gtkmd --stream 50 tests/markdown/repro-nested-markdown-blocks.md

  Reload while streaming to stress clear/teardown with multiple nested trees.
-->

# Nested markdown frames (three blocks)

Intro paragraph with **bold** before any fence.

## Block 1 — lists

```markdown
## Inside block 1

- Item with **bold** and `inline code`.
- Second item referencing a path: `tests/markdown/repro-chatview-thinking-lines.md`.
```

## Block 2 — table

```markdown
## Inside block 2

| Left | Right |
|:-----|------:|
| *a*  | **b** |
| wide | This cell has extra text so column sizing does something visible. |
```

## Block 3 — short

```markdown
Third nested renderer: *italic*, **strong**, and a `final()` token.
```

Trailing **body** markdown after all nested blocks — exercises layout after nested teardown boundaries.
