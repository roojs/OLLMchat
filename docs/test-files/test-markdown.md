# Markdown Parser Test File

This file contains various markdown formatting examples to test the parser.

## Basic Text Formatting

This is plain text with no formatting.

This is *italic text* using asterisks.

This is **bold text** using double asterisks.

This is ***bold and italic*** using triple asterisks.

This is _italic text_ using underscores.

This is __bold text__ using double underscores.

This is ___bold and italic___ using triple underscores.

## Code Formatting

This is `inline code` using backticks.

This is ``double backtick code`` for emphasis.

## Strikethrough

This is ~~strikethrough text~~ using double tildes.

## Escaped Characters

This has an escaped asterisk: \*not italic\*

This has an escaped backtick: \`not code\`

This has an escaped underscore: \_not italic\_

## Nested Formatting

This is **bold with *italic* inside**.

This is *italic with **bold** inside*.

This is `code with *italic* inside` but it shouldn't work.

This is **bold with `code` inside**.

This is ***bold italic with `code` inside***.

## HTML Tags

This is a <span>span tag</span> in the text.

This is a <div class="test">div with attributes</div>.

This is a <strong>strong tag</strong> (should be handled as HTML).

This is a <em>em tag</em> (should be handled as HTML).

This is a <code>code tag</code> (should be handled as HTML).

This is a <del>del tag</del> (should be handled as HTML).

This is a closing tag </span> without opening.

This is an opening tag <span> without closing.

This is a <span class="test" id="myid">span with multiple attributes</span>.

This is a <br>self-closing tag.

This is a <br/>self-closing tag with slash.

## Edge Cases

Empty formatting: ** **

Single asterisk: * (should be literal)

Double asterisk: ** (should be literal if not closed)

Triple asterisk: *** (should be literal if not closed)

Asterisk at end: text*

Asterisk at start: *text

Multiple asterisks: **** (should be bold then literal asterisk)

Backtick at end: text`

Backtick at start: `text

Multiple backticks: ``` (should be code then literal backtick)

## Complex Examples

This is a **bold** word, then *italic*, then `code`, then ~~strikethrough~~, all in one sentence.

This is **bold with *nested italic* and `code`** all together.

This is <span class="highlight">HTML span</span> with **markdown bold** mixed together.

This is `code with **bold** inside` - the bold should not work inside code.

This is **bold with <span>HTML</span> inside** - both should work.

## Long Text Examples

This is a very long paragraph with lots of text to test how the parser handles longer strings. It contains multiple sentences and should be processed correctly. The parser should handle this without issues even when the text is split across multiple chunks or contains various formatting characters scattered throughout.

This paragraph has *italic text* in the middle and **bold text** at the end, with `code` scattered throughout to test nested formatting and edge cases.

## Special Characters

Price: $100.00

Email: test@example.com

URL: https://example.com/path?query=value&other=test

Math: 2 * 2 = 4 (asterisk should be literal)

Path: /usr/bin/valac (slashes should be literal)

Regex: .*test.* (dots should be literal)

## Mixed Formatting Stress Test

***Triple*** **double** *single* asterisks all together.

___Triple___ __double__ _single_ underscores all together.

`code` **bold** *italic* ~~strike~~ all in sequence.

<tag>HTML</tag> **bold** `code` *italic* all mixed.

**Bold start** middle text *italic middle* **bold end**.

*Italic start* middle text **bold middle** *italic end*.

`Code start` middle text **bold middle** `code end`.

## Boundary Testing

Asterisk at word boundary: word*word

Asterisk between words: word * word

Asterisk with punctuation: word*.

Asterisk with comma: word*,

Asterisk with semicolon: word*;

Asterisk with colon: word*:

Backtick at word boundary: word`word

Backtick between words: word ` word

Backtick with punctuation: word`.

Underscore at word boundary: word_word

Underscore between words: word _ word

Underscore with punctuation: word_.

## Real-World Examples

Here's a **real-world** example with *emphasis* and `code snippets`.

Check out this `function_call()` that returns **true** or *false*.

The variable `count` should be **incremented** by *one*.

This is a ~~deprecated~~ feature, use **new_feature** instead.

Visit <a href="https://example.com">example.com</a> for more info.

## Task Lists

- [x] Completed task
- [ ] Incomplete task
- [ ] Sub‑task
  - [x] Done sub‑task
  - [ ] Still pending

## Nested Lists

- Unordered item 1
  - Nested unordered
    - Deeply nested
- Unordered item 2
1. Ordered item 1
2. Ordered item 2
   1. Nested ordered (type‑1)
   2. Another nested ordered
3. Ordered item 3

