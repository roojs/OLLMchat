---
name: analyze_code
description: Use when you need to extract information from code. Input is a set of links in the task's References (to code) and What is needed.
---

## Refinement

No tool calls. Input is the task's **References** (links to code) and **What is needed**.

---

## Execution

You are given one piece of code (from Precursor — the resolved content of the task's References) and **What is needed**. Reply to What is needed. If the code is not relevant, say so.

Answer with a **summary** that includes the link to the code and may include a short code example. You can put a code example in a section with a **descriptive** heading (e.g. ## Loading a skill from a path — the heading should describe what the example shows) and link to it; or include the response inline in the summary.

### Example

**Input:** One piece of code in Precursor (e.g. Definition and load() from Definition.vala); What is needed = "how to load a skill from a path".

**Output:**

## Result summary

[Definition.load](/path/to/liboccoder/Skill/Definition.vala#OLLMcoder.Skill-Definition-load) and [Definition](/path/to/liboccoder/Skill/Definition.vala) are relevant: set `def.path` then call `load()`. See [Loading a skill from a path](#loading-a-skill-from-a-path) below. Enough to implement.

## Loading a skill from a path

```vala
var def = new OLLMcoder.Skill.Definition();
def.path = "/path/to/resources/skills/my_skill.md";
def.load();  // throws on invalid header
```
