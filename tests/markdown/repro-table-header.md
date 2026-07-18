<!--
  Table border / spacing preview (top rule only; header→table gap).

  Preview:
    build/examples/oc-test-gtkmd tests/markdown/repro-table-header.md

  Session shape (19-35-33): ### heading then table with a single \\n — no blank line.
-->

## Variant: normal paragraph before table

Here is a normal sentence immediately above the table (no heading). Compare the gap to the heading cases below.

| Col | Value |
|-----|-------|
| alpha | 1 |
| beta | 2 |

Text right after that table (should sit close if bottom padding is small).

---

Lead-in paragraph so you can compare spacing above the first heading.

### Summary Recommendation
| Model Size | Feasibility | Performance | Recommended Quantization |
| :--- | :--- | :--- | :--- |
| **1B - 3B** | ✅ Excellent | Fast | Q8_0 or FP16 |
| **7B - 9B** | ✅ Great | Smooth | Q4_K_M or Q5_K_M |
| **12B - 30B** | ✅ Good | Moderate/Slow | Q4_K_M |
| **70B+** | ⚠️ Possible | Very Slow | Q3_K_S or Q4_K_S |

**Suggested Software Path:** after the table (bold line, no heading).

---

## Variant: blank line before table

### With blank line

| A | B |
|---|---|
| 1 | 2 |

---

## Variant: table only (no heading)

| Left | Center | Right |
|:-----|:------:|------:|
| a | b | longer cell so column widths differ |
| d | e | another row |

---

## Variant: list then table

Before the table, a short list:

- First item
- Second item

| Col1 | Col2 |
|------|------|
| *x* | **bold** and `code` |
