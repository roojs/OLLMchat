# Markdown Renderer Test Suite

Below is a comprehensive example that uses **as many** Markdown features and block types as possible.

Feel free to copy‑paste this into your renderer to see how each element is displayed.

---

## 1. Headings

```markdown
# H1 – Largest heading
## H2 – Second level
### H3 – Third level
#### H4 – Fourth level
##### H5 – Fifth level
###### H6 – Smallest heading
```

# H1 – Largest heading

## H2 – Second level

### H3 – Third level

#### H4 – Fourth level

##### H5 – Fifth level

###### H6 – Smallest heading

---

## 2. Emphasis

```markdown
*Italic* or _Italic_
**Bold** or __Bold__
***Bold + Italic***
~~Strikethrough~~
```

*Italic* or _Italic_

**Bold** or __Bold__

***Bold + Italic***

~~Strikethrough~~

---

## 3. Blockquote

```markdown
> This is a blockquote.
>
> > Nested blockquote.
>
> • It can contain lists
> • **and** other formatting
```

> This is a blockquote.

>

> > Nested blockquote.

>

> • It can contain lists
> • **and** other formatting

---

## 4. Lists

### Unordered List

```markdown
- Item 1
- Item 2
  - Sub‑item 2a
  - Sub‑item 2b
- Item 3
```

- Item 1
- Item 2
  - Sub‑item 2a
  - Sub‑item 2b
- Item 3

### Ordered List

```markdown
1. First
2. Second
   1. Sub‑first
   2. Sub‑second
3. Third
```

1. First
2. Second
   1. Sub‑first
   2. Sub‑second
3. Third

### Task List

```markdown
- [x] Completed task
- [ ] Incomplete task
- [ ] Another pending task
```

- [x] Completed task

- [ ] Incomplete task

- [ ] Another pending task

---

## 5. Tables

```markdown
| Header 1 | Header 2 | Header 3 |
|:--------|:--------:|--------:|
| left    | center   |   right |
| **bold**| *italic* | `code`  |
```

| Header 1 | Header 2 | Header 3 |
| :--- | :---: | ---: |
| left | center | right |
| **bold** | *italic* | `code` |


---

## 6. Horizontal Rule

```markdown
---   (or *** or ___)
```

---

## 7. Links & Images

```markdown
[OpenAI](https://openai.com)

![Placeholder Image](https://via.placeholder.com/150 "Sample Image")
```

[OpenAI](https://openai.com)

![Placeholder Image](https://via.placeholder.com/150 "Sample Image")

---

## 8. Inline Code & Code Blocks

### Inline Code

```markdown
Use the `printf()` function to print text.
```

Use the `printf()` function to print text.

### Fenced Code Blocks (different languages)

#### Python

```python
def greet(name: str) -> str:
    """Return a friendly greeting."""
    return f"Hello, {name}!"
```

#### JavaScript

```javascript
function greet(name) {
    return `Hello, ${name}!`;
}
```

#### Bash

```bash
#!/usr/bin/env bash
echo "Hello, world!"
```

---

## 9. HTML Block (raw HTML)

```markdown
<div style="border:2px solid #4CAF50; padding:10px;">
    <strong>Raw HTML block</strong> – will be rendered as HTML if the renderer allows it.
</div>
```





<div style="border:2px solid #4CAF50; padding:10px;">
    <strong>Raw HTML block</strong> – will be rendered as HTML if the renderer allows it.
</div>

---

## 10. Footnotes

```markdown
Here is a statement with a footnote.[^1]

[^1]: This is the footnote text.
```

Here is a statement with a footnote.[^1]

[^1]: This is the footnote text.

---

## 11. Definition List (CommonMark extension)

```markdown
Term 1
: Definition of term 1.

Term 2
: Definition of term 2, which can be **bold** or *italic*.
```

Term 1

: Definition of term 1.

Term 2

: Definition of term 2, which can be **bold** or *italic*.

---

## 12. Emoji (GitHub‑flavored Markdown)

```markdown
:smile: :rocket: :thumbsup:
```

😄 🚀 👍

---

## 13. Math (KaTeX / LaTeX)

```markdown
Inline math: $E = mc^2$

Display math:

$$
\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
$$
```

Inline math: $E = mc^2$

Display math:

$$

int_{-infty}^{infty} e^{-x^2} dx = sqrt{pi}

$$

---

## 14. Nested Formatting Example

```markdown
> **Note:** You can combine *multiple* formats, such as `code` inside **bold** text, or ~~strikethrough~~ inside a list item.
```

> **Note:** You can combine *multiple* formats, such as `code` inside **bold** text, or ~~strikethrough~~ inside a list item.

---

### End of Test Suite

Feel free to edit, remove, or rearrange any sections to match the capabilities of your specific Markdown renderer. Happy testing!
