<!--
  C2 repro: emoji / icons at the start of Markdown headers (streaming hang).
  Commands:
    build/oc-markdown-test tests/markdown/repro-heading-emoji.md
    build/examples/oc-test-gtkmd --stream 30 tests/markdown/repro-heading-emoji.md
  Full parse: emoji-led ATX lines become <p> with literal "#", not <hN>.
  Stream: BlockMap.peek returns -1 (leftover) until flush — UI appears hung.
-->

# 🚀 Launch checklist

Some intro text after an emoji H1.

## ✅ Done items

Paragraph under a checkmark header.

## ⚠️ Warnings

- bullet one
- bullet two

### 🔧 Setup steps

More body text so streaming has something to chew on after the headers.

## Plain header (control)

This one has no leading emoji — should be a real `<h2>`.

## Header with trailing 🚀 emoji

Alphanumeric-first with emoji later — should still be a heading (isalnum gate passes).
