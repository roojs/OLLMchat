---
name: research_pages
description: Use after research_topic to summarize and synthesize its findings. Receives the output from a research_topic task and produces a concise, actionable summary for use in plans or implementation.
---

## Research pages skill

Receives the output from a **research_topic** task (Result summary + Detail) and summarizes the findings.

### Input (this skill)

From the standard input, **Precursor** contains the output from the **research_topic** task (Result summary + Detail). This skill has no tool calls; it interprets the precursor and produces a synthesized summary.

### Output (this skill)

Result summary and Detail. In Result summary: **summary of what this task did** to address the goal and **whether that answered it** (e.g. "Synthesized the research into async usage and sample code — enough to proceed." or "Precursor had nothing relevant."). Do not use a literal "Goal:" line. In Detail: keep markdown links to the most useful sources (URLs from the web search results); include short summaries about each reference and why it is useful. When the query is **how to do something**, include **sample usage** where helpful: code examples, possible solutions, or minimal snippets derived from the researched pages. End with a clear conclusion (enough to proceed or what still needs research).

### Instructions

#### Refinement

- No tool calls. Ensure the task's **References** include the prior **research_topic** task output (refiner adds a link to that task's results so Precursor contains Result summary + Detail).

#### Execution (what to do with the results)

- Read the research_topic output in Precursor (Result summary and Detail). **Result summary**: one or two sentences — **what this task did** (synthesized the research) and **whether that answered the goal** (enough to proceed / precursor had nothing relevant). Summarise the work and outcome; do not start with "Goal:".
- **Detail**: synthesize the findings into a concise summary. Keep key markdown links. When the task is about **how to do something**, add **sample usage** where it helps: code examples, possible solutions, or minimal snippets based on the sources. End with a clear conclusion: enough to proceed, or what additional research or checks are still needed.
- Do not paste long precursor text; use links, short synthesis, and (when appropriate) brief code examples or solution sketches.

### Example

**Input:** (full research_topic output for "async method in Vala" — Result summary + Detail)

**Output:**

## Result summary

Synthesized the research into Vala async and main-loop usage; Detail below gives the pattern and sample code — enough to proceed for basic async.

## Detail

Vala supports async methods with `async`/`yield` and integrates with [GLib.MainLoop](https://docs.gtk.org/glib/main-loop.html). Callers use `method.begin(callback)` or `yield method()` from another async method. For threading, use GLib.Thread or run async code on the main loop.

**Sample usage** (from the sources): basic async method and caller:

```vala
public async void do_work () {
  yield do_something_async ();
}
// Caller: do_work.begin (() => { ... });
```

Enough information to proceed; no further research needed for basic async usage.
