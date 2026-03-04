---
name: research_web_page
description: Use after research_online_search to fetch and analyze specific web pages. Refinement makes the tool calls for fetching web pages (e.g. URLs recommended by research_online_search); execution receives the fetched content and analyzes it to produce a concise, actionable summary for plans or implementation.
tools: web_fetch
---

## Refinement

**Purpose of this skill:** Fetch and analyze specific web pages; the executor needs the fetched page content so it can synthesize findings. Refinement **uses the information in the task list summaries** (output summaries from previous tasks) to **create web_fetch requests** — then execution can analyze the fetched content.

You receive **what is needed** for this task and a **summary of the task list so far executed** (including output summaries from previous tasks). **Do not fill in References.** Instead, use the **summaries** to identify URLs or pages to fetch (e.g. pages recommended by research_online_search, or URLs mentioned in prior task results). **Emit web_fetch tool calls** (e.g. **web_fetch** with **url** for each page) from that information. Use URLs from "What is needed", from the task list summaries, or from links in prior task output. There is no "try again" at execution, so issue all fetch calls in refinement.

---

## Execution

You receive a **single output** (the fetched web page content, or combined contents from multiple fetches). Report results based on your analysis of that content.

- **Result summary**: What this task did (synthesized the fetched pages) and whether that answered the goal (enough to proceed / nothing relevant). **List sections of your output as links** — very important, so later tasks can see what is available. **Never use generic titles** like "Detail" or "Synthesis and sample code"; use a **specific** title that states what the section is telling the reader (e.g. "Vala async: yield, main loop, and example of calling async methods", "Example: fetching and parsing API response"). Do not use a literal "Goal:" line.
- **Body section**: Use a **specific heading** that describes what the section tells the reader (e.g. "Example: fetching and calling Vala async methods", "How to parse the JSON response"). Synthesize the findings into a concise summary. Keep key markdown links to sources. When the task is about **how to do something**, add **sample usage** where it helps: code examples, possible solutions, or minimal snippets based on the fetched pages. End with a clear conclusion: enough to proceed, or what additional research or checks are still needed.
- Do not paste long fetched text; use links, short synthesis, and (when appropriate) brief code examples or solution sketches.

### Example output

## Result summary

Synthesized the research into Vala async and main-loop usage — enough to proceed for basic async. See [Vala async: yield, main loop, and example of calling async methods](#vala-async-yield-main-loop-and-example-of-calling-async-methods).

## Vala async: yield, main loop, and example of calling async methods

Vala supports async methods with `async`/`yield` and integrates with [GLib.MainLoop](https://docs.gtk.org/glib/main-loop.html). Callers use `method.begin(callback)` or `yield method()` from another async method. For threading, use GLib.Thread or run async code on the main loop.

**Sample usage** (from the sources): basic async method and caller:

```vala
public async void do_work () {
  yield do_something_async ();
}
// Caller: do_work.begin (() => { ... });
```

Enough information to proceed; no further research needed for basic async usage.
