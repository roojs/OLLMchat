<!--
  ATX headings whose content starts with bold (**…**).
  Commands:
    build/oc-markdown-test tests/markdown/repro-heading-bold.md
    build/examples/oc-test-gtkmd --stream 30 tests/markdown/repro-heading-bold.md
  Expected: <h3> with bold inside; stream must not leftover until flush.
-->

Intro paragraph.

### **1. Simple Frames/Basic Units**
Body under heading.

### **2. Mid-Range Combinations**
More body.

### **Summary Tip:**
Trailing tip body.
